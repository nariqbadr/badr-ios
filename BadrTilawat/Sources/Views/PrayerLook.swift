import SwiftUI
import AVFoundation
import AudioToolbox

/// Each prayer has its own quiet colour (the sky at its time), the same in every theme — as on Android.
enum PrayerSky {
    private static func c(_ v: UInt32) -> Color { Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255) }
    /// (lighter, darker)
    static func of(_ k: String) -> (Color, Color) {
        switch k {
        case "fajr": return (c(0x2C3158), c(0x15182E))
        case "sunrise": return (c(0x3A3A3A), c(0x262626))
        case "duha": return (c(0x5C5235), c(0x34301F))
        case "dhuhr": return (c(0x34496A), c(0x1A2638))
        case "asr": return (c(0x6E6442), c(0x3B3626))
        case "maghrib": return (c(0x4C3032), c(0x2A1D1F))
        case "isha": return (c(0x1F2439), c(0x0F1220))
        default: return (c(0x2E2843), c(0x16131F))
        }
    }
    static let light = c(0xF3ECD8), soft = c(0xE6DFCF), muted = c(0xB9B19C)
    static func card(_ k: String, strong: Bool = false) -> LinearGradient {
        let (a, b) = of(k)
        return strong ? LinearGradient(colors: [b.mix(.black, 0.12), b.mix(a, 0.75), a.mix(.black, 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [b, b.mix(a, 0.55), b.mix(a, 0.15)], startPoint: .leading, endPoint: .trailing)
    }
    static func swatch(_ k: String) -> LinearGradient { let (a, b) = of(k); return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing) }
}

func prayerLabel(_ p: PrayerTime) -> String { p.key == "dhuhr" && Calendar.current.component(.weekday, from: p.time) == 6 ? tr("الجمعة") : p.name }
private var clockFmts: [String: DateFormatter] = [:]
/// «4:58» (one formatter per language, not one per call: the home card asks every second)
@MainActor func clock(_ d: Date) -> String {
    let k = L.locale.identifier
    let f = clockFmts[k] ?? { let f = DateFormatter(); f.locale = L.locale; f.dateFormat = "h:mm"; clockFmts[k] = f; return f }()
    return f.string(from: d)
}
func hms(_ left: Int) -> String { String(format: "%02d:%02d:%02d", left / 3600, left % 3600 / 60, left % 60) }

/// «تنبيه {name}»: one tap moves adhan → notification → nothing (a notification or nothing for the quiet ones)
@MainActor func cycleMode(_ p: PrayerTime) {
    let pr = Prayers.shared, m = pr.mode(p.key), quiet = Prayers.quiet.contains(p.key)
    let nx = quiet ? (m == "off" ? "notify" : "off") : (m == "adhan" ? "notify" : m == "notify" ? "off" : "adhan")
    if !pr.alertsOn { pr.setAlerts(true) }
    pr.setMode(p.key, nx)
    UIState.shared?.say(nx == "adhan" ? tr("سيُرفع الأذان لصلاة {0}", p.name) : nx == "notify" ? tr("إشعار فقط: {0}", p.name) : tr("بدون تنبيه: {0}", p.name))
}

// MARK: the home card

