import SwiftUI
import UserNotifications

struct AdhkarView: View {
    @Environment(\.pal) private var c
    @State private var kind = "morning"
    @State private var counts: [Int: Int] = [:]
    private static let data: [String: [(text: String, count: Int)]] = {
        guard let u = Bundle.main.url(forResource: "adhkar", withExtension: "json"), let d = try? Data(contentsOf: u) else { return [:] }
        return J(data: d).dict.mapValues { $0.array.map { (text: $0["text"].str, count: max(1, $0["count"].int)) } }
    }()
    var body: some View {
        let kinds = [("morning", "أذكار الصباح"), ("evening", "أذكار المساء"), ("sleep", "أذكار النوم")].filter { AdhkarView.data[$0.0] != nil }
        let list = AdhkarView.data[kind] ?? []
        let done = list.indices.filter { (counts[$0] ?? 0) >= list[$0].count }.count
        ScrollView {
            LazyVStack(spacing: 12) {
                HStack(spacing: 8) { ForEach(kinds, id: \.0) { k, l in Pill(title: l, on: kind == k) { kind = k; counts = [:] } } }.padding(.top, 14)
                Text("\(done.ar) من \(list.count.ar) — أُنجزت").font(F.plex(12.5)).foregroundStyle(c.muted)
                ForEach(Array(list.enumerated()), id: \.offset) { i, z in
                    let n = counts[i] ?? 0, finished = n >= z.count
                    Button { if !finished { counts[i] = n + 1; UIImpactFeedbackGenerator(style: .light).impactOccurred() } } label: {
                        VStack(spacing: 12) {
                            Text(z.text).font(F.amiri(19, bold: false)).foregroundStyle(c.text).lineSpacing(8).multilineTextAlignment(.center)
                            HStack {
                                Text(finished ? "تمّ ✓" : "اضغط للعدّ").font(F.plex(12)).foregroundStyle(finished ? c.ok : c.muted)
                                Spacer()
                                Text("\(n.ar) / \(z.count.ar)").font(F.plex(15, .bold)).foregroundStyle(c.gold)
                            }
                        }
                        .padding(18).background(RoundedRectangle(cornerRadius: 22).fill(finished ? c.gold.opacity(0.08) : c.surface)).overlay(RoundedRectangle(cornerRadius: 22).stroke(finished ? c.gold.opacity(0.5) : c.line))
                        .opacity(finished ? 0.75 : 1)
                    }.buttonStyle(.plain).padding(.horizontal, 16)
                }
            }.padding(.bottom, 24)
        }
    }
}

