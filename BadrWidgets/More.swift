import WidgetKit
import SwiftUI
import AppIntents

// MARK: - the day: hijri date, the weekday drawn long, Ramadan

enum Hj {
    static let ar = Locale(identifier: "ar")
    static let cal: Calendar = { var c = Calendar(identifier: .islamicUmmAlQura); c.locale = Locale(identifier: "ar"); return c }()
    static func day(_ d: Date) -> Int { cal.component(.day, from: d) }
    /// the year as plain digits («1448»: inside Text("…") an Int was written «1,448»)
    static func year(_ d: Date) -> String { String(cal.component(.year, from: d)) }
    static func month(_ d: Date) -> String { let f = DateFormatter(); f.calendar = cal; f.locale = ar; f.dateFormat = "MMMM"; return f.string(from: d) }
    static func weekday(_ d: Date) -> String { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = ar; f.dateFormat = "EEEE"; return f.string(from: d) }
    static func greg(_ d: Date) -> String { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = ar; f.dateFormat = "d MMMM"; return latin(f.string(from: d)) }
    /// «الثلاثـــــاء»: the weekday with a long kashida, as calligraphers write it
    static func long(_ d: Date) -> String {
        let w = weekday(d)
        let m = ["الأحد": "الأحـــــد", "الاثنين": "الاثنيـــــن", "الثلاثاء": "الثلاثـــــاء", "الأربعاء": "الأربعـــــاء", "الخميس": "الخميـــــس", "الجمعة": "الجمعـــــة", "السبت": "السبـــــت"]
        return m[w] ?? w
    }
    static func latin(_ s: String) -> String { String(s.unicodeScalars.map { u -> Character in (0x660...0x669).contains(u.value) ? Character(UnicodeScalar(u.value - 0x660 + 48)!) : Character(u) }) }
    /// «٧ جمادى الآخرة ١٤٤٨»
    static func full(_ d: Date) -> String { "\(day(d)) \(month(d)) \(year(d))" }

    enum Season { case before(days: Int, frac: Double), ramadan(day: Int), eid(day: Int) }
    /// days left to 1 Ramadan; the day of Ramadan; the days of Eid al-Fitr
    static func season(_ now: Date) -> Season {
        let c = cal.dateComponents([.month, .day], from: now)
        if c.month == 9 { return .ramadan(day: c.day ?? 1) }
        if c.month == 10, let d = c.day, d <= 3 { return .eid(day: d) }
        let start = cal.nextDate(after: now, matching: DateComponents(month: 9, day: 1), matchingPolicy: .nextTime) ?? now
        let g = Calendar.current
        let days = max(0, g.dateComponents([.day], from: g.startOfDay(for: now), to: g.startOfDay(for: start)).day ?? 0)
        return .before(days: days, frac: max(0, min(1, 1 - Double(days) / 330)))
    }
    static func daysTo(_ month: Int, _ day: Int, _ now: Date) -> Int {
        let at = cal.nextDate(after: now, matching: DateComponents(month: month, day: day), matchingPolicy: .nextTime) ?? now
        let g = Calendar.current
        return max(0, g.dateComponents([.day], from: g.startOfDay(for: now), to: g.startOfDay(for: at)).day ?? 0)
    }
    /// «يومًا» / «يومين» / «أيام» with the number
    /// 1 Ramadan of the coming year
    static func ramadanStart(_ now: Date) -> Date { cal.nextDate(after: now, matching: DateComponents(month: 9, day: 1), matchingPolicy: .nextTime) ?? now }
    /// «8 فبراير 2027»
    static func gregFull(_ d: Date) -> String { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = ar; f.dateFormat = "d MMMM y"; return latin(f.string(from: d)) }
    static func daysText(_ n: Int) -> String { n == 1 ? "يوم واحد" : n == 2 ? "يومان" : (3...10).contains(n) ? "\(n) أيام" : "\(n) يومًا" }
}

/// Arabic with numbers set right to left: on the lock screen the widget's own direction did not reach the text, and
/// «السبت · 18 جمادى الآخرة» came out «جمادى الآخرة 18 · السبت», «رمضان بعد 72 يومًا» as «72 يومًا رمضان بعد»
func rtl(_ s: String) -> String { "\u{202B}\(s)\u{202C}" }

/// The prayer times the app shared, seen from one moment.
struct PDay {
    let all: [Shared.Prayer]; let at: Date
    init(_ at: Date) { self.at = at; all = (Shared.read("w_prayers", [Shared.Prayer].self) ?? []).sorted { $0.at < $1.at } }
    var today: [Shared.Prayer] { all.filter { Calendar.current.isDate(Date(timeIntervalSince1970: $0.at), inSameDayAs: at) } }
    var five: [Shared.Prayer] { today.filter { $0.key != "sunrise" } }
    var next: Shared.Prayer? { all.first { $0.key != "sunrise" && $0.at > at.timeIntervalSince1970 } }
    var prev: Shared.Prayer? { all.last { $0.key != "sunrise" && $0.at <= at.timeIntervalSince1970 } }
    var place: String { (Shared.d.string(forKey: "w_place") ?? "").components(separatedBy: "،").first?.trimmingCharacters(in: .whitespaces) ?? "" }
    /// midnight and the last third of the night (between maghrib and the next fajr)
    var night: (mid: Double, third: Double)? {
        guard let m = today.first(where: { $0.key == "maghrib" }), let f = all.first(where: { $0.key == "fajr" && $0.at > m.at }) else { return nil }
        let len = f.at - m.at
        return (m.at + len / 2, m.at + len * 2 / 3)
    }
    var empty: Bool { all.isEmpty }
    static func hm(_ t: Double) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "h:mm"; return f.string(from: Date(timeIntervalSince1970: t)) }
    static func ampm(_ t: Double) -> String { Calendar.current.component(.hour, from: Date(timeIntervalSince1970: t)) < 12 ? "ص" : "م" }
    /// entries: now, each prayer ahead (the next one moves on), and midnight (the date changes)
    static func dates(_ now: Date, extra: [Date] = []) -> [Date] {
        let all = Shared.read("w_prayers", [Shared.Prayer].self) ?? []
        var d = [now] + all.map { Date(timeIntervalSince1970: $0.at) }.filter { $0 > now && $0 < now.addingTimeInterval(36 * 3600) }
        let cal = Calendar.current
        if let mid = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) { d.append(mid) }
        d += extra.filter { $0 > now }
        return Array(Set(d)).sorted()
    }
}