/// The prayer card on the home screen: it wears the next prayer's colour; its name and the time left, the day's six times, then duha and the night.
struct PrayerBand: View {
    @EnvironmentObject var prayers: Prayers
    private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let list = prayers.forDay(ctx.date), next = prayers.next(), ex = prayers.extras(ctx.date)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { ui.sheet = .prayer } label: {
                        HStack(spacing: 5) {
                            SiteIcon(name: "pin", size: 17, color: c.gold2)
                            Text(prayers.place.isEmpty ? tr("حدّد مدينتك") : prayers.place).font(F.plex(13.5, .semibold)).foregroundStyle(PrayerSky.light).lineLimit(1)
                            SiteIcon(name: "chev-d", size: 17, color: PrayerSky.muted)
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)
                    Spacer()
                    Text(Prayers.hijri()).font(F.plex(12.5)).foregroundStyle(PrayerSky.muted).lineLimit(1)
                }
                if let n = next {
                    let left = max(0, Int(n.time.timeIntervalSince(ctx.date)))
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(tr("الصلاة القادمة")).font(F.plex(12.5, .semibold)).foregroundStyle(PrayerSky.muted)
                            Text(prayerLabel(n)).font(F.amiri(38)).foregroundStyle(PrayerSky.light).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(tr("المتبقي")).font(F.plex(12.5, .semibold)).foregroundStyle(PrayerSky.muted)
                            Text(hms(left)).font(F.amiri(30)).foregroundStyle(PrayerSky.light).monospacedDigit().environment(\.layoutDirection, .leftToRight)
                        }
                    }
                }
                HStack(spacing: 2) {
                    ForEach(list) { p in
                        let on = p.key == next?.key && p.time == next?.time, past = !on && p.time < ctx.date
                        VStack(spacing: 2) {
                            Text(prayerLabel(p)).font(F.plex(11.5, on ? .bold : .medium)).foregroundStyle(on ? c.gold2 : PrayerSky.muted).lineLimit(1)
                            Text(clock(p.time)).font(F.amiri(17)).foregroundStyle(PrayerSky.soft).lineLimit(1)
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(on ? PrayerSky.light.opacity(0.12) : .clear)).opacity(past ? 0.55 : 1)
                    }
                }.padding(4).background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.18)))
                HStack(spacing: 8) {
                    ForEach(ex) { p in ExtraChip(p: p) }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 26).fill(PrayerSky.card(next?.key ?? "asr", strong: true)))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture { ui.go(.prayer) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .id(prayers.rev)
    }
}

// MARK: the prayer page's timeline

