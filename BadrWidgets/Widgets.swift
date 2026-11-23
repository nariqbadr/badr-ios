import WidgetKit
import SwiftUI
import AppIntents

/// What the app shares with its widgets (App Group): the prayer times ahead, the ayahs of the coming days, what is playing, the theme.
enum Shared {
    static let group = "group.com.bawazirquran.app"
    static var d: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
    struct Prayer: Codable { let key: String; let name: String; let at: Double; var iq: Double? = nil }
    struct Wird: Codable { let on: Bool; let from: Int; let to: Int; let surah: String; let percent: Int; let khatmas: Int; let done: Bool }
    struct Ayah: Codable { let day: String; let s: Int; let a: Int; let surah: String; let text: String }
    struct Now: Codable { let title: String; let sub: String; let playing: Bool; let art: String }
    struct Pal: Codable { let bg: String, surface: String, text: String, muted: String, gold: String, onGold: String; let dark: Bool }
    /// every palette of the app, by name, so each widget can have its own
    struct PalOpt: Codable { let key: String; let name: String; let pal: Pal }
    /// the recitations to choose from in the player widget
    struct TrackOpt: Codable { let id: String; let title: String; let sub: String }
    static func read<T: Decodable>(_ k: String, _ t: T.Type) -> T? { d.data(forKey: k).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
}

// MARK: colours (the app's theme, or the site's «ليلي زمردي»)
struct WPal {
    let bg, surface, text, muted, gold, onGold: Color; let dark: Bool
    static var current: WPal { of(nil) }
    /// the colour chosen for this widget, or the app's own theme (the default)
    static func of(_ key: String?) -> WPal {
        let p = key.flatMap { k in k == "app" ? nil : (Shared.read("w_pals", [Shared.PalOpt].self) ?? []).first { $0.key == k }?.pal } ?? Shared.read("w_pal", Shared.Pal.self)
        func c(_ h: String?, _ def: UInt32) -> Color { Color(hex: h.flatMap { UInt32($0, radix: 16) } ?? def) }
        return WPal(bg: c(p?.bg, 0xFF0C1715), surface: c(p?.surface, 0xFF13241F), text: c(p?.text, 0xFFECE4D2), muted: c(p?.muted, 0xFFA3ADA6), gold: c(p?.gold, 0xFFC9A45C), onGold: c(p?.onGold, 0xFF14201D), dark: p?.dark ?? true)
    }
}
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: Double((hex >> 24) & 0xFF) / 255) }
}
extension Int { var ar: String { String(String(self).map { c -> Character in if let d = c.wholeNumberValue { return Character(UnicodeScalar(0x0660 + d)!) }; return c }) } }
func plex(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .custom(w == .bold ? "IBMPlexSansArabic-Bold" : w == .semibold ? "IBMPlexSansArabic-SemiBold" : "IBMPlexSansArabic-Regular", size: s) }

/// The card behind every widget: the theme's ink with a soft gold glow in the corner.
struct WCard: ViewModifier {
    let p: WPal
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { ZStack { p.bg; RadialGradient(colors: [p.gold.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 260) } }
        } else {
            content.padding().background(ZStack { p.bg; RadialGradient(colors: [p.gold.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 260) })
        }
    }
}

// MARK: - the widget's settings (long-press → «تعديل الأداة»): its colour, and for the player the recitation