/// A countdown that never runs below zero (WidgetKit's timer counts up once the moment is past).
struct Countdown: View {
    let to: Double; let font: Font; let color: Color
    var body: some View {
        Text(timerInterval: Date()...max(Date(), Date(timeIntervalSince1970: to)), countsDown: true)
            .font(font).foregroundStyle(color).monospacedDigit().environment(\.layoutDirection, .leftToRight)
    }
}

private func amiri(_ s: CGFloat) -> Font { .custom("Amiri-Bold", size: s) }
private func quranF(_ s: CGFloat) -> Font { .custom("AmiriQuran-Regular", size: s) }

/// the card for the lock screen: no background of its own
struct AccCard: ViewModifier {
    func body(content: Content) -> some View { content.containerBackground(for: .widget) { Color.clear } }
}

// MARK: - the widget's shape (long-press → «تعديل الأداة»)

enum DayStyle: String, AppEnum {
    case row, callig, frame
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "الشكل" }
    static var caseDisplayRepresentations: [DayStyle: DisplayRepresentation] { [.row: "صف المواقيت", .callig: "اليوم بالخط", .frame: "إطار المصحف"] }
}
struct DayIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "التاريخ ومواقيت الصلاة" }
    static var description: IntentDescription { IntentDescription("اختر شكل الأداة ولونها") }
    @Parameter(title: "الشكل", default: .row) var style: DayStyle
    @Parameter(title: "اللون") var color: ColorEntity?
    init() {}
}

// MARK: - «التاريخ ومواقيت الصلاة» (small · medium in three shapes · large · lock screen)

struct DayEntry: TimelineEntry { let date: Date; var pal = WPal.current; var style: DayStyle = .row }
struct DayProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: Date()) }
    func snapshot(for c: DayIntent, in context: Context) async -> DayEntry { DayEntry(date: Date(), pal: .of(c.color?.id), style: c.style) }
    func timeline(for c: DayIntent, in context: Context) async -> Timeline<DayEntry> {
        let now = Date(), pal = WPal.of(c.color?.id)
        let ds = PDay.dates(now)
        return Timeline(entries: ds.map { DayEntry(date: $0, pal: pal, style: c.style) }, policy: .after(ds.last.map { $0.addingTimeInterval(60) } ?? now.addingTimeInterval(3600)))
    }
}

struct DayWidgetView: View {
    let e: DayEntry
    @Environment(\.widgetFamily) private var fam
    var body: some View {
        Group {
            switch fam {
            case .systemSmall: DaySmall(e: e)
            case .systemLarge: DayLarge(e: e)
            case .accessoryRectangular: DayRect(e: e)
            case .accessoryInline: Text(rtl("\(Hj.full(e.date)) هـ"))
            default:
                switch e.style {
                case .row: PrayerRow(at: e.date, p: e.pal, hijri: true)
                case .callig: DayCallig(e: e)
                case .frame: DayFrame(e: e)
                }
            }
        }
        .modifier(DayBg(p: e.pal, acc: [.accessoryRectangular, .accessoryInline, .accessoryCircular].contains(fam)))
        .environment(\.layoutDirection, .rightToLeft)
        .widgetURL(URL(string: "badr://prayer"))
    }
}
/// the theme's card, or nothing on the lock screen
struct DayBg: ViewModifier {
    let p: WPal; let acc: Bool
    func body(content: Content) -> some View {
        if acc { content.modifier(AccCard()) } else { content.containerBackground(for: .widget) { p.bg } }
    }
}

/// medium: the next prayer, its countdown and the hijri date; the six times in a row, the next one in a box
struct PrayerRow: View {
    let at: Date; let p: WPal; var hijri = false
    var body: some View {
        let d = PDay(at)
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("الصلاة القادمة" + (d.place.isEmpty ? "" : " · \(d.place)")).font(plex(11)).foregroundStyle(p.muted).lineLimit(1)
                    Text(d.next?.name ?? "—").font(plex(24, .bold)).foregroundStyle(p.text)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(hijri ? Hj.full(at) : "متبقٍ").font(plex(11, .semibold)).foregroundStyle(p.gold).lineLimit(1)
                    if let n = d.next { Countdown(to: n.at, font: plex(24, .bold), color: p.text).multilineTextAlignment(.trailing) }
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                ForEach(d.today, id: \.key) { x in
                    let on = x.key == d.next?.key && x.at == d.next?.at
                    VStack(spacing: 2) {
                        Text(x.name).font(plex(10.5)).foregroundStyle(on ? p.text : p.muted).lineLimit(1).minimumScaleFactor(0.75)
                        Text(PDay.hm(x.at)).font(plex(13, .bold)).foregroundStyle(on ? p.gold : p.text).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(on ? p.surface : .clear))
                }
            }
            if d.empty { Text("افتح التطبيق مرة لتظهر المواقيت").font(plex(11)).foregroundStyle(p.muted) }
        }
    }
}