/// Today's times as a timeline: a card in its colour for each prayer, thin rows for sunrise, duha and the night's last third, «الآن» above the next.
struct PrayerTimeline: View {
    @EnvironmentObject var prayers: Prayers
    @Environment(\.pal) private var c
    let now: Date
    private let rail: CGFloat = 28
    var body: some View {
        let all = prayers.timeline(now), next = prayers.next()
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(tr("مواقيت اليوم")).font(F.plex(13.5, .bold)).foregroundStyle(c.gold)
                Rectangle().fill(c.gold.opacity(0.22)).frame(height: 1)
            }.padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 12)
            VStack(spacing: 10) {
                ForEach(all) { p in
                    let isNext = p.key == next?.key && p.time == next?.time
                    let past = !isNext && p.time < now && p.key != "qiyam"
                    if isNext { nowRow }
                    if Prayers.quiet.contains(p.key) { thin(p, past) }
                    else if isNext { nextCard(p) }
                    else { card(p, past) }
                }
            }
            .background(alignment: .leading) { Rectangle().fill(c.gold.opacity(0.22)).frame(width: 1.5).padding(.vertical, 18).padding(.leading, rail / 2 - 0.75) }
        }
    }
    private func dot() -> some View {
        Circle().fill(c.bg).frame(width: 11, height: 11).overlay(Circle().strokeBorder(c.gold.opacity(0.45), lineWidth: 1.5)).frame(width: rail)
    }
    private func bell(_ p: PrayerTime, big: Bool = false) -> some View {
        let m = prayers.mode(p.key), on = prayers.alertsOn && m != "off"
        return Button { cycleMode(p) } label: {
            SiteIcon(name: on ? icon(m) : "mute", size: 20, color: PrayerSky.soft)
                .frame(width: big ? 48 : 44, height: big ? 48 : 44)
                .background(Circle().fill(Color.black.opacity(0.12))).overlay(Circle().strokeBorder(PrayerSky.light.opacity(0.22)))
        }.buttonStyle(.plain).accessibilityLabel(tr("تنبيه {0}", p.name))
    }
    private func card(_ p: PrayerTime, _ past: Bool) -> some View {
        HStack(spacing: 10) {
            dot()
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(prayerLabel(p)).font(F.amiri(25)).foregroundStyle(PrayerSky.light).lineLimit(1)
                    HStack(spacing: 8) {
                        Text(Fmt.time(p.time)).font(F.amiri(20)).foregroundStyle(PrayerSky.soft)
                        if let iq = prayers.iqamaAt(p) {
                            Circle().fill(PrayerSky.muted).frame(width: 3, height: 3)
                            Text(tr("الإقامة {0}", Fmt.time(iq))).font(F.plex(12.5)).foregroundStyle(PrayerSky.muted).lineLimit(1)
                        }
                    }
                }
                Spacer()
                bell(p)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 22).fill(PrayerSky.card(p.key)))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.08)))
        }.opacity(past ? 0.72 : 1)
    }
    private func nextCard(_ p: PrayerTime) -> some View {
        HStack(spacing: 10) {
            Circle().fill(PrayerSky.light).frame(width: 22, height: 22).background(Circle().fill(PrayerSky.light.opacity(0.18)).frame(width: 40, height: 40)).frame(width: rail)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(prayerLabel(p)).font(F.amiri(32)).foregroundStyle(PrayerSky.light).lineLimit(1)
                    Text(Fmt.time(p.time)).font(F.amiri(21)).foregroundStyle(PrayerSky.soft)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("التالية")).font(F.plex(12, .bold)).foregroundStyle(PrayerSky.light).padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(PrayerSky.light.opacity(0.12)))
                    if let iq = prayers.iqamaAt(p) { Text(tr("الإقامة {0}", Fmt.time(iq))).font(F.plex(12.5)).foregroundStyle(PrayerSky.muted).lineLimit(1) }
                }
                bell(p, big: true)
            }
            .padding(.horizontal, 18).padding(.vertical, 20)
            .background(RoundedRectangle(cornerRadius: 24).fill(PrayerSky.card(p.key, strong: true)))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(PrayerSky.light.opacity(0.14)))
        }
    }
    private var nowRow: some View {
        HStack(spacing: 10) {
            SiteIcon(name: "sun", size: 20, color: c.gold2).background(Circle().fill(c.bg).frame(width: 24, height: 24)).frame(width: rail)
            Text(tr("الآن")).font(F.plex(13.5, .bold)).foregroundStyle(c.text)
            Text(Fmt.time(now)).font(F.amiri(16)).foregroundStyle(c.text)
            LinearGradient(colors: [c.gold2.opacity(0.7), c.gold2.opacity(0.1)], startPoint: .leading, endPoint: .trailing).frame(height: 1).environment(\.layoutDirection, L.dir)
        }.padding(.vertical, 4)
    }
    private func thin(_ p: PrayerTime, _ past: Bool) -> some View {
        let on = prayers.alertsOn && prayers.mode(p.key) != "off"
        return HStack(spacing: 10) {
            dot()
            SiteIcon(name: p.key == "qiyam" ? "moon" : "sun", size: 18, color: c.gold)
            Text(p.key == "qiyam" ? tr("قيام الليل، الثلث الأخير") : p.name).font(F.plex(14)).foregroundStyle(c.muted).lineLimit(1)
            Rectangle().fill(c.gold.opacity(0.16)).frame(height: 1)
            Text(Fmt.time(p.time)).font(F.amiri(19)).foregroundStyle(c.text).lineLimit(1)
            if p.key == "sunrise" { Color.clear.frame(width: 44, height: 44) }
            else { Button { cycleMode(p) } label: { SiteIcon(name: on ? "bell" : "mute", size: 18, color: on ? c.gold : c.faint).frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel(tr("تنبيه {0}", p.name)) }
        }.frame(minHeight: 44).opacity(past ? 0.72 : 1)
    }
}

// MARK: grouped settings (iOS-style lists)