struct ColorEntity: AppEntity {
    let id: String; let name: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "اللون" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery: ColorQuery { ColorQuery() }
}
struct ColorQuery: EntityQuery {
    static func all() -> [ColorEntity] { [ColorEntity(id: "app", name: "لون التطبيق")] + (Shared.read("w_pals", [Shared.PalOpt].self) ?? []).map { ColorEntity(id: $0.key, name: $0.name) } }
    func entities(for identifiers: [String]) async throws -> [ColorEntity] { Self.all().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [ColorEntity] { Self.all() }
    func defaultResult() async -> ColorEntity? { Self.all().first }
}
struct TrackEntity: AppEntity {
    let id: String; let title: String; let sub: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "التلاوة" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(sub)") }
    static var defaultQuery: TrackQuery { TrackQuery() }
}
struct TrackQuery: EntityStringQuery {
    static let now = TrackEntity(id: "now", title: "التلاوة الحالية", sub: "ما يعمل الآن في التطبيق")
    static func all() -> [TrackEntity] { [now] + (Shared.read("w_tracks", [Shared.TrackOpt].self) ?? []).map { TrackEntity(id: $0.id, title: $0.title, sub: $0.sub) } }
    func entities(for identifiers: [String]) async throws -> [TrackEntity] { Self.all().filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [TrackEntity] {
        let q = string.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? Self.all() : Self.all().filter { $0.title.localizedCaseInsensitiveContains(q) || $0.sub.localizedCaseInsensitiveContains(q) }
    }
    func suggestedEntities() async throws -> [TrackEntity] { Self.all() }
    func defaultResult() async -> TrackEntity? { Self.now }
}
struct ColorIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "لون الأداة" }
    static var description: IntentDescription { IntentDescription("اختر لون الأداة، أو اتركها بلون التطبيق") }
    @Parameter(title: "اللون") var color: ColorEntity?
    init() {}
}
struct PlayerIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "المشغّل" }
    static var description: IntentDescription { IntentDescription("اختر التلاوة التي تظهر في الأداة ولونها") }
    @Parameter(title: "التلاوة") var track: TrackEntity?
    @Parameter(title: "اللون") var color: ColorEntity?
    init() {}
}

// MARK: - آية اليوم

struct AyahEntry: TimelineEntry { let date: Date; let ayah: Shared.Ayah?; var pal = WPal.current; var short: Shared.Ayah? = nil }
struct AyahProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AyahEntry { AyahEntry(date: Date(), ayah: Shared.Ayah(day: "", s: 94, a: 5, surah: "الشرح", text: "فَإِنَّ مَعَ ٱلۡعُسۡرِ يُسۡرًا")) }
    func snapshot(for c: ColorIntent, in context: Context) async -> AyahEntry { entry(Date(), .of(c.color?.id)) }
    func timeline(for c: ColorIntent, in context: Context) async -> Timeline<AyahEntry> {
        let cal = Calendar.current, now = Date(), pal = WPal.of(c.color?.id)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: now)) }
        return Timeline(entries: [entry(now, pal)] + days.dropFirst().map { entry($0, pal) }, policy: .after(days.last ?? now.addingTimeInterval(86400)))
    }
    private func entry(_ at: Date, _ pal: WPal) -> AyahEntry {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let l = Shared.read("w_ayahs", [Shared.Ayah].self) ?? []
        let sh = Shared.read("w_short", [Shared.Ayah].self) ?? []
        return AyahEntry(date: at, ayah: l.first { $0.day == f.string(from: at) } ?? l.last, pal: pal, short: sh.first { $0.day == f.string(from: at) } ?? sh.last)
    }
}
/// the ayah between its ornate brackets, set right to left (without the embedding the brackets came out facing outwards)
func ayahLine(_ t: String) -> String { "\u{202B}\u{FD3F}\(t)\u{FD3E}\u{202C}" }