/// medium: the weekday in calligraphy with the dates, and the five prayers
struct DayCallig: View {
    let e: DayEntry
    var body: some View {
        let p = e.pal, d = PDay(e.date)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Hj.long(e.date)).font(amiri(30)).foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.6)
                Text("\(Hj.day(e.date)) \(Hj.month(e.date))").font(plex(13, .semibold)).foregroundStyle(p.gold)
                Text("\(Hj.year(e.date)) هـ · \(Hj.greg(e.date))").font(plex(10.5)).foregroundStyle(p.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(p.muted.opacity(0.3)).frame(width: 0.5)
            FiveList(d: d, p: p, timer: false).frame(maxWidth: .infinity)
        }
    }
}

/// the five prayers one under another; the next one in a box (with its countdown when asked)
struct FiveList: View {
    let d: PDay; let p: WPal; var timer = false
    var body: some View {
        VStack(spacing: 0) {
            ForEach(d.five, id: \.key) { x in
                let on = x.key == d.next?.key && x.at == d.next?.at
                HStack {
                    Text(x.name).font(plex(12, on ? .bold : .regular)).foregroundStyle(on ? p.gold : p.muted)
                    Spacer(minLength: 4)
                    if on && timer { Countdown(to: x.at, font: plex(12, .bold), color: p.text) }
                    else { Text(PDay.hm(x.at)).font(plex(12, on ? .bold : .regular)).foregroundStyle(on ? p.text : p.muted) }
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? p.surface : .clear))
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// medium: the Mushaf frame — a double gold border, the date on one side and the prayers on the other
struct DayFrame: View {
    let e: DayEntry
    var body: some View {
        let p = e.pal, d = PDay(e.date)
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(Hj.long(e.date)).font(amiri(21)).foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.6)
                Text("\(Hj.day(e.date))").font(plex(30, .bold)).foregroundStyle(p.gold)
                Text("\(Hj.month(e.date)) \(Hj.year(e.date))").font(plex(11.5, .semibold)).foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 3) {
                Rectangle().fill(p.gold.opacity(0.4)).frame(width: 0.6)
                Diamond().stroke(p.gold.opacity(0.75), lineWidth: 0.8).frame(width: 9, height: 9)
                Rectangle().fill(p.gold.opacity(0.4)).frame(width: 0.6)
            }
            FiveList(d: d, p: p, timer: true).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(p.gold.opacity(0.85), lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(p.gold.opacity(0.35), lineWidth: 0.6).padding(3))
        .padding(-6)
    }
}
struct Diamond: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.midY)); p.closeSubpath() } }
}

/// small: the day of the hijri month large, the weekday, and the next prayer's countdown
struct DaySmall: View {
    let e: DayEntry
    var body: some View {
        let p = e.pal, d = PDay(e.date)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Hj.weekday(e.date)).font(plex(11.5, .semibold)).foregroundStyle(p.gold)
                Spacer()
                Text(d.place).font(plex(10.5)).foregroundStyle(p.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(Hj.month(e.date)).font(plex(12.5)).foregroundStyle(p.text.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Hj.day(e.date))").font(plex(40, .bold)).foregroundStyle(p.text)
                Text("\(Hj.year(e.date))").font(plex(11)).foregroundStyle(p.muted)
            }
            Spacer(minLength: 0)
            Rectangle().fill(p.muted.opacity(0.3)).frame(height: 0.5).padding(.bottom, 6)
            HStack {
                Text(d.next?.name ?? "—").font(plex(11.5, .semibold)).foregroundStyle(p.text)
                Spacer(minLength: 2)
                if let n = d.next { Countdown(to: n.at, font: plex(12, .bold), color: p.gold) }
            }
        }
    }
}

/// large: the weekday in calligraphy, the next prayer in a band, the six times, the night and Ramadan
struct DayLarge: View {
    let e: DayEntry
    var body: some View {
        let p = e.pal, d = PDay(e.date)
        VStack(spacing: 12) {
            HStack(alignment: .bottom) {
                Text(Hj.long(e.date)).font(amiri(36)).foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Hj.day(e.date)) \(Hj.month(e.date)) \(Hj.year(e.date))").font(plex(11.5, .semibold)).foregroundStyle(p.gold)
                    Text(Hj.greg(e.date)).font(plex(11)).foregroundStyle(p.muted)
                }
            }
            if let n = d.next {
                HStack {
                    Text("\(n.name) \(PDay.hm(n.at)) \(PDay.ampm(n.at))").font(plex(15, .bold)).foregroundStyle(p.text)
                    Spacer()
                    Countdown(to: n.at, font: plex(16, .bold), color: p.gold)
                }
                .padding(.horizontal, 12).padding(.vertical, 9).background(RoundedRectangle(cornerRadius: 12).fill(p.surface))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(d.today, id: \.key) { x in
                    let on = x.key == d.next?.key && x.at == d.next?.at
                    VStack(spacing: 1) {
                        Text(x.name).font(plex(12, on ? .semibold : .regular)).foregroundStyle(on ? p.gold : p.muted)
                        Text(PDay.hm(x.at)).font(plex(18, .bold)).foregroundStyle(on ? p.gold : p.text)
                    }
                }
            }
            Spacer(minLength: 0)
            Rectangle().fill(p.muted.opacity(0.3)).frame(height: 0.5)
            HStack {
                if let n = d.night {
                    Stat(t: "منتصف الليل", v: PDay.hm(n.mid), p: p); Spacer()
                    Stat(t: "الثلث الأخير", v: PDay.hm(n.third), p: p); Spacer()
                }
                Stat(t: seasonTitle(e.date), v: seasonValue(e.date), p: p)
            }
        }
    }
}
private struct Stat: View {
    let t: String, v: String, p: WPal
    var body: some View { VStack(spacing: 1) { Text(t).font(plex(10.5)).foregroundStyle(p.muted); Text(v).font(plex(14, .bold)).foregroundStyle(p.text) } }
}
func seasonTitle(_ d: Date) -> String { switch Hj.season(d) { case .before: return "رمضان بعد"; case .ramadan: return "رمضان"; case .eid: return "عيد الفطر" } }
func seasonValue(_ d: Date) -> String { switch Hj.season(d) { case .before(let n, _): return Hj.daysText(n); case .ramadan(let n): return "اليوم \(n)"; case .eid: return "مبارك" } }