struct GroupHead: View {
    let title: String; var sub: String? = nil
    @Environment(\.pal) private var c
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(F.plex(13.5, .bold)).foregroundStyle(c.gold)
            if let sub { Text(sub).font(F.plex(12)).foregroundStyle(c.faint.mix(c.muted, 0.5)) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.top, 24).padding(.bottom, 8)
    }
}
struct SettingsGroup<Content: View>: View {
    @Environment(\.pal) private var c
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }.padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 20).fill(c.surface))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(c.text.opacity(0.06)))
    }
}
struct Hairline: View {
    var inset: CGFloat = 0
    @Environment(\.pal) private var c
    var body: some View { Rectangle().fill(c.text.opacity(0.07)).frame(height: 1).padding(.leading, inset) }
}
/// «جديد» on a new setting: it goes once the setting is used, or after the days the dashboard sets (7 by default) from the first time it was shown
final class NewMarks: ObservableObject {
    static let shared = NewMarks()
    @Published private(set) var usedKeys: Set<String> = []
    private let d = UserDefaults.standard
    func show(_ k: String) -> Bool {
        if usedKeys.contains(k) || d.bool(forKey: "newUsed-\(k)") { return false }
        let now = Date().timeIntervalSince1970
        var since = d.double(forKey: "newSince-\(k)"); if since == 0 { since = now; d.set(now, forKey: "newSince-\(k)") }
        let j = Repo.shared.data?.site.j["newFeatureDays"]
        let days = (j != nil && j!.isNull == false) ? j!.int : 7
        return days > 0 && now - since < Double(days) * 86400
    }
    func used(_ k: String) { guard !usedKeys.contains(k) else { return }; d.set(true, forKey: "newUsed-\(k)"); usedKeys.insert(k) }
}
struct NewBadge: View {
    var k: String
    @ObservedObject private var marks = NewMarks.shared
    @Environment(\.pal) private var c
    var body: some View { if marks.show(k) { badge } }
    private var badge: some View { Text(tr("جديد")).font(F.plex(10, .bold)).foregroundStyle(c.gold2).padding(.horizontal, 6).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 6).fill(c.gold.opacity(0.14))) }
}
/// a small segmented control (adhan / notification / off…)
struct MiniSeg: View {
    let items: [(String, String, String)]; let selected: String; var enabled = true; let pick: (String) -> Void
    @Environment(\.pal) private var c
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { k, label, ic in
                let on = k == selected && enabled
                Button { pick(k) } label: {
                    HStack(spacing: 4) {
                        SiteIcon(name: ic, size: 14, color: on ? c.gold2 : c.faint.mix(c.muted, 0.5))
                        Text(label).font(F.plex(12, on ? .semibold : .medium)).foregroundStyle(on ? c.text : c.faint.mix(c.muted, 0.5)).lineLimit(1)
                    }.frame(width: 60, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9).fill(on ? c.surface3.mix(c.gold, 0.08) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? c.gold.opacity(0.28) : .clear))
                }.buttonStyle(.plain).disabled(!enabled)
            }
        }.padding(2).background(RoundedRectangle(cornerRadius: 11).fill(Color.black.opacity(0.28)))
    }
}
struct PrayerAlertRow: View {
    @EnvironmentObject var prayers: Prayers
    @Environment(\.pal) private var c
    let p: PrayerTime; var new = false; var sub: String? = nil
    var body: some View {
        let quiet = Prayers.quiet.contains(p.key)
        let items = p.key == "qiyam" ? [("notify", tr("بالصوت"), "volume"), ("off", tr("بدون"), "mute")]
            : (quiet ? [] : [("adhan", tr("أذان"), "volume")]) + [("notify", tr("إشعار"), "bell"), ("off", tr("بدون"), "mute")]
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8).fill(PrayerSky.swatch(p.key)).frame(width: 24, height: 24).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) { Text(p.name).font(F.plex(15, .semibold)).foregroundStyle(c.text).lineLimit(1); if new { NewBadge(k: "alert-\(p.key)") } }
                Text(sub ?? Fmt.time(p.time)).font(F.plex(12.5)).foregroundStyle(c.faint.mix(c.muted, 0.5)).lineLimit(1)
            }
            Spacer(minLength: 4)
            MiniSeg(items: items, selected: prayers.mode(p.key), enabled: prayers.alertsOn) { if new { NewMarks.shared.used("alert-\(p.key)") }; prayers.setMode(p.key, $0) }
        }.frame(minHeight: 60)
    }
}

/// a full-width segmented bar (the salawat's frequency, a reminder's voice)
struct SegBar<T: Hashable>: View {
    let items: [(T, String)]; let selected: T; let pick: (T) -> Void
    @Environment(\.pal) private var c
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { k, label in
                let on = k == selected
                Button { pick(k) } label: {
                    Text(label).font(F.plex(12.5, on ? .bold : .medium)).foregroundStyle(on ? c.text : c.muted).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(on ? c.surface3.mix(c.gold, 0.08) : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? c.gold.opacity(0.28) : .clear))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(3).background(RoundedRectangle(cornerRadius: 13).fill(Color.black.opacity(0.28)))
    }
}

