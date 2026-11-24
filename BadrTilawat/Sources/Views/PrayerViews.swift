import SwiftUI
import CoreLocation
import UserNotifications

/// Adhkar like the site: one dhikr at a time with a big counter (or the full list); the counts reset every day.
struct AdhkarView: View {
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var tab = { if RootView.shot == "adhkarEve" { return "evening" }; let h = Calendar.current.component(.hour, from: Date()); return (3...12).contains(h) ? "morning" : (13...20).contains(h) ? "evening" : "sleep" }()
    @AppStorage("adhkarList") private var listMode = false
    @State private var counts: [Int] = []
    @State private var page = 0
    @State private var fadlOpen: String? = nil
    private static let data: [String: [(text: String, count: Int, src: String, fadl: String)]] = {
        guard let u = Bundle.main.url(forResource: "adhkar", withExtension: "json"), let d = try? Data(contentsOf: u) else { return [:] }
        return J(data: d).dict.mapValues { $0.array.map { (text: $0["text"].str, count: max(1, $0["count"].int), src: $0["src"].str, fadl: $0["fadl"].str) } }
    }()
    /// «مرة واحدة», «٣ مرات», «١٠٠ مرة»
    static func times(_ n: Int) -> String { n == 1 ? tr("مرة واحدة") : n == 2 ? tr("مرتان") : (3...10).contains(n) ? tr("{0} مرات", n.ar) : tr("{0} مرة", n.ar) }
    /// the line under a dhikr: where it is narrated and how many times
    private static func note(_ src: String, _ n: Int) -> String { [src, times(n)].filter { !$0.isEmpty }.joined(separator: " · ") }
    private static func text(_ t: String) -> String {
        let r = try! NSRegularExpression(pattern: "\\s*\\((\\d+)\\)"); var s = t.trimmingCharacters(in: .whitespaces)
        for m in r.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() { if let g = Range(m.range, in: s), let n = Range(m.range(at: 1), in: s) { s.replaceSubrange(g, with: " \(ReadText.mark(Int(s[n])?.ar ?? ""))") } }
        // each line right-to-left: a line that ends with the ayah mark kept its brackets facing the right way
        return L.rtl ? s.components(separatedBy: "\n").map { $0.isEmpty ? $0 : rtlText($0) }.joined(separator: "\n") : s
    }
    private func key(_ i: Int) -> String { "dk-\(Wird.today)-\(tab)-\(i)" }
    var body: some View {
        let cats = [("morning", tr("الصباح")), ("evening", tr("المساء")), ("sleep", tr("النوم"))].filter { !(AdhkarView.data[$0.0] ?? []).isEmpty } + [("friday", tr("سنن يوم الجمعة"))]
        let list = AdhkarView.data[tab] ?? []
        let done = list.indices.filter { (counts[safe: $0] ?? 0) >= list[$0].count }.count
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Seg(items: cats.map { $0.1 }, selected: cats.firstIndex { $0.0 == tab } ?? 0, fit: true) { tab = cats[$0].0 }
                if tab != "friday" { Chip(text: nil, icon: listMode ? "rectangle.portrait" : "list.bullet", on: listMode) { listMode.toggle() } }
            }.padding(.horizontal, 16).padding(.vertical, 8)
            if tab == "friday" { FridayView() } else {
            HStack(spacing: 10) {
                // one segment for each dhikr: done in gold, the open one half gold
                HStack(spacing: 2) {
                    ForEach(list.indices, id: \.self) { k in
                        let fin = (counts[safe: k] ?? 0) >= list[k].count
                        RoundedRectangle(cornerRadius: 2).fill(fin ? c.gold : (!listMode && k == page) ? c.gold.opacity(0.45) : c.lineSoft).frame(height: 4)
                    }
                }.frame(maxWidth: .infinity).animation(.easeOut(duration: 0.3), value: done)
                Text(listMode ? tr("أنجزت {0} من {1}", done.ar, list.count.ar) : tr("{0} من {1} — أنجزت {2}", (page + 1).ar, list.count.ar, done.ar)).font(F.plex(12.5, .medium)).foregroundStyle(c.muted)
            }.padding(.horizontal, 18).padding(.vertical, 2)
            if list.isEmpty { Empty(text: tr("لا توجد أذكار")); Spacer() }
            else if listMode {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(list.enumerated()), id: \.offset) { i, dk in
                            let n = counts[safe: i] ?? 0, fin = n >= dk.count
                            Panel(pad: 18, lattice: false) {
                                Text(AdhkarView.text(dk.text)).font(F.amiri(20, bold: false)).foregroundStyle(fin ? c.muted : c.text).lineSpacing(14)
                                Text(AdhkarView.note(dk.src, dk.count)).font(F.plex(12, .medium)).foregroundStyle(c.muted).padding(.top, 6)
                                HStack(spacing: 12) {
                                    ZStack { Circle().fill(fin ? AnyShapeStyle(c.goldBrush) : AnyShapeStyle(c.surface3)); if fin { SiteIcon(name: "check", size: 22, color: c.onGold) } else { Text((dk.count - n).ar).font(F.plex(16, .semibold)).foregroundStyle(c.gold) } }.frame(width: 44, height: 44)
                                    Text(fin ? tr("اكتمل") : tr("اضغط للعدّ")).font(F.plex(12.5)).foregroundStyle(c.muted)
                                }.padding(.top, 12)
                            }.contentShape(Rectangle()).onTapGesture { if !fin { count(i, list) } }
                        }
                    }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 24)
                }
            } else {
                TabView(selection: $page) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, dk in
                        let n = counts[safe: i] ?? 0, left = max(0, dk.count - n), fin = left == 0
                        VStack(spacing: 0) {
                            // the card is as tall as the dhikr; a long one takes the space there is and is read by dragging inside it
                            let t = Text(AdhkarView.text(dk.text)).font(F.amiri(22, bold: false)).foregroundStyle(c.text).lineSpacing(16).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                            Panel(pad: 18) {
                                ViewThatFits(in: .vertical) {
                                    t.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
                                    ScrollView(showsIndicators: true) { t.padding(.vertical, 4) }
                                }
                                DashLine().padding(.top, 12).padding(.bottom, 8)
                                let open = fadlOpen == "\(tab)-\(i)"
                                HStack(spacing: 8) {
                                    Text(AdhkarView.note(dk.src, dk.count)).font(F.plex(12, .medium)).foregroundStyle(c.muted)
                                    // «فضله»: the dhikr's virtue opens under it
                                    if !dk.fadl.isEmpty {
                                        Button { withAnimation(.easeOut(duration: 0.25)) { fadlOpen = open ? nil : "\(tab)-\(i)" } } label: {
                                            HStack(spacing: 4) { Text(tr("فضله")).font(F.plex(11.5, .semibold)); SiteIcon(name: "chev-d", size: 14, color: c.gold2).rotationEffect(.degrees(open ? 180 : 0)) }
                                                .foregroundStyle(c.gold2).padding(.horizontal, 9).padding(.vertical, 3)
                                                .overlay(Capsule().stroke(c.gold.opacity(0.45), lineWidth: 1))
                                        }.buttonStyle(.plain)
                                    }
                                }.frame(maxWidth: .infinity)
                                if open && !dk.fadl.isEmpty {
                                    Text(dk.fadl).font(F.plex(12.5, .medium)).foregroundStyle(c.gold2).lineSpacing(5).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                                        .padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 10).fill(c.gold.opacity(0.08))).padding(.top, 10)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }.layoutPriority(1)
                            // the card itself counts too
                            .contentShape(Rectangle()).onTapGesture { count(i, list) }
                            Button { count(i, list) } label: {
                                ZStack {
                                    Circle().fill(c.surface2)
                                    Circle().stroke(c.lineSoft, lineWidth: 8).padding(6)
                                    Circle().trim(from: 0, to: dk.count > 0 ? Double(n) / Double(dk.count) : 1).stroke(c.goldBrush, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90)).padding(6)
                                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: n)
                                    VStack(spacing: 0) {
                                        if fin { SiteIcon(name: "check", size: 52, color: c.gold) } else { Text(left.ar).font(F.plex(46, .bold)).foregroundStyle(c.gold) }
                                        Text(fin ? tr("اكتمل") : tr("اضغط للعدّ")).font(F.plex(12.5, .medium)).foregroundStyle(c.muted)
                                    }
                                }.frame(width: 150, height: 150)
                            }.buttonStyle(Press(scale: 0.92)).padding(.top, 16)
                            HStack(spacing: 8) {
                                Button { withAnimation { page = max(0, i - 1) } } label: { SiteIcon(name: "chev-r", size: 24, color: c.text).frame(width: 44, height: 44) }.accessibilityLabel(tr("السابق"))
                                Chip(text: nil, icon: "copy") { UIPasteboard.general.string = AdhkarView.text(dk.text); ui.say(tr("نُسخ الذكر")) }
                                Chip(text: nil, icon: "arrow.counterclockwise") { UserDefaults.standard.set(0, forKey: key(i)); if counts.indices.contains(i) { counts[i] = 0 } }
                                Button { withAnimation { page = min(list.count - 1, i + 1) } } label: { SiteIcon(name: "chev-l", size: 24, color: c.text).frame(width: 44, height: 44) }.accessibilityLabel(tr("التالي"))
                            }.padding(.vertical, 14)
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 18).padding(.vertical, 10).tag(i)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
            }
            }
        }
        .onAppear { if let t = ui.adhkarTab { tab = t; ui.adhkarTab = nil }; load(AdhkarView.data[tab] ?? []) }
        .onReceive(ui.$adhkarTab) { t in if let t { tab = t; DispatchQueue.main.async { ui.adhkarTab = nil } } }
        .onChange(of: tab) { _ in let l = AdhkarView.data[tab] ?? []; load(l) }
    }
    private func load(_ list: [(text: String, count: Int, src: String, fadl: String)]) {
        counts = list.indices.map { UserDefaults.standard.integer(forKey: key($0)) }
        page = list.indices.first { counts[$0] < list[$0].count } ?? 0
    }
    private func count(_ i: Int, _ list: [(text: String, count: Int, src: String, fadl: String)]) {
        let n = counts[safe: i] ?? 0
        if n >= list[i].count { if i < list.count - 1 { withAnimation { page = i + 1 } }; return }
        let v = n + 1; counts[i] = v; UserDefaults.standard.set(v, forKey: key(i))
        if v >= list[i].count { UINotificationFeedbackGenerator().notificationOccurred(.success) } else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        if v >= list[i].count && i < list.count - 1 && !listMode { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { withAnimation { page = i + 1 } } }
    }
}