/// lock screen: the weekday and the hijri date, then Ramadan
struct DayRect: View {
    let e: DayEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(rtl("\(Hj.weekday(e.date)) · \(Hj.day(e.date)) \(Hj.month(e.date))")).font(amiri(17)).lineLimit(1).minimumScaleFactor(0.7)
            Text(rtl("\(Hj.year(e.date)) هـ · \(Hj.greg(e.date))")).font(plex(12)).opacity(0.75)
            Text(rtl("\(seasonTitle(e.date)) \(seasonValue(e.date))")).font(plex(12, .semibold)).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "day", intent: DayIntent.self, provider: DayProvider()) { DayWidgetView(e: $0) }
            .configurationDisplayName("التاريخ ومواقيت الصلاة").description("التاريخ الهجري ومواقيت الصلاة والعدّ التنازلي — صغير ومتوسط وكبير، وعلى شاشة القفل")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

/// «اليوم بالخط» and «إطار المصحف» as widgets of their own, so they show in the widget gallery as they are
struct DayStyleProvider: AppIntentTimelineProvider {
    let style: DayStyle
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: Date(), style: style) }
    func snapshot(for c: ColorIntent, in context: Context) async -> DayEntry { DayEntry(date: Date(), pal: .of(c.color?.id), style: style) }
    func timeline(for c: ColorIntent, in context: Context) async -> Timeline<DayEntry> {
        let now = Date(), pal = WPal.of(c.color?.id), ds = PDay.dates(now)
        return Timeline(entries: ds.map { DayEntry(date: $0, pal: pal, style: style) }, policy: .after(ds.last.map { $0.addingTimeInterval(60) } ?? now.addingTimeInterval(3600)))
    }
}
struct DayCalligWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "dayCallig", intent: ColorIntent.self, provider: DayStyleProvider(style: .callig)) { DayWidgetView(e: $0) }
            .configurationDisplayName("اليوم بالخط ومواقيت الصلاة").description("اسم اليوم بالخط مع التاريخ الهجري، ومواقيت الصلاة")
            .supportedFamilies([.systemMedium])
    }
}
struct DayFrameWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "dayFrame", intent: ColorIntent.self, provider: DayStyleProvider(style: .frame)) { DayWidgetView(e: $0) }
            .configurationDisplayName("إطار المصحف").description("التاريخ الهجري في إطار مزدوج، ومواقيت الصلاة والعدّ التنازلي")
            .supportedFamilies([.systemMedium])
    }
}

// MARK: - «مواقيت الصلاة» (the first widget, kept by its kind): new shapes and the lock screen