/// hears a reminder's voice in the settings: Sheikh Badr al-Turki's recording, or the notification sound
@MainActor
final class ReminderVoice: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = ReminderVoice()
    @Published private(set) var playing: String?
    private var player: AVAudioPlayer?
    func toggle(_ k: String, badr: Bool) {
        if playing == k { stop(); return }
        stop()
        guard badr else { AudioServicesPlaySystemSound(1007); return }
        guard let u = Bundle.main.url(forResource: k, withExtension: "caf"), let p = try? AVAudioPlayer(contentsOf: u) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        p.delegate = self; p.play(); player = p; playing = k
    }
    /// Sheikh Badr al-Turki's whole recording (opened from the reminder's notification), whatever voice the notification has
    func full(_ k: String) {
        stop()
        let u = k == "qiyam" ? Bundle.main.url(forResource: "qiyam_full", withExtension: "m4a") : Bundle.main.url(forResource: k, withExtension: "caf")
        guard let u, let p = try? AVAudioPlayer(contentsOf: u) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        p.delegate = self; p.play(); player = p; playing = k
    }
    /// where the recording is (0…1)
    var progress: Double { guard let p = player, p.duration > 0 else { return 0 }; return p.currentTime / p.duration }
    func stop() { player?.stop(); player = nil; playing = nil }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in self.stop() } }
}

/// the reminder's voice: the notification sound or Sheikh Badr al-Turki — heard here, and its notification tried at once
struct VoiceBox: View {
    @EnvironmentObject var prayers: Prayers
    @ObservedObject private var rv = ReminderVoice.shared
    @Environment(\.pal) private var c
    @State private var sent = false
    let k: String
    var body: some View {
        let _ = prayers.rev
        let badr = prayers.voice(k) == "badr", playing = rv.playing == k
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("الصوت")).font(F.plex(12.5)).foregroundStyle(c.faint.mix(c.muted, 0.5)).padding(.top, 4)
            // the notification sound, or the imam of the Grand Mosque in Makkah (his full title on two lines)
            HStack(spacing: 2) {
                ForEach(["default", "badr"], id: \.self) { v in
                    let on = prayers.voice(k) == v
                    Button { rv.stop(); prayers.setVoice(k, v) } label: {
                        VStack(spacing: 1) {
                            if v == "badr" {
                                Text(tr("إمام الحرم المكي")).font(F.plex(10.5, .semibold)).foregroundStyle(on ? c.gold2 : c.faint.mix(c.muted, 0.5))
                                Text(tr("الشيخ د. بدر بن محمد التركي")).font(F.plex(12.5, on ? .bold : .medium)).foregroundStyle(on ? c.text : c.muted)
                            } else { Text(tr("صوت الإشعار")).font(F.plex(12.5, on ? .bold : .medium)).foregroundStyle(on ? c.text : c.muted) }
                        }.lineLimit(1).minimumScaleFactor(0.75).padding(.horizontal, 6).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10).fill(on ? c.surface3.mix(c.gold, 0.08) : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? c.gold.opacity(0.28) : .clear))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).frame(width: v == "badr" ? nil : 104)
                }
            }.fixedSize(horizontal: false, vertical: true).padding(3).background(RoundedRectangle(cornerRadius: 13).fill(Color.black.opacity(0.28)))
            HStack(spacing: 8) {
                btn(playing ? tr("إيقاف") : tr("استماع"), playing ? "pause" : "play", on: playing) { UIImpactFeedbackGenerator(style: .light).impactOccurred(); rv.toggle(k, badr: badr) }
                // «تجربة الإشعار» shows that it was pressed: a tap you feel, then «أُرسل الإشعار ✓» in gold for a moment
                btn(sent ? tr("أُرسل الإشعار") : tr("تجربة الإشعار"), sent ? "check" : "bell", on: sent) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        let ok = await prayers.testReminder(k)
                        if ok { UINotificationFeedbackGenerator().notificationOccurred(.success); withAnimation(.easeOut(duration: 0.2)) { sent = true }
                            try? await Task.sleep(nanoseconds: 2_500_000_000); withAnimation(.easeOut(duration: 0.3)) { sent = false } }
                        else { UIState.shared?.say(tr("اسمح بالإشعارات من الإعدادات أولًا")) }
                    }
                }
            }
        }
    }
    private func btn(_ t: String, _ ic: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 6) { SiteIcon(name: ic, size: 15, color: on ? c.gold2 : c.gold); Text(t).font(F.plex(13, .semibold)).foregroundStyle(on ? c.gold2 : c.text).lineLimit(1) }
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(on ? c.gold.opacity(0.14) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? c.gold.opacity(0.5) : c.text.opacity(0.08))).contentShape(Rectangle())
        }.buttonStyle(Press(scale: 0.95))
    }
}

