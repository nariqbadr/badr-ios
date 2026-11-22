import SwiftUI
import CoreLocation
import CoreMotion

/// the bearing (degrees from north) from a to b
func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
    let la1 = a.latitude * .pi / 180, la2 = b.latitude * .pi / 180, dl = (b.longitude - a.longitude) * .pi / 180
    let y = sin(dl) * cos(la2), x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dl)
    return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}

private let stepHadith = "«من تطهّر في بيته ثم مشى إلى بيت من بيوت الله ليقضي فريضة من فرائض الله، كانت خطوتاه إحداهما تحطّ خطيئة، والأخرى ترفع درجة» — رواه مسلم"

/// «تلحق الجماعة؟»: for my mosque (else the nearest) — the coming prayer, when its iqama is, the walk there, and when to
/// leave; a ring empties as the time to leave comes near.
struct CatchCard: View {
    let m: Mosque; let isMine: Bool; let onGo: () -> Void
    @ObservedObject private var mq = Mosques.shared
    @ObservedObject private var prayers = Prayers.shared
    @Environment(\.pal) private var c
    @Environment(\.openURL) private var openURL
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            if let j = mq.nextJamaah() { card(ctx.date, j.0, j.1, j.2) }
        }
    }
    private func card(_ now: Date, _ p: PrayerTime, _ iq: Date, _ friday: Bool) -> some View {
        let walk = Mosques.walkS(mq.dist(m))
        let left = iq.timeIntervalSince(now) - walk - 120
        let far = p.time.timeIntervalSince(now) > 3 * 3600
        let ok = Color(red: 0.25, green: 0.75, blue: 0.5)
        let iqT = L.digits(Fmt.time(iq)), wT = Mosques.mins(walk)
        let head: String, sub: String, col: Color
        if far { head = tr("الصلاة القادمة: {0}", p.name); sub = tr("الأذان {0} · الإقامة {1}", L.digits(Fmt.time(p.time)), iqT); col = c.gold }
        else if left > 60 { head = tr("اخرج خلال {0} لتلحق الجماعة", Mosques.mins(left)); sub = tr("إقامة {0} {1} · المشي {2}", p.name, iqT, wT); col = ok }
        else if left > -240 { head = tr("اخرج الآن لتلحق {0}", p.name); sub = tr("الإقامة {0} · المشي {1}", iqT, wT); col = c.gold }
        else { head = tr("قد تفوتك تكبيرة الإحرام في {0}", p.name); sub = tr("أسرع إن خرجت الآن — والصلاة في جماعة خير"); col = c.danger }
        let frac: Double = far ? 1 : min(1, max(0, left / 3600))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(friday ? tr("الجمعة") : tr("تلحق الجماعة؟")).font(F.plex(12.5, .bold)).foregroundStyle(col)
                    Text(head).font(F.amiri(20, bold: true)).foregroundStyle(c.text).fixedSize(horizontal: false, vertical: true)
                    Text(sub).font(F.plex(12.5)).foregroundStyle(c.muted).fixedSize(horizontal: false, vertical: true)
                    Text((isMine ? tr("مسجدي: ") : tr("أقرب مسجد: ")) + m.title).font(F.plex(12.5)).foregroundStyle(c.text.opacity(0.8)).lineLimit(1)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(c.line, lineWidth: 6)
                    Circle().trim(from: 0, to: frac).stroke(col, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: frac)
                    VStack(spacing: 1) {
                        SiteIcon(name: "walk", size: 20, color: col)
                        Text(Mosques.mins(walk)).font(F.plex(12, .bold)).foregroundStyle(c.text)
                    }
                }.frame(width: 76, height: 76)
            }
            HStack(spacing: 8) {
                GoldButton(title: tr("انطلق إلى المسجد"), icon: "walk", action: onGo).frame(maxWidth: .infinity)
                GhostButton(title: tr("الخرائط"), icon: "pin") {
                    if let u = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(m.lat),\(m.lng)&travelmode=walking") { openURL(u) }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26).fill(LinearGradient(colors: [col.opacity(0.16), c.surface], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(col.opacity(0.5)))
    }
}