struct PrayerEntry: TimelineEntry { let date: Date; var pal = WPal.current }
struct PrayerProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry { PrayerEntry(date: Date()) }
    func snapshot(for c: ColorIntent, in context: Context) async -> PrayerEntry { PrayerEntry(date: Date(), pal: .of(c.color?.id)) }
    func timeline(for c: ColorIntent, in context: Context) async -> Timeline<PrayerEntry> {
        let now = Date(), pal = WPal.of(c.color?.id), ds = PDay.dates(now)
        return Timeline(entries: ds.map { PrayerEntry(date: $0, pal: pal) }, policy: .after(ds.last.map { $0.addingTimeInterval(60) } ?? now.addingTimeInterval(3600)))
    }
}
struct PrayerWidgetView: View {
    let e: PrayerEntry
    @Environment(\.widgetFamily) private var fam
    var body: some View {
        let d = PDay(e.date), p = e.pal
        Group {
            switch fam {
            case .systemSmall: NextSmall(d: d, p: p)
            case .accessoryRectangular:
                // like the lock screen's own: «العصر ٢:٣٧ م» and the time left under it
                VStack(alignment: .leading, spacing: 0) {
                    if let n = d.next {
                        Text(rtl("\(n.name) \(PDay.hm(n.at)) \(PDay.ampm(n.at))")).font(plex(17, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        Countdown(to: n.at, font: plex(16, .semibold), color: .primary).opacity(0.75)
                    } else { Text("مواقيت الصلاة").font(plex(15, .bold)) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryCircular:
                if let n = d.next, let pr = d.prev {
                    ProgressView(timerInterval: Date(timeIntervalSince1970: pr.at)...Date(timeIntervalSince1970: n.at), countsDown: false) { Text(n.name) } currentValueLabel: {
                        VStack(spacing: -2) { Text(n.name).font(plex(9.5, .semibold)); Text(PDay.hm(n.at)).font(plex(12, .bold)) }
                    }.progressViewStyle(.circular)
                } else { Image(systemName: "moon.stars") }
            case .accessoryInline:
                if let n = d.next { Text(rtl("\(n.name) \(PDay.hm(n.at)) \(PDay.ampm(n.at))")) } else { Text("مواقيت الصلاة") }
            default: PrayerRow(at: e.date, p: p, hijri: true)
            }
        }
        .modifier(DayBg(p: p, acc: [.accessoryRectangular, .accessoryInline, .accessoryCircular].contains(fam)))
        .environment(\.layoutDirection, .rightToLeft)
        .widgetURL(URL(string: "badr://prayer"))
    }
}
/// small: the next prayer in the middle, its countdown, and the iqama
struct NextSmall: View {
    let d: PDay; let p: WPal
    var body: some View {
        VStack(spacing: 2) {
            Text("الصلاة القادمة").font(plex(11)).foregroundStyle(p.muted)
            Spacer(minLength: 0)
            Text(d.next?.name ?? "—").font(amiri(28)).foregroundStyle(p.text)
            if let n = d.next { Countdown(to: n.at, font: plex(22, .bold), color: p.gold).multilineTextAlignment(.center) }
            Spacer(minLength: 0)
            if let n = d.next {
                Text(n.iq.map { "الإقامة \(PDay.hm($0))" } ?? "\(PDay.hm(n.at)) \(PDay.ampm(n.at))").font(plex(11)).foregroundStyle(p.muted)
            }
        }.frame(maxWidth: .infinity)
    }
}
struct PrayerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "prayer", intent: ColorIntent.self, provider: PrayerProvider()) { PrayerWidgetView(e: $0) }
            .configurationDisplayName("الصلاة القادمة").description("الصلاة القادمة والعدّ التنازلي — وعلى شاشة القفل")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - «رمضان»

struct RamadanEntry: TimelineEntry { let date: Date; var pal = WPal.current }
struct RamadanProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RamadanEntry { RamadanEntry(date: Date()) }
    func snapshot(for c: ColorIntent, in context: Context) async -> RamadanEntry { RamadanEntry(date: Date(), pal: .of(c.color?.id)) }
    func timeline(for c: ColorIntent, in context: Context) async -> Timeline<RamadanEntry> {
        let now = Date(), pal = WPal.of(c.color?.id), ds = PDay.dates(now)
        return Timeline(entries: ds.map { RamadanEntry(date: $0, pal: pal) }, policy: .after(ds.last.map { $0.addingTimeInterval(60) } ?? now.addingTimeInterval(3600)))
    }
}
struct RamadanView: View {
    let e: RamadanEntry
    @Environment(\.widgetFamily) private var fam
    var body: some View {
        let p = e.pal, s = Hj.season(e.date), d = PDay(e.date)
        let maghrib = d.today.first { $0.key == "maghrib" && $0.at > e.date.timeIntervalSince1970 }
        Group {
            switch fam {
            case .accessoryCircular:
                switch s {
                case .before(let n, let f): Gauge(value: f) { Image(systemName: "moon.stars.fill") } currentValueLabel: { Text(String(n)).font(plex(15, .bold)) }.gaugeStyle(.accessoryCircular)
                case .ramadan(let n): Gauge(value: Double(n) / 30) { Text("رمضان") } currentValueLabel: { Text(String(n)).font(plex(15, .bold)) }.gaugeStyle(.accessoryCircular)
                case .eid: ZStack { AccessoryWidgetBackground(); Text("عيد").font(ruqaa(18)) }
                }
            case .accessoryRectangular:
                HStack(spacing: 10) {
                    Text("رمضان").font(ruqaa(26)).lineLimit(1).fixedSize()
                    VStack(alignment: .leading, spacing: 0) {
                        switch s {
                        case .before(let n, _): Text(rtl("بعد \(Hj.daysText(n))")).font(plex(14, .bold)); Text(rtl(Hj.gregFull(Hj.ramadanStart(e.date)))).font(plex(11)).opacity(0.75)
                        case .ramadan(let n):
                            Text(rtl("اليوم \(n)")).font(plex(14, .bold))
                            if let m = maghrib { HStack(spacing: 4) { Text("الإفطار").font(plex(11)); Countdown(to: m.at, font: plex(12, .bold), color: .primary) } }
                        case .eid: Text("عيد مبارك").font(plex(14, .bold)); Text("تقبّل الله منا ومنكم").font(plex(11))
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryInline:
                switch s {
                case .before(let n, _): Text(rtl("رمضان بعد \(Hj.daysText(n))"))
                case .ramadan(let n): Text(rtl("اليوم \(n) من رمضان"))
                case .eid: Text("عيد مبارك")
                }
            case .systemMedium: RamadanMedium(s: s, p: p, maghrib: maghrib, at: e.date)
            default: RamadanSmall(s: s, p: p, maghrib: maghrib, at: e.date)
            }
        }
        .modifier(RamadanBg(p: p, acc: [.accessoryRectangular, .accessoryInline, .accessoryCircular].contains(fam)))
        .environment(\.layoutDirection, .rightToLeft)
        .widgetURL(URL(string: "badr://prayer"))
    }
}
/// «رمضان» in Ruqaa calligraphy
func ruqaa(_ s: CGFloat) -> Font { .custom("ArefRuqaa-Bold", size: s) }
/// the widget's colour with a soft moonlight in one corner and a few stars
struct RamadanBg: ViewModifier {
    let p: WPal; let acc: Bool
    func body(content: Content) -> some View {
        if acc { content.modifier(AccCard()) } else {
            content.containerBackground(for: .widget) {
                ZStack {
                    p.bg
                    RadialGradient(colors: [p.gold.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 220)
                    GeometryReader { g in
                        ForEach(0..<9, id: \.self) { i in
                            let x = [0.1, 0.24, 0.86, 0.93, 0.06, 0.95, 0.04, 0.15, 0.8][i], y = [0.12, 0.06, 0.08, 0.22, 0.32, 0.45, 0.6, 0.2, 0.18][i]
                            Circle().fill(p.gold.opacity(i % 3 == 0 ? 0.55 : 0.3)).frame(width: i % 3 == 0 ? 2.6 : 1.8).position(x: g.size.width * x, y: g.size.height * y)
                        }
                    }
                }
            }
        }
    }
}
/// a thin bar that fills as Ramadan comes (as its days pass, in Ramadan)
private struct RamadanBar: View {
    let frac: Double; let p: WPal
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(p.text.opacity(0.12))
                Capsule().fill(LinearGradient(colors: [p.gold.opacity(0.65), p.gold], startPoint: .leading, endPoint: .trailing)).frame(width: max(5, g.size.width * frac))
            }
        }.frame(height: 5)
    }
}
private func ramFrac(_ s: Hj.Season) -> Double { switch s { case .before(_, let f): return f; case .ramadan(let n): return Double(n) / 30; case .eid: return 1 } }
/// «يومًا» after a number (the number is drawn on its own)
private func dayWord(_ n: Int) -> String { n == 1 ? "يوم" : n == 2 ? "يومان" : (3...10).contains(n) ? "أيام" : "يومًا" }

/// small: «رمضان» in Ruqaa, the days left large, the bar, and the date it begins
struct RamadanSmall: View {
    let s: Hj.Season; let p: WPal; let maghrib: Shared.Prayer?; let at: Date
    var body: some View {
        VStack(spacing: 0) {
            Text(caseTitle).font(ruqaa(34)).foregroundStyle(p.gold).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            switch s {
            case .before(let n, _):
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(n)).font(plex(34, .bold)).foregroundStyle(p.text)
                    Text(dayWord(n)).font(plex(13, .semibold)).foregroundStyle(p.muted)
                }.environment(\.layoutDirection, .rightToLeft)
            case .ramadan(let n):
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("اليوم").font(plex(13, .semibold)).foregroundStyle(p.muted)
                    Text(String(n)).font(plex(34, .bold)).foregroundStyle(p.text)
                }
            case .eid: Text("عيد مبارك").font(plex(18, .bold)).foregroundStyle(p.text)
            }
            Spacer(minLength: 0)
            RamadanBar(frac: ramFrac(s), p: p).padding(.bottom, 7)
            footer.font(plex(10)).foregroundStyle(p.muted).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
    private var caseTitle: String { if case .eid = s { return "عيد الفطر" }; return "رمضان" }
    @ViewBuilder private var footer: some View {
        switch s {
        case .before: Text(rtl(Hj.gregFull(Hj.ramadanStart(at))))
        case .ramadan:
            if let m = maghrib { HStack(spacing: 4) { Text("الإفطار"); Countdown(to: m.at, font: plex(10.5, .bold), color: p.gold) } }
            else { Text("رمضان كريم") }
        case .eid: Text("تقبّل الله منا ومنكم")
        }
    }
}
/// medium: the calligraphy on one side; the days left, the date it begins (hijri and gregorian) and the bar on the other
struct RamadanMedium: View {
    let s: Hj.Season; let p: WPal; let maghrib: Shared.Prayer?; let at: Date
    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(isEid ? "عيد الفطر" : "رمضان").font(ruqaa(48)).foregroundStyle(p.gold).lineLimit(1).minimumScaleFactor(0.6)
                Text(isEid ? "تقبّل الله منا ومنكم" : "شهر القرآن").font(plex(11)).foregroundStyle(p.muted)
            }.frame(maxWidth: .infinity)
            Rectangle().fill(p.gold.opacity(0.25)).frame(width: 1).padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 4) {
                switch s {
                case .before(let n, _):
                    Text("المتبقي").font(plex(11)).foregroundStyle(p.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(String(n)).font(plex(36, .bold)).foregroundStyle(p.text)
                        Text(dayWord(n)).font(plex(14, .semibold)).foregroundStyle(p.muted)
                    }
                    Text(rtl("1 رمضان \(Hj.year(Hj.ramadanStart(at))) هـ · \(Hj.gregFull(Hj.ramadanStart(at)))")).font(plex(10.5)).foregroundStyle(p.muted).lineLimit(1).minimumScaleFactor(0.7)
                case .ramadan(let n):
                    Text("رمضان كريم").font(plex(11)).foregroundStyle(p.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("اليوم").font(plex(14, .semibold)).foregroundStyle(p.muted)
                        Text(String(n)).font(plex(36, .bold)).foregroundStyle(p.text)
                    }
                    if let m = maghrib { HStack(spacing: 4) { Text("الإفطار").font(plex(11)).foregroundStyle(p.muted); Countdown(to: m.at, font: plex(12, .bold), color: p.gold) } }
                case .eid(let n):
                    Text("عيد مبارك").font(plex(20, .bold)).foregroundStyle(p.text)
                    Text(rtl("اليوم \(n) من شوال")).font(plex(11)).foregroundStyle(p.muted)
                }
                RamadanBar(frac: ramFrac(s), p: p).padding(.top, 4)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var isEid: Bool { if case .eid = s { return true }; return false }
}
struct RamadanWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ramadan", intent: ColorIntent.self, provider: RamadanProvider()) { RamadanView(e: $0) }
            .configurationDisplayName("رمضان").description("كم يومًا بقي على رمضان، وفي رمضان: اليوم والوقت المتبقي للإفطار")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - «عدّاد التسبيح» (tap the widget itself)

enum Tasbih {
    static let seq: [(String, Int)] = [("سبحان الله", 33), ("الحمد لله", 33), ("الله أكبر", 34)]
    static var n: Int { Shared.d.integer(forKey: "w_tb_n") }
    static var i: Int { Shared.d.integer(forKey: "w_tb_i") % seq.count }
    static var total: Int { Shared.d.string(forKey: "w_tb_day") == today ? Shared.d.integer(forKey: "w_tb_total") : 0 }
    static var today: String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }
    static func tap() {
        var n = n + 1, i = i
        if n >= seq[i].1 { n = 0; i = (i + 1) % seq.count }
        let t = total + 1
        Shared.d.set(n, forKey: "w_tb_n"); Shared.d.set(i, forKey: "w_tb_i"); Shared.d.set(t, forKey: "w_tb_total"); Shared.d.set(today, forKey: "w_tb_day")
    }
    static func reset() { Shared.d.set(0, forKey: "w_tb_n"); Shared.d.set(0, forKey: "w_tb_i") }
}
struct TasbihTap: AppIntent {
    static var title: LocalizedStringResource { "تسبيحة" }
    func perform() async throws -> some IntentResult { Tasbih.tap(); return .result() }
}
struct TasbihReset: AppIntent {
    static var title: LocalizedStringResource { "من البداية" }
    func perform() async throws -> some IntentResult { Tasbih.reset(); return .result() }
}
struct TasbihEntry: TimelineEntry { let date: Date; var pal = WPal.current }
struct TasbihProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TasbihEntry { TasbihEntry(date: Date()) }
    func snapshot(for c: ColorIntent, in context: Context) async -> TasbihEntry { TasbihEntry(date: Date(), pal: .of(c.color?.id)) }
    func timeline(for c: ColorIntent, in context: Context) async -> Timeline<TasbihEntry> { Timeline(entries: [TasbihEntry(date: Date(), pal: .of(c.color?.id))], policy: .never) }
}
struct TasbihView: View {
    let e: TasbihEntry
    var body: some View {
        let p = e.pal, (word, of) = Tasbih.seq[Tasbih.i], n = Tasbih.n
        ZStack(alignment: .topLeading) {
            Button(intent: TasbihTap()) {
                VStack(spacing: 2) {
                    Text(word).font(amiri(19)).foregroundStyle(p.gold).lineLimit(1).minimumScaleFactor(0.7)
                    ZStack {
                        Circle().stroke(p.surface, lineWidth: 4)
                        Circle().trim(from: 0, to: Double(n) / Double(of)).stroke(p.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("\(n)").font(plex(30, .bold)).foregroundStyle(p.text).contentTransition(.numericText())
                    }.padding(.horizontal, 22)
                    Text("من \(of) · اليوم \(Tasbih.total)").font(plex(10.5)).foregroundStyle(p.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain)
            Button(intent: TasbihReset()) { Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.muted).frame(width: 26, height: 26).background(Circle().fill(p.surface)) }.buttonStyle(.plain)
        }
        .containerBackground(for: .widget) { p.bg }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
struct TasbihWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "tasbih", intent: ColorIntent.self, provider: TasbihProvider()) { TasbihView(e: $0) }
            .configurationDisplayName("عدّاد التسبيح").description("المس الأداة لتسبّح: سبحان الله، الحمد لله، الله أكبر")
            .supportedFamilies([.systemSmall])
    }
}

// MARK: - «عبادات اليوم» (tick each one from the widget)

enum Ibada {
    static let five: [(String, String, String)] = [("fajr", "الفجر", "sunrise"), ("dhuhr", "الظهر", "sun.max"), ("asr", "العصر", "sun.min"), ("maghrib", "المغرب", "sunset"), ("isha", "العشاء", "moon")]
    static let more: [(String, String, String)] = [("am", "أذكار الصباح", "sun.horizon"), ("pm", "أذكار المساء", "moon.haze"), ("wird", "الورد", "book")]
    static let large: [(String, String, String)] = [("duha", "الضحى", "sun.and.horizon"), ("sunnah", "السنن", "plus.circle"), ("witr", "الوتر", "moon.stars"), ("qiyam", "قيام الليل", "sparkles")]
    static var key: String { "w_ib_" + Tasbih.today }
    static var done: Set<String> { Set(Shared.d.stringArray(forKey: key) ?? []) }
    static func toggle(_ id: String) { var s = done; if s.contains(id) { s.remove(id) } else { s.insert(id) }; Shared.d.set(Array(s), forKey: key) }
}
struct IbadaToggle: AppIntent {
    static var title: LocalizedStringResource { "عبادة" }
    @Parameter(title: "العبادة") var id: String
    init() {}
    init(_ id: String) { self.id = id }
    func perform() async throws -> some IntentResult { Ibada.toggle(id); return .result() }
}
struct IbadaEntry: TimelineEntry { let date: Date; var pal = WPal.current }
struct IbadaProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> IbadaEntry { IbadaEntry(date: Date()) }
    func snapshot(for c: ColorIntent, in context: Context) async -> IbadaEntry { IbadaEntry(date: Date(), pal: .of(c.color?.id)) }
    func timeline(for c: ColorIntent, in context: Context) async -> Timeline<IbadaEntry> {
        let cal = Calendar.current, now = Date(), mid = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        return Timeline(entries: [IbadaEntry(date: now, pal: .of(c.color?.id)), IbadaEntry(date: mid, pal: .of(c.color?.id))], policy: .after(mid.addingTimeInterval(60)))
    }
}
struct IbadaView: View {
    let e: IbadaEntry
    @Environment(\.widgetFamily) private var fam
    var body: some View {
        let p = e.pal, done = Ibada.done
        let items = Ibada.five + Ibada.more + (fam == .systemLarge ? Ibada.large : [])
        VStack(spacing: 8) {
            HStack {
                Text("عبادات اليوم").font(plex(13, .bold)).foregroundStyle(p.text)
                Spacer()
                Text("\(items.filter { done.contains($0.0) }.count) / \(items.count)").font(plex(12, .bold)).foregroundStyle(p.gold)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(items, id: \.0) { it in
                    let on = done.contains(it.0)
                    Button(intent: IbadaToggle(it.0)) {
                        VStack(spacing: 3) {
                            Image(systemName: on ? "checkmark" : it.2).font(.system(size: 13, weight: .semibold)).foregroundStyle(on ? p.onGold : p.gold)
                            Text(it.1).font(plex(9.5, .semibold)).foregroundStyle(on ? p.onGold : p.text).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: fam == .systemLarge ? 62 : 44)
                        .background(RoundedRectangle(cornerRadius: 11).fill(on ? p.gold : p.surface))
                    }.buttonStyle(.plain)
                }
            }
            if fam == .systemLarge { Spacer(minLength: 0) }
        }
        .containerBackground(for: .widget) { p.bg }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
struct IbadaWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ibadat", intent: ColorIntent.self, provider: IbadaProvider()) { IbadaView(e: $0) }
            .configurationDisplayName("عبادات اليوم").description("علّم على صلواتك وأذكارك ووردك من الأداة نفسها — تبدأ من جديد كل يوم")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - «الوضوء»

struct WuduToggle: AppIntent {
    static var title: LocalizedStringResource { "الوضوء" }
    func perform() async throws -> some IntentResult {
        Shared.d.set(Shared.d.double(forKey: "w_wudu") > 0 ? 0 : Date().timeIntervalSince1970, forKey: "w_wudu"); return .result()
    }
}
struct WuduView: View {
    let e: IbadaEntry
    var body: some View {
        let p = e.pal, since = Shared.d.double(forKey: "w_wudu")
        Button(intent: WuduToggle()) {
            VStack(spacing: 5) {
                Image(systemName: since > 0 ? "drop.fill" : "hand.raised").font(.system(size: 24)).foregroundStyle(p.gold)
                Text(since > 0 ? "على وضوء" : "لستَ على وضوء").font(plex(15, .bold)).foregroundStyle(p.text)
                if since > 0 { Text("منذ \(PDay.hm(since)) \(PDay.ampm(since))").font(plex(11)).foregroundStyle(p.muted) }
                else { Text("\(Hj.weekday(e.date)) · \(PDay.hm(e.date.timeIntervalSince1970))").font(plex(11)).foregroundStyle(p.muted) }
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.text).frame(width: 30, height: 30).background(Circle().fill(p.surface)).padding(.top, 2)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) { p.bg }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
struct WuduProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> IbadaEntry { IbadaEntry(date: Date()) }
    func snapshot(for c: ColorIntent, in context: Context) async -> IbadaEntry { IbadaEntry(date: Date(), pal: .of(c.color?.id)) }
    func timeline(for c: ColorIntent, in context: Context) async -> Timeline<IbadaEntry> { Timeline(entries: [IbadaEntry(date: Date(), pal: .of(c.color?.id))], policy: .after(Date().addingTimeInterval(1800))) }
}
struct WuduWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "wudu", intent: ColorIntent.self, provider: WuduProvider()) { WuduView(e: $0) }
            .configurationDisplayName("متابعة الوضوء").description("المس الأداة عند الوضوء، ومرة أخرى إذا انتقض")
            .supportedFamilies([.systemSmall])
    }
}