/// Prayer times page (like the Android app): the next prayer with a countdown ring, today's times with each alert, settings, the qibla.
struct PrayerView: View {
    @EnvironmentObject var prayers: Prayers
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var modes: [String: String] = [:]
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let list = prayers.forDay(), now = ctx.date
                    if let n = prayers.next() {
                        let prev = list.last { $0.key != "sunrise" && $0.time <= now }
                        let left = max(0, Int(n.time.timeIntervalSince(now)))
                        let span = max(1, n.time.timeIntervalSince(prev?.time ?? n.time.addingTimeInterval(-6 * 3600)))
                        let frac = 1 - min(1, max(0, Double(left) / span))
                        NextPanel(n: n, left: left, frac: frac)
                        PrayerTimeline(now: now)
                    }
                }.id(prayers.rev)
                HStack(spacing: 10) {
                    GhostButton(title: tr("صوت الأذان"), icon: "volume") { ui.sheet = .prayer }.frame(maxWidth: .infinity)
                    GhostButton(title: tr("الموقع والتنبيهات"), icon: "slider.horizontal.3") { ui.sheet = .prayer }.frame(maxWidth: .infinity)
                }
                QiblaCard()
            }.padding(16).padding(.bottom, 10)
        }
    }
}

/// The prayer page's head: the next prayer in its ring (a clock's marks round it), the time left, then its adhan and iqama.
struct NextPanel: View {
    @EnvironmentObject var prayers: Prayers
    private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    let n: PrayerTime; let left: Int; let frac: Double
    var body: some View {
        Panel(pad: 16, lattice: false) {
            VStack(spacing: 0) {
                HStack {
                    Button { ui.sheet = .prayer } label: {
                        HStack(spacing: 4) { SiteIcon(name: "pin", size: 17, color: c.gold); Text(prayers.place.isEmpty ? tr("حدّد مدينتك") : prayers.place).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(1); SiteIcon(name: "chev-d", size: 20, color: c.muted) }.padding(.vertical, 6)
                    }.buttonStyle(.plain)
                    Spacer()
                    Text(Prayers.hijri()).font(F.plex(12)).foregroundStyle(c.muted).lineLimit(1)
                }
                ZStack {
                    // a clock's marks round the ring, then the ring and its knob
                    ForEach(0..<60, id: \.self) { i in
                        Rectangle().fill(c.text.opacity(i % 5 == 0 ? 0.35 : 0.14)).frame(width: 1.2, height: i % 5 == 0 ? 6 : 4)
                            .offset(y: -102 + (i % 5 == 0 ? 0 : 1)).rotationEffect(.degrees(Double(i) * 6))
                    }
                    Circle().stroke(c.text.opacity(0.07), lineWidth: 5).padding(17)
                    Circle().trim(from: 0, to: frac).stroke(c.goldBrush, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90)).padding(17)
                    Circle().fill(c.gold2).frame(width: 12, height: 12).overlay(Circle().stroke(c.surface, lineWidth: 2.5))
                        .offset(y: -88).rotationEffect(.degrees(360 * frac))
                    VStack(spacing: 0) {
                        Text(tr("الصلاة القادمة")).font(F.plex(12, .medium)).foregroundStyle(c.muted)
                        Text(n.name).font(F.amiri(36)).foregroundStyle(c.goldBrushV)
                        Text(hms(left)).font(F.amiri(28)).foregroundStyle(c.text).monospacedDigit().environment(\.layoutDirection, .leftToRight)
                    }
                }.frame(width: 210, height: 210).padding(.top, 8)
                HStack(spacing: 0) {
                    VStack(spacing: 1) { Text(tr("الأذان")).font(F.plex(11.5)).foregroundStyle(c.muted); Text(Fmt.time(n.time)).font(F.amiri(18)).foregroundStyle(c.text) }.frame(maxWidth: .infinity).padding(.vertical, 10)
                    Rectangle().fill(c.text.opacity(0.07)).frame(width: 1, height: 52)
                    VStack(spacing: 1) { Text(tr("الإقامة")).font(F.plex(11.5)).foregroundStyle(c.muted); Text(prayers.iqamaAt(n).map { Fmt.time($0) } ?? "—").font(F.amiri(18)).foregroundStyle(c.text) }.frame(maxWidth: .infinity).padding(.vertical, 10)
                }.background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.22))).padding(.top, 14)
            }.frame(maxWidth: .infinity)
        }
    }
}