/// The mosques around on a dial that turns with the phone: each one a dot at its bearing and distance, the Kaaba on the
/// rim at the qibla, rings at 500 m, 1 km and 2 km. Tap a dot to choose that mosque.
struct MosqueDial: View {
    let list: [Mosque]; let selected: String?; let pick: (Mosque) -> Void
    @ObservedObject private var mq = Mosques.shared
    @StateObject private var compass = Compass()
    @Environment(\.pal) private var c
    @State private var pulse = false
    private var far: Double { max(600, min(3500, list.prefix(12).map { mq.dist($0) }.max() ?? 1000) * 1.12) }
    var body: some View {
        if let here = mq.pos { card(here) }
    }
    private func card(_ here: CLLocationCoordinate2D) -> some View {
        let hd = compass.heading
        return VStack(spacing: 10) {
            HStack {
                Text(tr("المساجد حولك")).font(F.plex(15, .bold)).foregroundStyle(c.gold)
                Spacer()
                Text(hd == nil ? tr("الشمال أعلى") : tr("يدور مع جوالك")).font(F.plex(11)).foregroundStyle(c.muted)
            }
            GeometryReader { g in dial(here, g.size, -(hd ?? 0)) }
                .aspectRatio(1, contentMode: .fit).padding(.horizontal, 10)
                .environment(\.layoutDirection, .leftToRight)
            Text(tr("الخط الذهبي إلى الكعبة · النقاط مساجد · الدوائر ٥٠٠ م و١ كم و٢ كم")).font(F.plex(11)).foregroundStyle(c.faint).multilineTextAlignment(.center)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26).fill(c.surface.opacity(0.7))).overlay(RoundedRectangle(cornerRadius: 26).stroke(c.lineSoft))
        .onAppear { compass.start(); withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
        .onDisappear { compass.stop() }
    }
    private static func at(_ o: CGPoint, _ r: CGFloat, _ b: Double, _ f: Double, _ rot: Double) -> CGPoint {
        let t = (b + rot) * .pi / 180
        return CGPoint(x: o.x + CGFloat(sin(t) * f) * r, y: o.y - CGFloat(cos(t) * f) * r)
    }
    private func dial(_ here: CLLocationCoordinate2D, _ size: CGSize, _ rot: Double) -> some View {
        let side = min(size.width, size.height), r: CGFloat = side / 2 - 14, o = CGPoint(x: size.width / 2, y: size.height / 2)
        let q = Prayers.shared.qibla(), far = far
        return ZStack {
            Canvas { ctx, _ in draw(&ctx, o, r, rot, q, far) }
            Circle().stroke(c.gold.opacity(pulse ? 0 : 0.35), lineWidth: 2).frame(width: pulse ? 2 * r : 10, height: pulse ? 2 * r : 10).position(o)
            kaaba.position(Self.at(o, r, q, 1, rot))
            ForEach(list.prefix(25)) { m in
                dot(m).position(Self.at(o, r, bearing(here, m.coord), min(1, mq.dist(m) / far), rot))
            }
        }
    }
    private var kaaba: some View {
        RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.08))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(c.gold, lineWidth: 1.5))
            .overlay(Rectangle().fill(c.gold).frame(height: 2.5).offset(y: -3))
            .frame(width: 22, height: 22)
    }
    private func dot(_ m: Mosque) -> some View {
        let on = m.id == selected
        let size: CGFloat = on ? 16 : 10
        return Button { pick(m) } label: {
            Circle().fill(on ? c.gold : c.gold2.opacity(0.75)).overlay(Circle().stroke(c.bg2, lineWidth: 2))
                .frame(width: size, height: size).frame(width: 30, height: 30).contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel(m.title)
    }
    private func draw(_ ctx: inout GraphicsContext, _ o: CGPoint, _ r: CGFloat, _ rot: Double, _ q: Double, _ far: Double) {
        let disc = Path(ellipseIn: CGRect(x: o.x - r, y: o.y - r, width: 2 * r, height: 2 * r))
        ctx.fill(disc, with: .radialGradient(Gradient(colors: [c.surface3, c.surface, c.bg2]), center: o, startRadius: 0, endRadius: r))
        for k: Double in [500, 1000, 2000, 3000] where k < far {
            let rr = r * CGFloat(k / far)
            ctx.stroke(Path(ellipseIn: CGRect(x: o.x - rr, y: o.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(c.line), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
        ctx.stroke(disc, with: .color(c.gold.opacity(0.55)), lineWidth: 2.5)
        for i in 0..<72 {
            let major = i % 18 == 0
            let len: CGFloat = major ? 10 : 4
            var l = Path()
            l.move(to: Self.at(o, r, Double(i) * 5, 1, rot))
            l.addLine(to: Self.at(o, r - len, Double(i) * 5, 1, rot))
            ctx.stroke(l, with: .color(i == 0 ? c.danger : c.faint), style: StrokeStyle(lineWidth: major ? 3 : 1.2, lineCap: .round))
        }
        // the qibla: a line to the rim
        let end = Self.at(o, r, q, 1, rot)
        var ql = Path(); ql.move(to: o); ql.addLine(to: end)
        ctx.stroke(ql, with: .linearGradient(Gradient(colors: [.clear, c.gold.opacity(0.7)]), startPoint: o, endPoint: end), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 4]))
        ctx.fill(Path(ellipseIn: CGRect(x: o.x - 6, y: o.y - 6, width: 12, height: 12)), with: .color(c.gold))
        ctx.fill(Path(ellipseIn: CGRect(x: o.x - 2.5, y: o.y - 2.5, width: 5, height: 5)), with: .color(c.surface))
    }
}

/// «خطواتك إلى المسجد»: this week's steps to the mosque, the walks of the last seven days, and the hadith.
struct StepsCard: View {
    @ObservedObject private var mq = Mosques.shared
    @Environment(\.pal) private var c
    var body: some View {
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        let days: [(Int, Date)] = (0...6).reversed().map { d in
            let from = cal.date(byAdding: .day, value: -d, to: today)!, to = cal.date(byAdding: .day, value: 1, to: from)!
            return (mq.walks.filter { $0.at >= from && $0.at < to }.reduce(0) { $0 + $1.steps }, from)
        }
        let top = max(1, days.map(\.0).max() ?? 1)
        let f = DateFormatter(); f.locale = L.locale; f.dateFormat = "EEE"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("خطواتك إلى المسجد")).font(F.plex(15, .bold)).foregroundStyle(c.gold)
                    Text(tr("هذا الأسبوع")).font(F.plex(12)).foregroundStyle(c.muted)
                }
                Spacer()
                Text(mq.weekSteps().ar).font(F.amiri(30, bold: true)).foregroundStyle(c.text)
                Text(tr("خطوة")).font(F.plex(13)).foregroundStyle(c.muted)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<days.count, id: \.self) { i in
                    let (v, d) = days[i]
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 6).fill(v > 0 ? c.gold : c.line).frame(height: max(3, 44 * CGFloat(v) / CGFloat(top)))
                        Text(String(f.string(from: d).prefix(3))).font(F.plex(10)).foregroundStyle(c.faint).lineLimit(1)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 64, alignment: .bottom)
            Text(tr(stepHadith)).font(F.plex(12.5)).foregroundStyle(c.muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26).fill(c.surface.opacity(0.7))).overlay(RoundedRectangle(cornerRadius: 26).stroke(c.lineSoft))
    }
}

