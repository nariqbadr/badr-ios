import SwiftUI
import UserNotifications

/// Adhkar like the site: one dhikr at a time with a big counter (or the full list); the counts reset every day.
struct AdhkarView: View {
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var tab = { let h = Calendar.current.component(.hour, from: Date()); return (3...12).contains(h) ? "morning" : (13...20).contains(h) ? "evening" : "sleep" }()
    @AppStorage("adhkarList") private var listMode = false
    @State private var counts: [Int] = []
    @State private var page = 0
    private static let data: [String: [(text: String, count: Int)]] = {
        guard let u = Bundle.main.url(forResource: "adhkar", withExtension: "json"), let d = try? Data(contentsOf: u) else { return [:] }
        return J(data: d).dict.mapValues { $0.array.map { (text: $0["text"].str, count: max(1, $0["count"].int)) } }
    }()
    private static func text(_ t: String) -> String {
        let r = try! NSRegularExpression(pattern: "\\s*\\((\\d+)\\)"); var s = t.trimmingCharacters(in: .whitespaces)
        for m in r.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() { if let g = Range(m.range, in: s), let n = Range(m.range(at: 1), in: s) { s.replaceSubrange(g, with: " ﴿\(Int(s[n])?.ar ?? "")﴾") } }
        return s
    }
    private func key(_ i: Int) -> String { "dk-\(Wird.today)-\(tab)-\(i)" }
    var body: some View {
        let cats = [("morning", tr("الصباح")), ("evening", tr("المساء")), ("sleep", tr("النوم"))].filter { !(AdhkarView.data[$0.0] ?? []).isEmpty }
        let list = AdhkarView.data[tab] ?? []
        let done = list.indices.filter { (counts[safe: $0] ?? 0) >= list[$0].count }.count
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Seg(items: cats.map { tr("أذكار {0}", $0.1) }, selected: cats.firstIndex { $0.0 == tab } ?? 0) { tab = cats[$0].0 }
                Chip(text: nil, icon: listMode ? "rectangle.portrait" : "list.bullet", on: listMode) { listMode.toggle() }
            }.padding(.horizontal, 16).padding(.vertical, 8)
            HStack(spacing: 10) {
                ProgressView(value: list.isEmpty ? 0 : Double(done) / Double(list.count)).tint(c.gold).animation(.easeOut(duration: 0.5), value: done)
                Text(listMode ? tr("أنجزت {0} من {1}", done.ar, list.count.ar) : tr("{0} من {1} — أنجزت {2}", (page + 1).ar, list.count.ar, done.ar)).font(F.plex(12.5, .medium)).foregroundStyle(c.muted)
            }.padding(.horizontal, 18).padding(.vertical, 2)
            if list.isEmpty { Empty(text: tr("لا توجد أذكار")); Spacer() }
            else if listMode {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(list.enumerated()), id: \.offset) { i, dk in
                            let n = counts[safe: i] ?? 0, fin = n >= dk.count
                            Panel(pad: 18, lattice: false) {
                                Text(AdhkarView.text(dk.text)).font(F.amiri(20, bold: false)).foregroundStyle(fin ? c.muted : c.text).lineSpacing(14)
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
                            Panel(pad: 22) {
                                ScrollView { Text(AdhkarView.text(dk.text)).font(F.amiri(22, bold: false)).foregroundStyle(c.text).lineSpacing(16).multilineTextAlignment(.center).frame(maxWidth: .infinity) }
                            }.frame(maxHeight: .infinity)
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
                        }.padding(.horizontal, 18).padding(.vertical, 10).tag(i)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .onAppear { load(list) }
        .onChange(of: tab) { _ in let l = AdhkarView.data[tab] ?? []; load(l) }
    }
    private func load(_ list: [(text: String, count: Int)]) {
        counts = list.indices.map { UserDefaults.standard.integer(forKey: key($0)) }
        page = list.indices.first { counts[$0] < list[$0].count } ?? 0
    }
    private func count(_ i: Int, _ list: [(text: String, count: Int)]) {
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
    @EnvironmentObject var ui: UIState
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
                        Panel(pad: 22) {
                            VStack(spacing: 0) {
                                Button { ui.sheet = .prayer } label: {
                                    HStack(spacing: 4) { SiteIcon(name: "pin", size: 18, color: c.gold); Text(prayers.place.isEmpty ? tr("حدّد مدينتك") : prayers.place).font(F.plex(14, .semibold)).foregroundStyle(c.text); SiteIcon(name: "chev-d", size: 20, color: c.muted) }.padding(6)
                                }.buttonStyle(.plain)
                                Text(Prayers.hijri()).font(F.plex(12.5)).foregroundStyle(c.muted)
                                ZStack {
                                    Rosette(color: c.gold.opacity(0.14))
                                    Circle().stroke(c.lineSoft, lineWidth: 6).padding(18)
                                    Circle().trim(from: 0, to: frac).stroke(c.goldBrush, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)).padding(18)
                                    VStack(spacing: 0) {
                                        Text(tr("الصلاة القادمة")).font(F.plex(12.5, .medium)).foregroundStyle(c.muted)
                                        Text(n.name).font(F.amiri(34)).foregroundStyle(c.goldBrushV)
                                        Text(String(format: "%02d:%02d:%02d", left / 3600, left % 3600 / 60, left % 60)).font(F.plex(24, .bold)).foregroundStyle(c.text).monospacedDigit().environment(\.layoutDirection, .leftToRight)
                                        Text(Fmt.time(n.time)).font(F.plex(12.5)).foregroundStyle(c.muted)
                                    }
                                }.frame(width: 210, height: 210).padding(.top, 14)
                            }.frame(maxWidth: .infinity)
                        }
                        Panel(pad: 8, lattice: false) {
                            ForEach(list) { p in
                                let on = p.key == n.key && p.time == n.time, past = p.time < now && !on
                                HStack(spacing: 12) {
                                    Ico(name: p.key == "sunrise" ? "sunrise" : ["fajr", "maghrib", "isha"].contains(p.key) ? "moon" : "sun", size: 24, color: on ? c.onGold : past ? c.faint : c.gold)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(p.key == "dhuhr" && Calendar.current.component(.weekday, from: p.time) == 6 ? tr("الجمعة") : p.name).font(F.plex(16, .semibold)).foregroundStyle(on ? c.onGold : past ? c.faint : c.text)
                                        if p.key == "sunrise" { Text(tr("لا يُرفع له أذان")).font(F.plex(11)).foregroundStyle(on ? c.onGold.opacity(0.8) : c.muted) }
                                    }
                                    Spacer()
                                    Text(Fmt.time(p.time)).font(F.plex(16, .semibold)).foregroundStyle(on ? c.onGold : past ? c.faint : c.text)
                                    if prayers.alertsOn {
                                        if p.key == "sunrise" { Color.clear.frame(width: 34, height: 34) }
                                        else {
                                            let m = modes[p.key] ?? prayers.mode(p.key)
                                            Button {
                                                let nx = m == "adhan" ? "notify" : m == "notify" ? "off" : "adhan"
                                                prayers.setMode(p.key, nx); modes[p.key] = nx
                                                ui.say(nx == "adhan" ? tr("سيُرفع الأذان لصلاة {0}", p.name) : nx == "notify" ? tr("إشعار فقط لصلاة {0}", p.name) : tr("بدون تنبيه لصلاة {0}", p.name))
                                            } label: {
                                                SiteIcon(name: m == "adhan" ? "volume" : m == "notify" ? "bell" : "mute", size: 19, color: on ? c.onGold : m == "off" ? c.faint : c.gold)
                                                    .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 11).fill(on ? c.onGold.opacity(0.12) : m == "off" ? .clear : c.gold.opacity(0.13)))
                                            }.buttonStyle(.plain).accessibilityLabel(tr("تنبيه {0}", p.name))
                                        }
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 16).fill(on ? AnyShapeStyle(c.goldBrush) : AnyShapeStyle(Color.clear))).padding(2)
                            }
                        }
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