struct PrayerView: View {
    @EnvironmentObject var prayers: Prayers
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Button { ui.sheet = .prayer } label: { Label(prayers.place.isEmpty ? "حدّد مدينتك" : prayers.place, systemImage: "mappin.and.ellipse").font(F.plex(15, .semibold)).foregroundStyle(c.text) }.padding(.top, 16)
                Text(Prayers.hijri()).font(F.plex(13)).foregroundStyle(c.muted)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    if let n = prayers.next() {
                        let left = max(0, Int(n.time.timeIntervalSince(ctx.date)))
                        ZStack {
                            Circle().stroke(c.lineSoft, lineWidth: 6)
                            Circle().trim(from: 0, to: 1 - min(1, Double(left) / 21600)).stroke(c.goldGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                            VStack(spacing: 4) {
                                Text("الصلاة القادمة").font(F.plex(13)).foregroundStyle(c.muted)
                                Text(n.name).font(F.amiri(36)).foregroundStyle(c.gold)
                                Text(String(format: "%02d:%02d:%02d", left / 3600, left % 3600 / 60, left % 60)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(c.text)
                                Text(Fmt.time(n.time)).font(F.plex(13)).foregroundStyle(c.muted)
                            }
                        }.frame(width: 240, height: 240)
                    }
                }
                Panel(pad: 8) {
                    ForEach(prayers.forDay()) { p in
                        HStack { Text(p.name).font(F.plex(15, .semibold)); Spacer(); Image(systemName: icon(prayers.mode(p.key))).foregroundStyle(c.muted); Text(Fmt.time(p.time)).font(F.plex(15, .semibold)).foregroundStyle(c.gold) }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                }.padding(.horizontal, 16).id(prayers.rev)
                HStack { GhostButton(title: "الموقع وتنبيه الأذان", icon: "slider.horizontal.3") { ui.sheet = .prayer }; GhostButton(title: "القبلة", icon: "location.north.circle") { ui.path.append(.qibla) } }
            }.padding(.bottom, 24)
        }
    }
}
func icon(_ m: String) -> String { m == "adhan" ? "speaker.wave.2.fill" : m == "notify" ? "bell.fill" : "bell.slash" }

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
                Text("مواقيت الصلاة والأذان").font(F.amiri(24)).foregroundStyle(c.text)
                Label(prayers.place.isEmpty ? "لم تُحدَّد مدينتك بعد" : prayers.place, systemImage: "mappin").font(F.plex(14)).foregroundStyle(c.muted)
                if notifDenied {
                    HStack { Text("الإشعارات متوقفة — لن يصلك تنبيه الأذان").font(F.plex(13)); Spacer(); Button("اسمح") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }.font(F.plex(13, .bold)) }
                        .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(c.danger.opacity(0.12)))
                }
                ForEach(prayers.forDay()) { p in
                    let m = modes[p.key] ?? prayers.mode(p.key)
                    HStack {
                        VStack(alignment: .leading) { Text(p.name).font(F.plex(15, .semibold)); Text(Fmt.time(p.time)).font(F.plex(12)).foregroundStyle(c.muted) }
                        Spacer()
                        ForEach(["adhan", "notify", "off"].filter { p.key != "sunrise" || $0 != "adhan" }, id: \.self) { k in
                            Button { prayers.setMode(p.key, k); modes[p.key] = k } label: {
                                VStack(spacing: 2) { Image(systemName: icon(k)); Text(k == "adhan" ? "أذان" : k == "notify" ? "إشعار" : "بدون").font(F.plex(10)) }
                                    .foregroundStyle(m == k ? c.gold : c.muted).padding(.horizontal, 9).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 12).fill(m == k ? c.gold.opacity(0.18) : .clear))
                            }.buttonStyle(.plain).disabled(!on)
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 16).fill(c.surface.opacity(0.6)))
                }
                Toggle(isOn: Binding(get: { on }, set: { v in on = v; prayers.setAlerts(v); if v { Task { notifDenied = !(await prayers.requestNotifications()) } } })) {
                    VStack(alignment: .leading) { Text("تنبيهات الصلاة").font(F.plex(15, .semibold)); Text("أذان أو إشعار عند دخول كل وقت حسب اختيارك").font(F.plex(12)).foregroundStyle(c.muted) }
                }.tint(c.gold)
                Text("تنبيه قبل الصلاة").font(F.plex(15, .semibold))
                HStack(spacing: 6) { ForEach([0, 5, 10, 15, 30], id: \.self) { m in Pill(title: m == 0 ? "بدون" : "\(m.ar) د", on: pre == m) { pre = m; prayers.setPre(m) } } }
                Text("صوت الأذان").font(F.plex(15, .semibold))
                ForEach(Adhan.voices, id: \.id) { v in
                    Button { voice = v.id; Adhan.setVoice(v.id) } label: {
                        HStack { VStack(alignment: .leading) { Text(v.name).font(F.plex(14.5, .semibold)).foregroundStyle(c.text); Text(v.muezzin).font(F.plex(12)).foregroundStyle(c.muted) }
                            Spacer(); Image(systemName: voice == v.id ? "checkmark.circle.fill" : "circle").foregroundStyle(voice == v.id ? c.gold : c.faint) }
                        .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(c.surface.opacity(0.6))).overlay(RoundedRectangle(cornerRadius: 14).stroke(voice == v.id ? c.gold : c.lineSoft))
                    }.buttonStyle(.plain)
                }
                GhostButton(title: "تجربة الأذان", icon: "play.fill") { testAdhan = true; AdhanPlayer.shared.play(fajr: false) }
                Text("في الإشعار يُسمع أول ٣٠ ثانية من الأذان (أقصى ما يسمح به الآيفون)، والمس الإشعار لسماعه كاملًا.").font(F.plex(12)).foregroundStyle(c.muted)
                GhostButton(title: busy ? "جارٍ التحديد…" : "حدّد موقعي تلقائيًا", icon: "location") {
                    busy = true; Task { let ok = await prayers.locate(); busy = false; ui.say(ok ? "تم تحديث المواقيت: \(prayers.place)" : "تعذّر تحديد الموقع — اكتب مدينتك") }
                }.frame(maxWidth: .infinity)
                Text("أو اكتب مدينتك يدويًا:").font(F.plex(13)).foregroundStyle(c.muted)
                TextField("المدينة — مثال: القاهرة", text: $city).padding(12).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                TextField("الدولة — مثال: مصر", text: $country).padding(12).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                GoldButton(title: "حفظ المدينة", icon: "checkmark") {
                    guard !city.isEmpty else { return }
                    Task { let ok = await prayers.setCity(city, country); ui.say(ok ? "تم حفظ المدينة" : "لم نجد هذه المدينة"); if ok { dismiss() } }
                }.frame(maxWidth: .infinity)
            }.padding(20)
        }
        .font(F.plex(15)).background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, .rightToLeft)
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
            Text("اتجاه القبلة").font(F.amiri(28)).foregroundStyle(c.text).padding(.top, 20)
            Text("\(Int(q).ar)° من الشمال").font(F.plex(14)).foregroundStyle(c.muted)
            ZStack {
                Circle().stroke(c.line, lineWidth: 2)
                ForEach(0..<36) { i in Rectangle().fill(i % 9 == 0 ? c.gold : c.faint).frame(width: 2, height: i % 9 == 0 ? 14 : 7).offset(y: -125).rotationEffect(.degrees(Double(i) * 10 - prayers.heading)) }
                Text("N").font(.system(size: 14, weight: .bold)).foregroundStyle(c.danger).offset(y: -100).rotationEffect(.degrees(-prayers.heading))
                Image(systemName: "location.north.fill").font(.system(size: 70)).foregroundStyle(c.goldGradient).rotationEffect(.degrees(rel))
                Text("🕋").font(.system(size: 28)).offset(y: -150).rotationEffect(.degrees(rel))
            }.frame(width: 260, height: 260).padding(30).animation(.easeOut(duration: 0.25), value: prayers.heading)
            Text(abs(((rel.truncatingRemainder(dividingBy: 360)) + 540).truncatingRemainder(dividingBy: 360) - 180) < 5 ? "أنت متجه إلى القبلة ✓" : "أدر الهاتف حتى يشير السهم للأعلى").font(F.plex(15, .semibold)).foregroundStyle(c.gold)
            Spacer()
        }
        .frame(maxWidth: .infinity).background(Backdrop())
        .navigationTitle("القبلة").navigationBarTitleDisplayMode(.inline)
        .onAppear { prayers.startHeading() }.onDisappear { prayers.stopHeading() }
    }
}