/// «الجمعة»: on Thursday evening and Friday it comes first; the sunnahs and the reminder before the prayer.
struct JumuahCard: View {
    @ObservedObject private var mq = Mosques.shared
    @Environment(\.pal) private var c
    var body: some View {
        let friday = Calendar.current.component(.weekday, from: Date()) == 6
        let dhuhr = Prayers.shared.forDay().first { $0.key == "dhuhr" }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(friday ? tr("اليوم الجمعة") : tr("الجمعة")).font(F.plex(15, .bold)).foregroundStyle(c.gold)
                    Text(friday && dhuhr != nil ? tr("الصلاة في وقت الظهر {0}", L.digits(Fmt.time(dhuhr!.time))) : mq.mine.map { tr("في مسجدك: {0}", $0.title) } ?? tr("اختر مسجدك ليصلك التذكير باسمه"))
                        .font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(2)
                }
                Spacer()
                SiteIcon(name: "mosque", size: 30, color: c.gold)
            }
            if friday {
                FlowWrap(spacing: 6) {
                    ForEach(["الغسل والطيب", "التبكير إلى المسجد", "سورة الكهف", "الإكثار من الصلاة على النبي ﷺ", "ساعة الإجابة آخر العصر"], id: \.self) { s in
                        Text(tr(s)).font(F.plex(12)).foregroundStyle(c.text).padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(c.gold.opacity(0.12)))
                    }
                }
            }
            Text(tr("ذكّرني قبل الجمعة")).font(F.plex(14, .semibold)).foregroundStyle(c.text)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach([0, 30, 45, 60, 90], id: \.self) { m in
                        Pill(title: m == 0 ? tr("بدون") : tr("{0} د", m.ar), on: mq.jumuahMin == m) { mq.setJumuah(m) }
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26).fill(friday ? AnyShapeStyle(LinearGradient(colors: [c.gold.opacity(0.18), c.surface], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(c.surface.opacity(0.7))))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(friday ? c.gold.opacity(0.5) : c.lineSoft))
    }
}