/// «الضحى» and «قيام الليل» on the home card: each in its own sky — a gold one with the sun, a night one with the moon and stars
struct ExtraChip: View {
    let p: PrayerTime
    private static func c(_ h: UInt32) -> Color { Color(red: Double(h >> 16 & 255) / 255, green: Double(h >> 8 & 255) / 255, blue: Double(h & 255) / 255) }
    var body: some View {
        let duha = p.key == "duha"
        let (top, bottom, line, label, time) = duha ? (ExtraChip.c(0x6B6040), ExtraChip.c(0x3A3523), ExtraChip.c(0xE3C584), ExtraChip.c(0xE8DDBF), ExtraChip.c(0xF3ECD8))
                                                    : (ExtraChip.c(0x3E3760), ExtraChip.c(0x1B1828), ExtraChip.c(0xD1CCF2), ExtraChip.c(0xDAD5F2), ExtraChip.c(0xF1EEFB))
        VStack(alignment: .leading, spacing: 0) {
            Text(p.name).font(F.plex(11)).foregroundStyle(label).lineLimit(1)
            Text(Fmt.time(p.time)).font(F.amiri(16)).foregroundStyle(time).lineLimit(1)
        }
        .padding(.horizontal, 11).padding(.top, 6).padding(.bottom, 7).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: [top, bottom], startPoint: .topTrailing, endPoint: .bottomLeading)
                // the sun / the moon and stars, at the left corner (drawn left-to-right whatever the language)
                Canvas { ctx, _ in
                    if duha {
                        let k: CGFloat = 64 / 90, o = CGPoint(x: -16, y: -20)
                        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * k, y: o.y + y * k) }
                        ctx.fill(Path(ellipseIn: CGRect(x: P(45, 45).x - 14 * k, y: P(45, 45).y - 14 * k, width: 28 * k, height: 28 * k)), with: .color(line.opacity(0.35)))
                        var r = Path()
                        for (a, b) in [((45, 15), (45, 23)), ((45, 67), (45, 75)), ((15, 45), (23, 45)), ((67, 45), (75, 45)), ((24, 24), (29.5, 29.5)), ((60.5, 60.5), (66, 66)), ((24, 66), (29.5, 60.5)), ((60.5, 29.5), (66, 24))] as [((CGFloat, CGFloat), (CGFloat, CGFloat))] {
                            r.move(to: P(a.0, a.1)); r.addLine(to: P(b.0, b.1))
                        }
                        ctx.stroke(r, with: .color(line.opacity(0.35)), style: StrokeStyle(lineWidth: 2 * k, lineCap: .round))
                    } else {
                        let k: CGFloat = 66 / 90, o = CGPoint(x: -4, y: -4)
                        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * k, y: o.y + y * k) }
                        func disc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: P(x, y).x - r * k, y: P(x, y).y - r * k, width: 2 * r * k, height: 2 * r * k)) }
                        ctx.drawLayer { l in
                            l.fill(disc(24.5, 23.5, 15), with: .color(line.opacity(0.33)))
                            l.blendMode = .destinationOut
                            l.fill(disc(28.5, 19.5, 13.5), with: .color(.black))
                        }
                        for (x, y, r, a) in [(55, 14, 1.3, 0.6), (66, 30, 1.0, 0.6), (48, 44, 0.9, 0.6), (74, 12, 0.8, 0.6)] as [(CGFloat, CGFloat, CGFloat, Double)] {
                            ctx.fill(disc(x, y, r), with: .color(line.opacity(a)))
                        }
                    }
                }.environment(\.layoutDirection, .leftToRight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(line.opacity(duha ? 0.22 : 0.2)))
    }
}