struct AyahWidgetView: View {
    let e: AyahEntry
    @Environment(\.widgetFamily) private var fam
    var body: some View {
        if fam == .accessoryRectangular || fam == .accessoryInline { lock } else { home }
    }
    /// lock screen: «﴿ سَلَٰمٞ قَوۡلٗا مِّن رَّبّٖ رَّحِيمٖ ﴾»
    private var lock: some View {
        let a = e.short ?? e.ayah
        return Group {
            if fam == .accessoryInline { Text(a.map { ayahLine($0.text) } ?? "آية اليوم") }
            else {
                Text(ayahLine(a?.text ?? "فَإِنَّ مَعَ ٱلۡعُسۡرِ يُسۡرًا")).font(.custom("AmiriQuran-Regular", size: 17)).multilineTextAlignment(.center)
                    .lineLimit(3).minimumScaleFactor(0.5).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .environment(\.layoutDirection, .rightToLeft)
        .widgetURL(URL(string: a.map { "badr://ayah/\($0.s)/\($0.a)" } ?? "badr://home"))
    }
    private var home: some View {
        let p = e.pal
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("آية اليوم").font(plex(11.5, .semibold)).foregroundStyle(p.gold)
                Spacer()
                if let a = e.ayah { Text("\(a.surah) · \(a.a.ar)").font(plex(11)).foregroundStyle(p.muted) }
            }
            Spacer(minLength: 0)
            Text(e.ayah.map { ayahLine($0.text) } ?? "افتح التطبيق مرة لتظهر آية اليوم").font(.custom("AmiriQuran-Regular", size: 22)).foregroundStyle(p.text)
                .multilineTextAlignment(.center).lineSpacing(6).minimumScaleFactor(0.45).frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .modifier(WCard(p: p))
        .environment(\.layoutDirection, .rightToLeft)
        .widgetURL(URL(string: e.ayah.map { "badr://ayah/\($0.s)/\($0.a)" } ?? "badr://home"))
    }
}
struct AyahWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ayah", intent: ColorIntent.self, provider: AyahProvider()) { AyahWidgetView(e: $0) }
            .configurationDisplayName("آية اليوم").description("آية تتغير كل يوم، والمس لتسمعها في التطبيق")
            .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - المشغّل

struct NowEntry: TimelineEntry { let date: Date; let now: Shared.Now?; var pal = WPal.current; var id: String? = nil }
struct NowProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NowEntry { NowEntry(date: Date(), now: Shared.Now(title: "تلاوة من سورة الكهف", sub: "الشيخ خالد بن سالم باوزير", playing: true, art: "")) }
    func snapshot(for c: PlayerIntent, in context: Context) async -> NowEntry { entry(c) }
    func timeline(for c: PlayerIntent, in context: Context) async -> Timeline<NowEntry> { Timeline(entries: [entry(c)], policy: .never) }
    /// the recitation chosen for this widget, or what is playing in the app (the default)
    private func entry(_ c: PlayerIntent) -> NowEntry {
        let pal = WPal.of(c.color?.id)
        if let t = c.track, t.id != "now" { return NowEntry(date: Date(), now: Shared.Now(title: t.title, sub: t.sub, playing: false, art: ""), pal: pal, id: t.id) }
        return NowEntry(date: Date(), now: Shared.read("w_now", Shared.Now.self), pal: pal)
    }
}
struct NowWidgetView: View {
    let e: NowEntry
    var body: some View {
        let p = e.pal
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [p.gold, p.gold.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if e.id == nil, let d = Shared.d.data(forKey: "w_art"), let i = UIImage(data: d) { Image(uiImage: i).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 12)) }
                else { Image("Logo").resizable().scaledToFit().padding(6) }
            }.frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.now?.title ?? "لا يوجد تشغيل الآن").font(plex(14, .bold)).foregroundStyle(p.text).lineLimit(2)
                Text(e.now?.sub ?? "المس لفتح التلاوات").font(plex(11.5)).foregroundStyle(p.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: e.now?.playing == true ? "pause.fill" : "play.fill").font(.system(size: 17)).foregroundStyle(p.onGold).frame(width: 40, height: 40).background(Circle().fill(p.gold))
        }
        .modifier(WCard(p: p))
        .environment(\.layoutDirection, .rightToLeft)
        // a chosen recitation plays at once; otherwise the player opens
        .widgetURL(URL(string: e.id.map { "badr://play/\($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0)" } ?? "badr://player"))
    }
}
struct NowWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "player", intent: PlayerIntent.self, provider: NowProvider()) { NowWidgetView(e: $0) }
            .configurationDisplayName("المشغّل").description("التلاوة الحالية أو التي تختارها — المس لتشغيلها")
            .supportedFamilies([.systemMedium])
    }
}