// MARK: - «الورد اليومي»

struct WirdView: View {
    let e: IbadaEntry
    @Environment(\.widgetFamily) private var fam
    var body: some View {
        let p = e.pal, w = Shared.read("w_wird", Shared.Wird.self)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("وردك اليوم").font(plex(12, .bold)).foregroundStyle(p.gold)
                Spacer()
                if w?.done == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(p.gold) }
            }
            if let w, w.on {
                Spacer(minLength: 0)
                Text(w.from == w.to ? "صفحة \(w.from)" : "صفحة \(w.from) – \(w.to)").font(plex(fam == .systemSmall ? 19 : 22, .bold)).foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.7)
                Text("سورة \(w.surah)").font(amiri(16)).foregroundStyle(p.text.opacity(0.85))
                Spacer(minLength: 0)
                ProgressView(value: Double(w.percent), total: 100).tint(p.gold)
                HStack {
                    Text("الختمة \(w.percent)٪").font(plex(10.5)).foregroundStyle(p.muted)
                    Spacer()
                    if w.khatmas > 0 { Text("الختمات \(w.khatmas)").font(plex(10.5)).foregroundStyle(p.muted) }
                }
            } else {
                Spacer(minLength: 0)
                Text("ابدأ وردك اليومي").font(amiri(19)).foregroundStyle(p.text)
                Text("المس لتختار مقدار الورد وموعد التذكير").font(plex(10.5)).foregroundStyle(p.muted)
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) { p.bg }
        .environment(\.layoutDirection, .rightToLeft)
        .widgetURL(URL(string: "badr://wird"))
    }
}
struct WirdWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "wird", intent: ColorIntent.self, provider: WuduProvider()) { WirdView(e: $0) }
            .configurationDisplayName("الورد اليومي").description("ورد اليوم من المصحف ونسبة الختمة")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// a bundle holds ten at most: the rest in this one
struct MoreWidgets: WidgetBundle {
    var body: some Widget { TasbihWidget(); IbadaWidget(); WuduWidget(); WirdWidget() }
}
