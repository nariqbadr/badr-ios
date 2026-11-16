import SwiftUI
import CoreLocation
import UserNotifications

/// Adhkar like the site: one dhikr at a time with a big counter (or the full list); the counts reset every day.
struct AdhkarView: View {
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
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
                    VStack(spacing: 12) {
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
    @State private var city = ""
    @State private var country = ""
    @State private var busy = false
    @State private var modes: [String: String] = [:]
    @State private var pre = 0
    @State private var iqOn = true
    @State private var iq: [String: Int] = [:]
    @State private var on = true
    @State private var notifDenied = false
    @State private var voice = Adhan.voiceId
    @State private var testAdhan = false
    @State private var testMsg = ""
    @State private var locOk: Bool?
    @ObservedObject private var adhanP = AdhanPlayer.shared
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
                // «الإقامة»: minutes after each adhan, per prayer
                Toggle(isOn: Binding(get: { iqOn }, set: { v in iqOn = v; prayers.setIqOn(v) })) {
                    VStack(alignment: .leading) { Text(tr("تنبيه وقت الإقامة")).font(F.plex(15, .semibold)); Text(tr("بعد الأذان بالمدة التي تختارها لكل صلاة (عدا صلاة الجمعة)")).font(F.plex(12)).foregroundStyle(c.muted) }
                }.tint(c.gold).disabled(!on)
                if iqOn && on {
                    ForEach(Prayers.iqKeys, id: \.self) { k in
                        let v = iq[k] ?? prayers.iqMin(k)
                        HStack {
                            Text(tr(Prayers.names.first { $0.0 == k }?.1 ?? "")).font(F.plex(14.5)).foregroundStyle(c.text)
                            Spacer()
                            Button { let n = max(5, v - 5); iq[k] = n; prayers.setIqMin(k, n) } label: { Text("−").font(.system(size: 22, weight: .medium)).foregroundStyle(c.gold).frame(width: 40, height: 36) }.buttonStyle(.plain).disabled(v <= 5)
                            Text(tr("بعد {0} د", v.ar)).font(F.plex(14)).foregroundStyle(c.text).frame(width: 80)
                            Button { let n = min(60, v + 5); iq[k] = n; prayers.setIqMin(k, n) } label: { Text("+").font(.system(size: 22, weight: .medium)).foregroundStyle(c.gold).frame(width: 40, height: 36) }.buttonStyle(.plain).disabled(v >= 60)
                        }.padding(.horizontal, 14).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 14).fill(c.surface.opacity(0.5)))
                    }
                }
                Text(tr("صوت الأذان")).font(F.plex(15, .semibold))
                ForEach(Adhan.voices, id: \.id) { v in
                    Button { voice = v.id; Adhan.setVoice(v.id) } label: {
                        HStack { VStack(alignment: .leading) { Text(v.name).font(F.plex(14.5, .semibold)).foregroundStyle(c.text); Text(v.muezzin).font(F.plex(12)).foregroundStyle(c.muted) }
                            Spacer(); Image(systemName: voice == v.id ? "checkmark.circle.fill" : "circle").foregroundStyle(voice == v.id ? c.gold : c.faint) }
                        .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(c.surface.opacity(0.6))).overlay(RoundedRectangle(cornerRadius: 14).stroke(voice == v.id ? c.gold : c.lineSoft))
                    }.buttonStyle(.plain)
                }
                // two tests: hear the chosen adhan now, and the real notification in 10 seconds
                HStack(spacing: 10) {
                    GhostButton(title: adhanP.playing ? tr("إيقاف") : tr("استماع للأذان"), icon: adhanP.playing ? "stop.fill" : "play.fill") {
                        if adhanP.playing { adhanP.stop() } else { adhanP.play(fajr: false) }
                    }.frame(maxWidth: .infinity)
                    GhostButton(title: tr("تجربة الإشعار"), icon: "bell") {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { testMsg = tr("جارٍ التجهيز…") }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task {
                            let ok = await prayers.testNotification()
                            testMsg = ok ? tr("سيصل إشعار الأذان بعد ١٠ ثوانٍ — يمكنك إغلاق التطبيق أو قفل الشاشة") : tr("اسمح للتطبيق بالإشعارات من الإعدادات أولًا")
                        }
                    }.frame(maxWidth: .infinity)
                }
                if !testMsg.isEmpty {
                    HStack(spacing: 8) {
                        Ico(name: "bell", size: 14).foregroundStyle(c.onGold).frame(width: 24, height: 24).background(Circle().fill(c.gold))
                        Text(testMsg).font(F.plex(12.5, .semibold)).foregroundStyle(c.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14).fill(c.gold.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.gold.opacity(0.45)))
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                Text(tr("في الإشعار يُسمع أول ٣٠ ثانية من الأذان (أقصى ما يسمح به الآيفون)، والمس الإشعار لسماعه كاملًا.")).font(F.plex(12)).foregroundStyle(c.muted)
                GhostButton(title: busy ? tr("جارٍ التحديد…") : tr("حدّد موقعي تلقائيًا"), icon: "location") {
                    busy = true; locOk = nil
                    Task {
                        let ok = await prayers.locate(); busy = false
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { locOk = ok }
                        if ok { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                    }
                }.frame(maxWidth: .infinity)
                // the result under the button (a toast was hidden behind this sheet)
                if let ok = locOk {
                    HStack(spacing: 8) {
                        Ico(name: ok ? "check" : "xmark", size: 14).foregroundStyle(ok ? c.onGold : .white)
                            .frame(width: 24, height: 24).background(Circle().fill(ok ? c.gold : Color.red.opacity(0.75)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ok ? tr("تم تحديث الموقع") : tr("تعذّر تحديد الموقع — اكتب مدينتك")).font(F.plex(13, .bold)).foregroundStyle(c.text)
                            if ok { Text(prayers.place).font(F.plex(12)).foregroundStyle(c.gold).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14).fill(c.gold.opacity(ok ? 0.12 : 0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.gold.opacity(ok ? 0.45 : 0.15)))
                    .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
                }
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
        .onDisappear { if adhanP.playing { adhanP.stop() } }
        .onAppear {
            pre = prayers.preMinutes; on = prayers.alertsOn; iqOn = prayers.iqOn; voice = Adhan.voiceId; Task { await Adhan.prepare(); prayers.schedule() }
            UNUserNotificationCenter.current().getNotificationSettings { s in DispatchQueue.main.async { notifDenied = s.authorizationStatus == .denied } }
        }
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
    private var active: Bool { pushed || tabOn }
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