/// The qibla compass, on the prayer page: the same finder as the qibla page.
struct QiblaCard: View {
    var body: some View { Panel(pad: 16) { QiblaFinder() } }
}
func icon(_ m: String) -> String { m == "adhan" ? "volume" : m == "notify" ? "bell" : "mute" }

/// Location + adhan settings (like adhan apps).
struct PrayerSettings: View {
    @EnvironmentObject var prayers: Prayers
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var cc = Store.shared.str("cc").uppercased()
    @State private var countryOpen = false
    @State private var countryQ = ""
    @State private var cityOpen = false
    @State private var cityQ = ""
    @State private var hits: [Prayers.CityHit] = []
    @State private var searching = false
    @State private var picked: Prayers.CityHit?
    @State private var busy = false
    @State private var modes: [String: String] = [:]
    @State private var pre = 0
    @State private var iqOn = true
    @State private var iq: [String: Int] = [:]
    @State private var on = true
    @State private var notifDenied = false
    @State private var voice = Adhan.voiceId
    @State private var iqVoice = Adhan.iqVoiceId
    @State private var testAdhan = false
    @State private var testMsg = ""
    @State private var locOk: Bool?
    @ObservedObject private var adhanP = AdhanPlayer.shared
    @ObservedObject private var files = AdhanFiles.shared
    @State private var ringSilent = false
    private var sub: Color { c.faint.mix(c.muted, 0.5) }
    var body: some View {
        ScrollViewReader { px in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                head
                alertsSection
                generalSection
                remindSection
                preSection
                iqamaSection
                adhanSection
                placeSection
            }.padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 28)
        }
        // (screenshots) the other times and the reminders
        .onAppear { if RootView.shot == "prayerRemind" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { px.scrollTo("others", anchor: .top) } } }
        }
        .font(F.plex(15)).background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir)
        .fullScreenCover(isPresented: $testAdhan) { AdhanScreen(key: "test") }
        .onDisappear { if adhanP.playing { adhanP.stop() }; ReminderVoice.shared.stop() }
        .onAppear {
            pre = prayers.preMinutes; on = prayers.alertsOn; iqOn = prayers.iqOn; ringSilent = prayers.ringSilent; voice = Adhan.voiceId; iqVoice = Adhan.iqVoiceId; Task { await Adhan.prepare(); prayers.schedule() }
            UNUserNotificationCenter.current().getNotificationSettings { s in DispatchQueue.main.async { notifDenied = s.authorizationStatus == .denied } }
        }
    }
}


