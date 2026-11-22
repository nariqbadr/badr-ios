import SwiftUI

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
func clock(_ d: Date) -> String { let f = DateFormatter(); f.locale = L.locale; f.dateFormat = "h:mm"; return f.string(from: d) }
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
                    ForEach(ex) { p in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 6).fill(PrayerSky.swatch(p.key)).frame(width: 20, height: 20)
                            Text(p.name).font(F.plex(12.5)).foregroundStyle(PrayerSky.muted).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Fmt.time(p.time)).font(F.amiri(15)).foregroundStyle(PrayerSky.soft).lineLimit(1)
                        }.padding(.horizontal, 10).padding(.vertical, 9).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.18)))
                    }
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
struct NewBadge: View {
    @Environment(\.pal) private var c
    var body: some View { Text(tr("جديد")).font(F.plex(10, .bold)).foregroundStyle(c.gold2).padding(.horizontal, 6).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 6).fill(c.gold.opacity(0.14))) }
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
        let items = (quiet ? [] : [("adhan", tr("أذان"), "volume")]) + [("notify", tr("إشعار"), "bell"), ("off", tr("بدون"), "mute")]
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8).fill(PrayerSky.swatch(p.key)).frame(width: 24, height: 24).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) { Text(p.name).font(F.plex(15, .semibold)).foregroundStyle(c.text).lineLimit(1); if new { NewBadge() } }
                Text(sub ?? Fmt.time(p.time)).font(F.plex(12.5)).foregroundStyle(c.faint.mix(c.muted, 0.5)).lineLimit(1)
            }
            Spacer(minLength: 4)
            MiniSeg(items: items, selected: prayers.mode(p.key), enabled: prayers.alertsOn) { prayers.setMode(p.key, $0) }
        }.frame(minHeight: 60)
    }
}