/// The qibla compass, on the prayer page (like the Android app).
struct QiblaCard: View {
    @EnvironmentObject var prayers: Prayers
    @Environment(\.pal) private var c
    var body: some View {
        let q = prayers.qibla(), rel = q - prayers.heading
        let ok = abs(((rel.truncatingRemainder(dividingBy: 360)) + 540).truncatingRemainder(dividingBy: 360) - 180) < 5
        Panel(pad: 20) {
            VStack(spacing: 10) {
                HStack { SiteIcon(name: "compass", size: 22, color: c.gold); Text(tr("اتجاه القبلة")).font(F.amiri(22)).foregroundStyle(c.text); Spacer(); Text(tr("{0}° من الشمال", Int(q).ar)).font(F.plex(12.5)).foregroundStyle(c.muted) }
                ZStack {
                    Circle().stroke(c.line, lineWidth: 2)
                    ForEach(0..<36) { i in Rectangle().fill(i % 9 == 0 ? c.gold : c.faint).frame(width: 2, height: i % 9 == 0 ? 12 : 6).offset(y: -95).rotationEffect(.degrees(Double(i) * 10 - prayers.heading)) }
                    Text(tr("ش")).font(F.plex(13, .bold)).foregroundStyle(c.danger).offset(y: -76).rotationEffect(.degrees(-prayers.heading))
                    Ico(name: "location.north.fill", size: 64.8).foregroundStyle(c.goldBrush).rotationEffect(.degrees(rel))
                    Text("🕋").font(.system(size: 24)).offset(y: -118).rotationEffect(.degrees(rel))
                }.frame(width: 200, height: 200).padding(24).animation(.easeOut(duration: 0.25), value: prayers.heading)
                Text(ok ? tr("أنت متجه إلى القبلة ✓") : tr("أدر الهاتف حتى يشير السهم للأعلى")).font(F.plex(14, .semibold)).foregroundStyle(c.gold)
            }.frame(maxWidth: .infinity)
        }
        .onAppear { prayers.startHeading() }.onDisappear { prayers.stopHeading() }
    }
}
func icon(_ m: String) -> String { m == "adhan" ? "volume" : m == "notify" ? "bell" : "mute" }