extension PrayerSettings {
    /// newKey: a new setting, marked «جديد» until it is used (or for the days the dashboard sets)
    private func toggleRow(_ on: Bool, _ t: String, _ subT: String?, newKey: String? = nil, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { on }, set: { v in if let newKey { NewMarks.shared.used(newKey) }; set(v) })) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) { Text(t).font(F.plex(15, .semibold)).foregroundStyle(c.text); if let newKey { NewBadge(k: newKey) } }
                if let subT { Text(subT).font(F.plex(12.5)).foregroundStyle(sub) }
            }
        }.tint(c.gold).padding(.vertical, 10)
    }
    private func radio(_ sel: Bool) -> some View {
        ZStack { Circle().fill(sel ? c.gold : .clear); Circle().strokeBorder(sel ? c.gold : c.faint, lineWidth: 1.5); if sel { SiteIcon(name: "check", size: 14, color: c.onGold) } }.frame(width: 22, height: 22)
    }
    @ViewBuilder var head: some View {
        Text(tr("مواقيت الصلاة والأذان")).font(F.amiri(28)).foregroundStyle(c.text)
        HStack(spacing: 5) {
            SiteIcon(name: "pin", size: 15, color: c.gold)
            Text(prayers.place.isEmpty ? tr("لم تُحدَّد مدينتك بعد") : prayers.place).font(F.plex(13)).foregroundStyle(c.muted).lineLimit(1)
            Spacer()
            Text(Prayers.hijri()).font(F.plex(12)).foregroundStyle(sub)
        }.padding(.horizontal, 4).padding(.top, 4)
        if notifDenied {
            HStack { Text(tr("الإشعارات متوقفة — لن يصلك تنبيه الأذان")).font(F.plex(13)); Spacer(); Button(tr("اسمح")) { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }.font(F.plex(13, .bold)) }
                .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(c.danger.opacity(0.12))).padding(.top, 10)
        }
    }
    @ViewBuilder var alertsSection: some View {
        let day = prayers.forDay(), ex = prayers.extras()
        GroupHead(title: tr("الصلوات الخمس"), sub: tr("أذان كامل، أو إشعار، أو بدون تنبيه"))
        SettingsGroup {
            let five = day.filter { $0.key != "sunrise" }
            ForEach(Array(five.enumerated()), id: \.element.id) { i, p in
                if i > 0 { Hairline(inset: 38) }
                PrayerAlertRow(p: p)
            }
        }
        GroupHead(title: tr("أوقات أخرى")).id("others")
        SettingsGroup {
            if let sr = day.first(where: { $0.key == "sunrise" }) { PrayerAlertRow(p: sr) }
            ForEach(ex) { p in
                Hairline(inset: 38)
                PrayerAlertRow(p: p, new: true, sub: p.key == "qiyam" ? tr("{0}، الثلث الأخير", Fmt.time(p.time)) : nil)
                // the night prayer's voice, right under its row
                if p.key == "qiyam" && prayers.mode("qiyam") != "off" { VoiceBox(k: "qiyam").padding(.leading, 38).padding(.bottom, 14) }
            }
        }
    }
    @ViewBuilder var remindSection: some View {
        let h = Friday.sunnahHours
        GroupHead(title: tr("التذكيرات"))
        SettingsGroup {
            toggleRow(prayers.kahfOn, tr("سورة الكهف"), tr("ليلة الجمعة بعد المغرب، وصباح الجمعة"), newKey: "kahf") { v in prayers.setKahf(v); if v { Task { _ = await prayers.requestNotifications() } } }
            Hairline()
            toggleRow(prayers.fridayOn, tr("سنن يوم الجمعة"), tr("قبل صلاة الجمعة بـ {0} ساعة", h.truncatingRemainder(dividingBy: 1) == 0 ? Int(h).ar : L.digits("\(h)")), newKey: "friday") { v in prayers.setFriday(v); if v { Task { _ = await prayers.requestNotifications() } } }
            Hairline()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) { Text(tr("صلِّ على محمد ﷺ")).font(F.plex(15, .semibold)).foregroundStyle(c.text); NewBadge(k: "salawat") }
                Text(tr("كم مرة يصلك التذكير")).font(F.plex(12.5)).foregroundStyle(sub)
                SegBar(items: [(0, tr("بدون")), (30, tr("نص ساعة")), (60, tr("ساعة")), (120, tr("ساعتين")), (1440, tr("يوميًا"))], selected: prayers.salawatEvery) { m in
                    NewMarks.shared.used("salawat"); prayers.setSalawat(m); if m > 0 { Task { notifDenied = !(await prayers.requestNotifications()) } }
                }
                VoiceBox(k: "salawat")
            }.padding(.vertical, 12)
        }
    }
    @ViewBuilder var generalSection: some View {
        GroupHead(title: tr("عام"))
        SettingsGroup {
            toggleRow(on, tr("تنبيهات الصلاة"), tr("أذان أو إشعار عند دخول كل وقت")) { v in on = v; prayers.setAlerts(v); if v { Task { notifDenied = !(await prayers.requestNotifications()) } } }
            if prayers.ringSilentAvailable {
                Hairline()
                toggleRow(ringSilent, tr("يرنّ حتى في الصامت"), tr("الأذان منبّه بالصوت الذي اخترته"), newKey: "ringSilent") { v in
                    ringSilent = v
                    Task { let ok = await prayers.setRingSilent(v); if v && !ok { ringSilent = false; ui.say(tr("اسمح للتطبيق بالمنبّهات من الإعدادات أولًا")) } }
                }
            }
        }
    }
    @ViewBuilder var preSection: some View {
        GroupHead(title: tr("تنبيه قبل الصلاة"))
        HStack(spacing: 2) {
            ForEach([0, 5, 10, 15, 30], id: \.self) { m in
                let sel = pre == m
                Button { pre = m; prayers.setPre(m) } label: {
                    Text(m == 0 ? tr("بدون") : tr("{0} د", m.ar)).font(F.plex(13.5, sel ? .bold : .medium)).foregroundStyle(sel ? c.text : c.muted)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(RoundedRectangle(cornerRadius: 10).fill(sel ? c.surface3.mix(c.gold, 0.08) : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(sel ? c.gold.opacity(0.28) : .clear))
                }.buttonStyle(.plain)
            }
        }.padding(3).background(RoundedRectangle(cornerRadius: 13).fill(Color.black.opacity(0.28))).overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(c.text.opacity(0.06)))
    }
    @ViewBuilder var iqamaSection: some View {
        GroupHead(title: tr("الإقامة"), sub: tr("بعد الأذان بالمدة التي تختارها لكل صلاة، عدا الجمعة"))
        SettingsGroup { toggleRow(iqOn, tr("تنبيه وقت الإقامة"), nil) { v in iqOn = v; prayers.setIqOn(v) } }
        if iqOn && on {
            SettingsGroup {
                ForEach(Array(Prayers.iqKeys.enumerated()), id: \.element) { i, k in
                    if i > 0 { Hairline(inset: 38) }
                    iqRow(k)
                }
            }.padding(.top, 8)
            GroupHead(title: tr("صوت الإقامة"))
            SettingsGroup {
                let list = [Adhan.Voice(id: "", name: tr("الصوت العادي"), muezzin: tr("صوت التنبيه المعتاد"), url: "", fajr: "")] + Adhan.iqVoices
                ForEach(Array(list.enumerated()), id: \.element.id) { i, v in
                    if i > 0 { Hairline(inset: 48) }
                    iqVoiceRow(v)
                }
            }
            GhostButton(title: tr("تجربة إشعار الإقامة"), icon: "bell") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { let ok = await prayers.testIqama(); ui.say(ok ? tr("أُرسل إشعار الإقامة الآن") : tr("اسمح للتطبيق بالإشعارات من الإعدادات أولًا")) }
            }.padding(.top, 10)
        }
    }
    private func iqRow(_ k: String) -> some View {
        let v = iq[k] ?? prayers.iqMin(k)
        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8).fill(PrayerSky.swatch(k)).frame(width: 24, height: 24)
            Text(tr(Prayers.names.first { $0.0 == k }?.1 ?? "")).font(F.plex(15, .semibold)).foregroundStyle(c.text)
            Spacer()
            HStack(spacing: 0) {
                Button { let n = min(60, v + 5); iq[k] = n; prayers.setIqMin(k, n) } label: { Text("+").font(.system(size: 18, weight: .medium)).foregroundStyle(c.text).frame(width: 36, height: 32) }.buttonStyle(.plain).disabled(v >= 60)
                Text(tr("بعد {0} د", v.ar)).font(F.plex(13, .semibold)).foregroundStyle(c.text).frame(width: 70)
                Button { let n = max(5, v - 5); iq[k] = n; prayers.setIqMin(k, n) } label: { Text("−").font(.system(size: 18, weight: .medium)).foregroundStyle(c.text).frame(width: 36, height: 32) }.buttonStyle(.plain).disabled(v <= 5)
            }.padding(2).background(RoundedRectangle(cornerRadius: 11).fill(Color.black.opacity(0.28)))
        }.frame(minHeight: 56)
    }
    private func iqVoiceRow(_ v: Adhan.Voice) -> some View {
        let playingIt = !v.id.isEmpty && adhanP.playing && adhanP.what == "iq:" + v.id
        let sel = iqVoice == v.id
        return HStack(spacing: 12) {
            if v.id.isEmpty { SiteIcon(name: "bell", size: 16, color: c.text).frame(width: 36, height: 36).background(Circle().fill(c.surface3)) }
            else {
                Button { if playingIt { adhanP.stop() } else { adhanP.playIqama(v) } } label: {
                    Ico(name: playingIt ? "pause.fill" : "play.fill", size: 14).foregroundStyle(playingIt ? c.onGold : c.text).frame(width: 36, height: 36).background(Circle().fill(playingIt ? c.gold : c.surface3))
                }.buttonStyle(.plain).accessibilityLabel(playingIt ? tr("إيقاف") : tr("استماع"))
            }
            Button { iqVoice = v.id; Adhan.setIqVoice(v.id); ui.say(v.id.isEmpty ? tr("ستصلك الإقامة بصوت التنبيه العادي") : tr("حُفظ صوت الإقامة")) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) { Text(v.name).font(F.plex(15, .semibold)).foregroundStyle(sel ? c.gold2 : c.text); if !v.muezzin.isEmpty { Text(v.muezzin).font(F.plex(12.5)).foregroundStyle(sub) } }
                    Spacer(); radio(sel)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.frame(minHeight: 62)
    }
    @ViewBuilder var adhanSection: some View {
        GroupHead(title: tr("صوت الأذان"))
        SettingsGroup {
            ForEach(Array(Adhan.voices.enumerated()), id: \.element.id) { i, v in
                if i > 0 { Hairline() }
                adhanRow(v)
            }
        }
        HStack(spacing: 10) {
            GhostButton(title: adhanP.playing ? tr("إيقاف") : tr("استماع للأذان"), icon: adhanP.playing ? "stop.fill" : "play.fill") {
                if adhanP.playing { adhanP.stop() } else { adhanP.play(fajr: false) }
            }.frame(maxWidth: .infinity)
            GhostButton(title: tr("تجربة الإشعار"), icon: "bell") {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { testMsg = tr("جارٍ التجهيز…") }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { let ok = await prayers.testNotification(); testMsg = ok ? tr("أُرسل إشعار الأذان الآن — إن لم يظهر فراجع إذن الإشعارات وعدم الإزعاج") : tr("اسمح للتطبيق بالإشعارات من الإعدادات أولًا") }
            }.frame(maxWidth: .infinity)
        }.padding(.top, 10)
        if !testMsg.isEmpty {
            HStack(spacing: 8) {
                Ico(name: "bell", size: 14).foregroundStyle(c.onGold).frame(width: 24, height: 24).background(Circle().fill(c.gold))
                Text(testMsg).font(F.plex(12.5, .semibold)).foregroundStyle(c.text)
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14).fill(c.gold.opacity(0.12))).overlay(RoundedRectangle(cornerRadius: 14).stroke(c.gold.opacity(0.45))).padding(.top, 10)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        Text(tr("في الإشعار يُسمع أول ٣٠ ثانية من الأذان (أقصى ما يسمح به الآيفون)، والمس الإشعار لسماعه كاملًا.")).font(F.plex(12)).foregroundStyle(sub).padding(.horizontal, 6).padding(.top, 10)
    }
    private func adhanRow(_ v: Adhan.Voice) -> some View {
        let sel = voice == v.id
        return Button { voice = v.id; Adhan.setVoice(v.id) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) { Text(v.name).font(F.plex(15, .semibold)).foregroundStyle(sel ? c.gold2 : c.text); Text(v.muezzin).font(F.plex(12.5)).foregroundStyle(sub) }
                Spacer()
                let _ = files.changed
                if let p = files.progress(v) {
                    HStack(spacing: 6) { ProgressView(value: p).frame(width: 46).tint(c.gold); Text("\(Int(p * 100).ar)٪").font(F.plex(11.5)).foregroundStyle(c.muted) }
                } else if Adhan.saved(v) {
                    Label(tr("على الجهاز"), systemImage: "checkmark.icloud").font(F.plex(11.5)).foregroundStyle(sub).labelStyle(.titleAndIcon)
                } else {
                    Button { Adhan.download(v) } label: { Label(tr("تحميل"), systemImage: "arrow.down.circle").font(F.plex(12, .semibold)).foregroundStyle(c.gold) }.buttonStyle(.plain)
                }
                radio(sel)
            }.frame(minHeight: 62).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    /// every country, in the app's language, in its alphabetical order
    private var countries: [(String, String)] {
        Locale.isoRegionCodes.compactMap { code in L.locale.localizedString(forRegionCode: code).map { (code, $0) } }
            .sorted { $0.1.compare($1.1, locale: L.locale) == .orderedAscending }
    }
    @ViewBuilder var placeSection: some View {
        GroupHead(title: tr("الموقع"))
        // where the times are computed for: the district and city, then the street and the coordinates (as other apps show it)
        let by = Store.shared.str("placeBy")
        SettingsGroup {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("موقعك الحالي")).font(F.plex(12, .semibold)).foregroundStyle(c.gold)
                    Text(prayers.place.isEmpty ? tr("لم يُحدَّد بعد") : prayers.place).font(F.plex(17, .bold)).foregroundStyle(c.text)
                    let street = Store.shared.str("placeStreet")
                    if by == "gps" && !street.isEmpty { Text(street).font(F.plex(14)).foregroundStyle(c.muted) }
                    if let la = Store.shared.double("lat"), let lo = Store.shared.double("lon") {
                        Text(tr("خط الطول: {0}   خط العرض: {1}", String(format: "%.4f", lo), String(format: "%.4f", la))).font(F.plex(12)).foregroundStyle(sub)
                    }
                    let how = by == "gps" ? tr("محدَّد من موقع جوالك") : by == "manual" ? tr("مختار يدويًا") : by == "ip" ? tr("تقريبي من الإنترنت") : ""
                    if !how.isEmpty { Text(how).font(F.plex(11.5)).foregroundStyle(sub) }
                }
                Spacer(minLength: 0)
                if by == "gps" { Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(c.gold) }
            }.padding(.vertical, 14)
            Hairline()
            Button {
                busy = true; locOk = nil; picked = nil
                Task { let ok = await prayers.locate(); busy = false; withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { locOk = ok }; if ok { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
            } label: {
                HStack(spacing: 10) { SiteIcon(name: "locate", size: 18, color: c.gold2); Text(busy ? tr("جارٍ التحديد…") : tr("حدّد موقعي تلقائيًا")).font(F.plex(15, .semibold)).foregroundStyle(c.gold2); Spacer() }.frame(minHeight: 52).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        if let ok = locOk {
            HStack(spacing: 8) {
                Ico(name: ok ? "check" : "xmark", size: 14).foregroundStyle(ok ? c.onGold : .white).frame(width: 24, height: 24).background(Circle().fill(ok ? c.gold : Color.red.opacity(0.75)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(ok ? tr("تم تحديث الموقع") : tr("تعذّر تحديد الموقع — اكتب مدينتك")).font(F.plex(13, .bold)).foregroundStyle(c.text)
                    if ok { Text(prayers.place).font(F.plex(12)).foregroundStyle(c.gold).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14).fill(c.gold.opacity(ok ? 0.12 : 0.05))).overlay(RoundedRectangle(cornerRadius: 14).stroke(c.gold.opacity(ok ? 0.45 : 0.15))).padding(.top, 10)
        }
        // by hand: the country from the list, then the city from the search results (nothing typed is taken as it is)
        GroupHead(title: tr("اختيار يدوي"))
        let all = countries
        let ccName = all.first { $0.0 == cc }?.1 ?? ""
        SettingsGroup {
            Button { withAnimation { countryOpen.toggle(); cityOpen = false } } label: {
                HStack(spacing: 12) {
                    Text(tr("الدولة")).font(F.plex(14)).foregroundStyle(c.muted).frame(width: 64, alignment: .leading)
                    Text(ccName.isEmpty ? tr("اختر الدولة") : ccName).font(F.plex(15, .semibold)).foregroundStyle(ccName.isEmpty ? sub : c.text)
                    Spacer(); Image(systemName: countryOpen ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(sub)
                }.frame(minHeight: 52).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if countryOpen {
                TextField(tr("ابحث عن دولة"), text: $countryQ).font(F.plex(15)).padding(.horizontal, 12).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 12).fill(c.surface3)).padding(.bottom, 6)
                let q = countryQ.trimmingCharacters(in: .whitespaces)
                ForEach(all.filter { q.isEmpty || $0.1.localizedCaseInsensitiveContains(q) }.prefix(40), id: \.0) { code, name in
                    Button { cc = code; countryOpen = false; countryQ = ""; picked = nil; hits = []; cityQ = ""; withAnimation { cityOpen = true } } label: {
                        HStack { Text(name).font(F.plex(15, code == cc ? .bold : .regular)).foregroundStyle(code == cc ? c.gold : c.text); Spacer(); if code == cc { Image(systemName: "checkmark").foregroundStyle(c.gold) } }
                            .frame(minHeight: 42).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            Hairline()
            Button { withAnimation { cityOpen.toggle(); countryOpen = false } } label: {
                HStack(spacing: 12) {
                    Text(tr("المدينة")).font(F.plex(14)).foregroundStyle(c.muted).frame(width: 64, alignment: .leading)
                    Text(picked?.name ?? tr("اختر المدينة")).font(F.plex(15, .semibold)).foregroundStyle(picked == nil ? sub : c.gold)
                    Spacer(); Image(systemName: cityOpen ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(sub)
                }.frame(minHeight: 52).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if cityOpen {
                TextField(tr("اكتب اسم مدينتك ثم اخترها من النتائج"), text: $cityQ).font(F.plex(15)).padding(.horizontal, 12).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 12).fill(c.surface3)).padding(.bottom, 6)
                    .task(id: cityQ + "|" + cc) {
                        hits = []; let q = cityQ.trimmingCharacters(in: .whitespaces)
                        guard q.count >= 2 else { searching = false; return }
                        searching = true
                        try? await Task.sleep(nanoseconds: 450_000_000); if Task.isCancelled { return }
                        let r = await prayers.searchCities(q, cc: cc, countryName: ccName)
                        if !Task.isCancelled { hits = r; searching = false }
                    }
                if searching { Text(tr("جارٍ البحث…")).font(F.plex(13)).foregroundStyle(sub).padding(.vertical, 8) }
                else if cityQ.trimmingCharacters(in: .whitespaces).count >= 2 && hits.isEmpty { Text(tr("لا نتائج — جرّب اسمًا آخر")).font(F.plex(13)).foregroundStyle(sub).padding(.vertical, 8) }
                ForEach(hits, id: \.self) { h in
                    Button { picked = h; withAnimation { cityOpen = false } } label: {
                        HStack(spacing: 10) {
                            SiteIcon(name: "pin", size: 16, color: c.gold)
                            VStack(alignment: .leading, spacing: 1) { Text(h.name).font(F.plex(15, .semibold)).foregroundStyle(c.text); if !h.sub.isEmpty { Text(h.sub).font(F.plex(12)).foregroundStyle(c.muted) } }
                            Spacer(); if picked == h { Image(systemName: "checkmark").foregroundStyle(c.gold) }
                        }.frame(minHeight: 48).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        // one save for the whole page: the city picked by hand (the other settings are kept as they are changed)
        GoldButton(title: tr("حفظ"), icon: "checkmark") {
            if let h = picked { prayers.setPicked(h) }
            ui.say(tr("تم الحفظ")); dismiss()
        }.frame(maxWidth: .infinity).padding(.top, 18)
    }
}

/// The qibla page.
struct QiblaView: View {
    var body: some View { ScrollView { QiblaFinder(pushed: true).padding(18) }.background(Backdrop()) }
}

/// The compass for the qibla: its own heading source (only this screen redraws as the phone turns).
@MainActor
final class Compass: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var heading: Double?
    @Published private(set) var needsCalibration = false
    private let lm = CLLocationManager()
    override init() { super.init(); lm.delegate = self; lm.headingFilter = 1 }
    func start() { lm.startUpdatingHeading() }
    func stop() { lm.stopUpdatingHeading() }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        let raw = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading, acc = h.headingAccuracy
        Task { @MainActor in
            self.needsCalibration = acc < 0 || acc > 20
            // smoothed like the site (a quarter of the way each time), across 0°/360°
            if let old = self.heading { var d = raw - old; if d > 180 { d -= 360 }; if d < -180 { d += 360 }; self.heading = (old + d * 0.25 + 360).truncatingRemainder(dividingBy: 360) }
            else { self.heading = raw }
        }
    }
    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}

/// Qibla finder, as on the site: the dial turns with the phone, the Kaaba sits on the rim at the qibla bearing, a big
/// instruction says which way to turn, and when the phone lines up the ring and the pointer turn green, a green glow
/// breathes behind the dial and the phone taps twice.
struct QiblaFinder: View {
    /// its own page (pushed): always on while shown; inside a tab: only while that tab is the one on screen
    var pushed = false
    @Environment(\.tabActive) private var tabOn
    /// on the prayer page: only while the compass itself is on screen (scrolled to) and no sheet covers it —
    /// it ran from the top of the page and under the settings sheet, turning and vibrating as the phone moved
    @State private var seen = true   // until measured (if the measure never comes, it works as before)
    @State private var covered = false
    private var active: Bool { pushed || (tabOn && seen && !covered) }
    @EnvironmentObject var prayers: Prayers
    @StateObject private var compass = Compass()
    @Environment(\.pal) private var c
    @State private var locked = false
    @State private var glow = false
    private let ok = Color(red: 63 / 255, green: 191 / 255, blue: 127 / 255)

    private var km: Int {
        let (lat, lon) = prayers.coords
        let r = { (d: Double) in d * .pi / 180 }, kLat = r(21.422487), kLon = r(39.826206), la = r(lat)
        let h = pow(sin((kLat - la) / 2), 2) + cos(la) * cos(kLat) * pow(sin((kLon - r(lon)) / 2), 2)
        return Int((2 * 6371 * asin(sqrt(h))).rounded())
    }

    /// a good part of it is in view
    private func measure(_ f: CGRect) {
        guard !pushed, f.height > 0 else { return }
        let h = UIScreen.main.bounds.height
        let v = f.minY < h - 100 && f.maxY > 100
        if v != seen { seen = v }
    }
    var body: some View {
        let b = prayers.qibla()
        let hd = compass.heading
        let diff = hd.map { ((b - $0 + 540).truncatingRemainder(dividingBy: 360)) - 180 }
        let on = diff.map { abs($0) <= 3 } ?? false
            VStack(spacing: 14) {
                // place · distance, and the bearing
                HStack(spacing: 10) {
                    Text(tr("{0} · {1} كم إلى مكة المكرمة", prayers.place.isEmpty ? tr("موقعك") : prayers.place, km.ar)).font(F.plex(13)).foregroundStyle(c.muted)
                    Spacer()
                    Text("\(Int(b.rounded()).ar)°").font(F.plex(15, .bold)).foregroundStyle(c.gold).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 10).fill(c.gold.opacity(0.14)))
                }
                // what to do now
                HStack(spacing: 12) {
                    Group {
                        if on { Ico(name: "checkmark", size: 24, color: ok) }
                        else if let d = diff { Text(d > 0 ? "↻" : "↺").font(.system(size: 26)).foregroundStyle(c.gold).rotationEffect(.degrees(glow ? (d > 0 ? 25 : -25) : 0)).scaleEffect(glow ? 1.1 : 1) }
                        else { Ico(name: "safari", size: 24, color: c.gold) }
                    }.frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(diff, on)).font(F.plex(17, .bold)).foregroundStyle(on ? ok : c.text)
                        Text(on ? tr("ثبّت الجوال على هذا الاتجاه") : diff.map { tr("باقي {0}°", Int(abs($0).rounded()).ar) } ?? tr("القبلة على {0}° من الشمال", Int(b.rounded()).ar))
                            .font(F.plex(12.5)).foregroundStyle(c.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16).fill(on ? ok.opacity(0.16) : c.surface2))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? ok.opacity(0.6) : c.line))
                .animation(.easeOut(duration: 0.25), value: on)
                dial(b, hd ?? 0, on).padding(.vertical, 8)
                if compass.needsCalibration {
                    Text(tr("البوصلة تحتاج معايرة: حرّك الجوال في الهواء على شكل الرقم ٨، وابعده عن المعادن والمغناطيس.")).font(F.plex(13)).foregroundStyle(c.muted).multilineTextAlignment(.center)
                } else {
                    Text(tr("ضع الجوال بشكل مسطّح على كفّك لدقّة أعلى.")).font(F.plex(13)).foregroundStyle(c.faint).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 520).frame(maxWidth: .infinity)
        // the compass runs only while the qibla is on screen (a hidden tab kept it running, and it vibrated elsewhere)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { measure(g.frame(in: .global)) }
                .onChange(of: g.frame(in: .global).minY) { _ in measure(g.frame(in: .global)) }
        })
        .onReceive(UIState.shared!.$sheet) { s in covered = s != nil }
        .onAppear { if active { compass.start() }; withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { glow = true } }
        .onDisappear { compass.stop() }
        .onChange(of: active) { a in if a { compass.start() } else { compass.stop(); locked = false } }
        .onChange(of: on) { v in
            if v && !locked && active && UIApplication.shared.applicationState == .active {
                locked = true
                // two taps when the phone lines up (the site's vibrate 60·40·60)
                let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
            }
        }
        .onChange(of: diff.map { abs($0) > 8 } ?? true) { far in if far { locked = false } }
    }

    private func title(_ diff: Double?, _ on: Bool) -> String {
        guard let d = diff else { return tr("أمسك الجوال مسطّحًا") }
        if on { return tr("أنت الآن باتجاه القبلة") }
        return d > 0 ? (d < 20 ? tr("أدِر الجوال يمينًا قليلًا") : tr("أدِر الجوال إلى اليمين")) : (d > -20 ? tr("أدِر الجوال يسارًا قليلًا") : tr("أدِر الجوال إلى اليسار"))
    }

    /// The dial (the site's SVG, viewBox −14…214): it turns by −heading; the pointer at the top stays still.
    private func dial(_ b: Double, _ hd: Double, _ on: Bool) -> some View {
        let side: CGFloat = min(300, UIScreen.main.bounds.width * 0.78)
        let u = side / 228            // one SVG unit
        return ZStack {
            if on {
                Circle().fill(RadialGradient(colors: [ok.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: side * 0.55))
                    .frame(width: side * 1.1, height: side * 1.1).opacity(glow ? 1 : 0.45)
            }
            Canvas { ctx, size in
                let o = CGPoint(x: 114 * u, y: 114 * u)           // the SVG's (100, 100)
                func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: (x + 14) * u, y: (y + 14) * u) }
                ctx.fill(Path(ellipseIn: CGRect(x: o.x - 96 * u, y: o.y - 96 * u, width: 192 * u, height: 192 * u)), with: .color(c.surface))
                ctx.stroke(Path(ellipseIn: CGRect(x: o.x - 96 * u, y: o.y - 96 * u, width: 192 * u, height: 192 * u)),
                           with: .color(on ? ok : c.gold.opacity(0.55)), lineWidth: (on ? 3.2 : 1.6) * u)
                var r = ctx
                r.translateBy(x: o.x, y: o.y); r.rotate(by: .degrees(-hd)); r.translateBy(x: -o.x, y: -o.y)
                for i in 0..<72 {
                    let major = i % 6 == 0
                    var t = r; t.translateBy(x: o.x, y: o.y); t.rotate(by: .degrees(Double(i * 5))); t.translateBy(x: -o.x, y: -o.y)
                    var l = Path(); l.move(to: pt(100, major ? 9 : 10)); l.addLine(to: pt(100, major ? 21 : 15))
                    t.stroke(l, with: .color(i == 0 ? Color(red: 224 / 255, green: 90 / 255, blue: 79 / 255) : major ? c.muted : c.faint), lineWidth: (i == 0 ? 2.6 : major ? 2 : 1) * u)
                }
                // the star in the middle
                var star = Path(); let sp: [(Double, Double)] = [(100, 58), (108, 92), (142, 100), (108, 108), (100, 142), (92, 108), (58, 100), (92, 92)]
                star.move(to: pt(sp[0].0, sp[0].1)); for q in sp.dropFirst() { star.addLine(to: pt(q.0, q.1)) }; star.closeSubpath()
                r.fill(star, with: .color(c.gold.opacity(0.08))); r.stroke(star, with: .color(c.gold.opacity(0.3)), lineWidth: u)
                // the line to the Kaaba, at the qibla bearing
                var k = r; k.translateBy(x: o.x, y: o.y); k.rotate(by: .degrees(b)); k.translateBy(x: -o.x, y: -o.y)
                var ln = Path(); ln.move(to: pt(100, 100)); ln.addLine(to: pt(100, 46))
                k.stroke(ln, with: .color(on ? ok : c.gold), style: StrokeStyle(lineWidth: 2.4 * u, lineCap: .round))
                k.fill(Path(ellipseIn: CGRect(x: pt(100, 27).x - 15 * u, y: pt(100, 27).y - 15 * u, width: 30 * u, height: 30 * u)), with: .color(c.gold.opacity(0.16)))
                // the Kaaba (the site's little cube)
                let kc = pt(100, 27)
                func kp(_ p: [(Double, Double)]) -> Path { var q = Path(); q.move(to: CGPoint(x: kc.x + p[0].0 * u, y: kc.y + p[0].1 * u)); for v in p.dropFirst() { q.addLine(to: CGPoint(x: kc.x + v.0 * u, y: kc.y + v.1 * u)) }; q.closeSubpath(); return q }
                k.fill(kp([(-10, -6), (0, -10), (10, -6), (0, -2)]), with: .color(Color(white: 0.23)))
                k.fill(kp([(-10, -6), (0, -2), (0, 10), (-10, 6)]), with: .color(Color(white: 0.08)))
                k.fill(kp([(10, -6), (0, -2), (0, 10), (10, 6)]), with: .color(Color(white: 0.04)))
                k.fill(kp([(-10, -1), (0, 3), (0, 5), (-10, 1)]), with: .color(c.gold))
                k.fill(kp([(10, -1), (0, 3), (0, 5), (10, 1)]), with: .color(c.gold))
                // the fixed pointer at the top and the hub
                var ptr = Path(); ptr.move(to: pt(100, -7)); ptr.addLine(to: pt(108, 1)); ptr.addLine(to: pt(100, 8)); ptr.addLine(to: pt(92, 1)); ptr.closeSubpath()
                ctx.fill(ptr, with: .color(on ? ok : c.gold))
                ctx.fill(Path(ellipseIn: CGRect(x: o.x - 5 * u, y: o.y - 5 * u, width: 10 * u, height: 10 * u)), with: .color(on ? ok : c.gold))
            }
            .frame(width: side, height: side)
            // the four letters, kept upright while the dial turns
            ForEach(Array(["ش", "ق", "ج", "غ"].enumerated()), id: \.offset) { i, l in
                Text(tr(l)).font(F.plex(12, .bold)).foregroundStyle(i == 0 ? Color(red: 224 / 255, green: 90 / 255, blue: 79 / 255) : c.muted)
                    .rotationEffect(.degrees(-(Double(i) * 90 - hd))).offset(y: -side * 68 / 228).rotationEffect(.degrees(Double(i) * 90 - hd))
            }
        }
        .frame(width: side, height: side)
        .animation(.linear(duration: 0.08), value: hd)
    }
}

/// a thin dashed rule (the line between a dhikr and its source)
struct DashLine: View {
    @Environment(\.pal) private var c
    var body: some View {
        GeometryReader { g in Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: g.size.width, y: 0)) }.stroke(c.gold.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6, 5])) }.frame(height: 1)
    }
}