// MARK: - الأذكار

struct DhikrEntry: TimelineEntry { let date: Date; let label: String; let text: String; let count: Int; var pal = WPal.current }
struct DhikrProvider: AppIntentTimelineProvider {
    static let data: [String: [(String, Int)]] = {
        guard let u = Bundle.main.url(forResource: "adhkar", withExtension: "json"), let d = try? Data(contentsOf: u),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: [[String: Any]]] else { return [:] }
        return o.mapValues { $0.compactMap { x in (x["text"] as? String).map { ($0, (x["count"] as? Int) ?? 1) } }.filter { (12...140).contains($0.0.count) } }
    }()
    func placeholder(in context: Context) -> DhikrEntry { DhikrEntry(date: Date(), label: "أذكار الصباح", text: "سبحان الله وبحمده", count: 100) }
    func snapshot(for c: ColorIntent, in context: Context) async -> DhikrEntry { var e = entry(Date()); e.pal = .of(c.color?.id); return e }
    func timeline(for c: ColorIntent, in context: Context) async -> Timeline<DhikrEntry> {
        // a new dhikr every hour (morning / evening / sleep by the time)
        let cal = Calendar.current, now = Date(), pal = WPal.of(c.color?.id)
        let start = cal.dateInterval(of: .hour, for: now)?.start ?? now
        let hours = (0..<12).compactMap { cal.date(byAdding: .hour, value: $0, to: start) }
        return Timeline(entries: ([entry(now)] + hours.dropFirst().map { entry($0) }).map { var e = $0; e.pal = pal; return e }, policy: .after(hours.last ?? now.addingTimeInterval(3600)))
    }
    private func entry(_ at: Date) -> DhikrEntry {
        let cal = Calendar.current, h = cal.component(.hour, from: at)
        let (k, label) = (3...12).contains(h) ? ("morning", "أذكار الصباح") : (13...20).contains(h) ? ("evening", "أذكار المساء") : ("sleep", "أذكار النوم")
        let l = DhikrProvider.data[k] ?? []
        let d = l.isEmpty ? ("سبحان الله وبحمده", 100) : l[(h + (cal.ordinality(of: .day, in: .year, for: at) ?? 0)) % l.count]
        return DhikrEntry(date: at, label: label, text: d.0.replacingOccurrences(of: "\\s*\\(\\d+\\)", with: "", options: .regularExpression), count: d.1)
    }
}
struct DhikrWidgetView: View {
    let e: DhikrEntry
    var body: some View {
        let p = e.pal
        VStack(alignment: .leading, spacing: 6) {
            Text(e.label).font(plex(11, .semibold)).foregroundStyle(p.gold)
            Text(e.text).font(.custom("Amiri-Bold", size: 16)).foregroundStyle(p.text).minimumScaleFactor(0.55).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                Text(e.count == 1 ? "مرة واحدة" : "\(e.count.ar) مرات").font(plex(10.5)).foregroundStyle(p.muted)
                Spacer()
                Text(e.count.ar).font(plex(11.5, .semibold)).foregroundStyle(p.gold).frame(width: 26, height: 26).overlay(Circle().stroke(p.gold, lineWidth: 1.4))
            }
        }
        .modifier(WCard(p: p))
        .environment(\.layoutDirection, .rightToLeft)
        .widgetURL(URL(string: "badr://adhkar"))
    }
}
struct DhikrWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "dhikr", intent: ColorIntent.self, provider: DhikrProvider()) { DhikrWidgetView(e: $0) }
            .configurationDisplayName("الأذكار").description("أذكار الصباح والمساء والنوم حسب الوقت")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