/// Location + adhan settings (like adhan apps).
struct PrayerSettings: View {
    @EnvironmentObject var prayers: Prayers
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var city = ""
    @State private var country = ""
    @State private var busy = false
    @State private var modes: [String: String] = [:]
    @State private var pre = 0
    @State private var on = true
    @State private var notifDenied = false
    @State private var voice = Adhan.voiceId
    @State private var testAdhan = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("مواقيت الصلاة والأذان")).font(F.amiri(24)).foregroundStyle(c.text)
                Label(prayers.place.isEmpty ? tr("لم تُحدَّد مدينتك بعد") : prayers.place, systemImage: "mappin").font(F.plex(14)).foregroundStyle(c.muted)
                if notifDenied {
                    HStack { Text(tr("الإشعارات متوقفة — لن يصلك تنبيه الأذان")).font(F.plex(13)); Spacer(); Button(tr("اسمح")) { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }.font(F.plex(13, .bold)) }
                        .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(c.danger.opacity(0.12)))
                }
                ForEach(prayers.forDay()) { p in
                    let m = modes[p.key] ?? prayers.mode(p.key)
                    HStack {
                        VStack(alignment: .leading) { Text(p.name).font(F.plex(15, .semibold)); Text(Fmt.time(p.time)).font(F.plex(12)).foregroundStyle(c.muted) }
                        Spacer()
                        ForEach(["adhan", "notify", "off"].filter { p.key != "sunrise" || $0 != "adhan" }, id: \.self) { k in
                            Button { prayers.setMode(p.key, k); modes[p.key] = k } label: {
                                VStack(spacing: 2) { Ico(name: icon(k), size: 20); Text(k == "adhan" ? tr("أذان") : k == "notify" ? tr("إشعار") : tr("بدون")).font(F.plex(10)) }
                                    .foregroundStyle(m == k ? c.gold : c.muted).padding(.horizontal, 9).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 12).fill(m == k ? c.gold.opacity(0.18) : .clear))
                            }.buttonStyle(.plain).disabled(!on)
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 16).fill(c.surface.opacity(0.6)))
                }
                Toggle(isOn: Binding(get: { on }, set: { v in on = v; prayers.setAlerts(v); if v { Task { notifDenied = !(await prayers.requestNotifications()) } } })) {
                    VStack(alignment: .leading) { Text(tr("تنبيهات الصلاة")).font(F.plex(15, .semibold)); Text(tr("أذان أو إشعار عند دخول كل وقت حسب اختيارك")).font(F.plex(12)).foregroundStyle(c.muted) }
                }.tint(c.gold)
                Text(tr("تنبيه قبل الصلاة")).font(F.plex(15, .semibold))
                HStack(spacing: 6) { ForEach([0, 5, 10, 15, 30], id: \.self) { m in Pill(title: m == 0 ? tr("بدون") : tr("{0} د", m.ar), on: pre == m) { pre = m; prayers.setPre(m) } } }
                Text(tr("صوت الأذان")).font(F.plex(15, .semibold))
                ForEach(Adhan.voices, id: \.id) { v in
                    Button { voice = v.id; Adhan.setVoice(v.id) } label: {
                        HStack { VStack(alignment: .leading) { Text(v.name).font(F.plex(14.5, .semibold)).foregroundStyle(c.text); Text(v.muezzin).font(F.plex(12)).foregroundStyle(c.muted) }
                            Spacer(); Image(systemName: voice == v.id ? "checkmark.circle.fill" : "circle").foregroundStyle(voice == v.id ? c.gold : c.faint) }
                        .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(c.surface.opacity(0.6))).overlay(RoundedRectangle(cornerRadius: 14).stroke(voice == v.id ? c.gold : c.lineSoft))
                    }.buttonStyle(.plain)
                }
                GhostButton(title: tr("تجربة الأذان"), icon: "play.fill") { testAdhan = true; AdhanPlayer.shared.play(fajr: false) }
                Text(tr("في الإشعار يُسمع أول ٣٠ ثانية من الأذان (أقصى ما يسمح به الآيفون)، والمس الإشعار لسماعه كاملًا.")).font(F.plex(12)).foregroundStyle(c.muted)
                GhostButton(title: busy ? tr("جارٍ التحديد…") : tr("حدّد موقعي تلقائيًا"), icon: "location") {
                    busy = true; Task { let ok = await prayers.locate(); busy = false; ui.say(ok ? tr("تم تحديث المواقيت: {0}", prayers.place) : tr("تعذّر تحديد الموقع — اكتب مدينتك")) }
                }.frame(maxWidth: .infinity)
                Text(tr("أو اكتب مدينتك يدويًا:")).font(F.plex(13)).foregroundStyle(c.muted)
                TextField(tr("المدينة — مثال: القاهرة"), text: $city).padding(12).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                TextField(tr("الدولة — مثال: مصر"), text: $country).padding(12).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                GoldButton(title: tr("حفظ المدينة"), icon: "checkmark") {
                    guard !city.isEmpty else { return }
                    Task { let ok = await prayers.setCity(city, country); ui.say(ok ? tr("تم حفظ المدينة") : tr("لم نجد هذه المدينة")); if ok { dismiss() } }
                }.frame(maxWidth: .infinity)
            }.padding(20)
        }
        .font(F.plex(15)).background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir)
        .fullScreenCover(isPresented: $testAdhan) { AdhanScreen(key: "test") }
        .onAppear {
            pre = prayers.preMinutes; on = prayers.alertsOn; voice = Adhan.voiceId; Task { await Adhan.prepare(); prayers.schedule() }
            UNUserNotificationCenter.current().getNotificationSettings { s in DispatchQueue.main.async { notifDenied = s.authorizationStatus == .denied } }
        }
    }
}