/// a simple wrapping row (the sunnahs of Friday)
struct FlowWrap: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity; var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews { let z = s.sizeThatFits(.unspecified); if x > 0 && x + z.width > w { x = 0; y += row + spacing; row = 0 }; x += z.width + spacing; maxX = max(maxX, x - spacing); row = max(row, z.height) }
        return CGSize(width: w.isFinite ? w : maxX, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > b.width { x = 0; y += row + spacing; row = 0 }
            let px = b.minX + x
            s.place(at: CGPoint(x: px, y: b.minY + y), proposal: ProposedViewSize(z)); x += z.width + spacing; row = max(row, z.height)
        }
    }
}

/// Steps and distance while walking to the mosque: the phone's location (each fix) and its pedometer.
@MainActor
final class WalkTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var pos: CLLocationCoordinate2D?
    @Published var walked = 0.0
    @Published var steps = 0
    private let lm = CLLocationManager(), ped = CMPedometer()
    private var last: CLLocation?
    func start() {
        lm.delegate = self; lm.desiredAccuracy = kCLLocationAccuracyBest; lm.distanceFilter = 3; lm.startUpdatingLocation()
        if CMPedometer.isStepCountingAvailable() {
            ped.startUpdates(from: Date()) { [weak self] d, _ in
                guard let n = d?.numberOfSteps.intValue else { return }
                Task { @MainActor in self?.steps = n }
            }
        }
    }
    func stop() { lm.stopUpdatingLocation(); ped.stopUpdates() }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for l in locations where l.horizontalAccuracy >= 0 && l.horizontalAccuracy < 80 {
                if let o = last { walked += min(80, l.distance(from: o)) }
                last = l; pos = l.coordinate
            }
        }
    }
}

/// «في الطريق إلى المسجد»: while walking — the distance left and the steps (from the pedometer, else from the distance
/// walked); it ends by itself near the mosque, or with «وصلت».
struct WalkSheet: View {
    let m: Mosque
    @StateObject private var t = WalkTracker()
    @ObservedObject private var mq = Mosques.shared
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var done = false
    @State private var start = Date()
    private var left: Double { t.pos.map { Mosques.d($0, m.coord) } ?? mq.dist(m) }
    private var shown: Int { t.steps > 0 ? t.steps : Int((t.walked / 0.72).rounded()) }
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SheetHead(title: tr("في الطريق إلى المسجد"))
                VStack(spacing: 12) {
                    Text(m.title).font(F.amiri(22, bold: true)).foregroundStyle(c.text).multilineTextAlignment(.center)
                    if done {
                        SiteIcon(name: "mosque", size: 44, color: c.gold)
                        Text(tr("وصلت — كُتب لك بكل خطوة أجر بإذن الله")).font(F.plex(16, .bold)).foregroundStyle(c.gold).multilineTextAlignment(.center)
                        Text(tr("{0} خطوة إلى بيت الله", shown.ar)).font(F.plex(14)).foregroundStyle(c.text)
                        GoldButton(title: tr("تم"), icon: "check") { dismiss() }.frame(maxWidth: .infinity)
                    } else {
                        HStack {
                            stat(shown.ar, tr("خطوة")); stat(Mosques.km(left), tr("متبقٍّ")); stat(Mosques.mins(Mosques.walkS(left)), tr("مشيًا"))
                        }
                        let all = max(1, mq.dist(m))
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(c.line)
                                Capsule().fill(c.gold).frame(width: g.size.width * min(1, max(0.02, 1 - left / all)))
                            }
                        }.frame(height: 8).animation(.easeOut(duration: 0.5), value: left)
                        Text(tr(stepHadith)).font(F.plex(12.5)).foregroundStyle(c.muted).multilineTextAlignment(.center).lineSpacing(4)
                        GoldButton(title: tr("وصلت"), icon: "check") { finish() }.frame(maxWidth: .infinity)
                    }
                }.padding(.horizontal, 22).padding(.bottom, 16)
            }
        }
        .environment(\.layoutDirection, L.dir)
        .presentationDetents([.medium, .large])
        .onAppear { start = Date(); t.start() }
        .onDisappear { finish(); t.stop() }
        .onChange(of: left) { v in if v < 35 && Date().timeIntervalSince(start) > 20 { finish() } }
    }
    private func finish() {
        guard !done else { return }
        done = true
        if shown > 0 || t.walked > 20 { mq.addWalk(.init(at: Date(), steps: max(shown, 1), meters: Int(t.walked.rounded()), name: m.title)) }
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) { Text(v).font(F.amiri(26, bold: true)).foregroundStyle(c.text); Text(l).font(F.plex(12)).foregroundStyle(c.muted) }.frame(maxWidth: .infinity)
    }
}