struct QiblaView: View {
    @EnvironmentObject var prayers: Prayers
    @Environment(\.pal) private var c
    var body: some View {
        let q = prayers.qibla()
        let rel = q - prayers.heading
        VStack(spacing: 20) {
            Text(tr("اتجاه القبلة")).font(F.amiri(28)).foregroundStyle(c.text).padding(.top, 20)
            Text(tr("{0}° من الشمال", Int(q).ar)).font(F.plex(14)).foregroundStyle(c.muted)
            ZStack {
                Circle().stroke(c.line, lineWidth: 2)
                ForEach(0..<36) { i in Rectangle().fill(i % 9 == 0 ? c.gold : c.faint).frame(width: 2, height: i % 9 == 0 ? 14 : 7).offset(y: -125).rotationEffect(.degrees(Double(i) * 10 - prayers.heading)) }
                Text("N").font(.system(size: 14, weight: .bold)).foregroundStyle(c.danger).offset(y: -100).rotationEffect(.degrees(-prayers.heading))
                Ico(name: "location.north.fill", size: 84.0).foregroundStyle(c.goldGradient).rotationEffect(.degrees(rel))
                Text("🕋").font(.system(size: 28)).offset(y: -150).rotationEffect(.degrees(rel))
            }.frame(width: 260, height: 260).padding(30).animation(.easeOut(duration: 0.25), value: prayers.heading)
            Text(abs(((rel.truncatingRemainder(dividingBy: 360)) + 540).truncatingRemainder(dividingBy: 360) - 180) < 5 ? tr("أنت متجه إلى القبلة ✓") : tr("أدر الهاتف حتى يشير السهم للأعلى")).font(F.plex(15, .semibold)).foregroundStyle(c.gold)
            Spacer()
        }
        .frame(maxWidth: .infinity).background(Backdrop())
        .navigationTitle(tr("القبلة")).navigationBarTitleDisplayMode(.inline)
        .onAppear { prayers.startHeading() }.onDisappear { prayers.stopHeading() }
    }
}
