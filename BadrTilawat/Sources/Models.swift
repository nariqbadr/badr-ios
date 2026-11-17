import Foundation

struct Reciter: Identifiable, Hashable {
    let id: String, name: String, nameEn: String, image: String, bio: String, featured: Bool, order: Int
    /// the name in the app's language (the Arabic name as written when the app is in Arabic)
    @MainActor var shown: String { nm(name) }
    init(_ j: J) { id = j["id"].str; name = j["name"].str; nameEn = j["nameEn"].str; image = j["image"].str; bio = j["bio"].str; featured = j["featured"].bool(); order = j["order"].int }
}

struct Track: Identifiable, Hashable {
    let id: String, reciterId: String, title: String, surah: String, surahNumber: Int, audio: String, image: String
    let description: String, downloadable: Bool, order: Int, createdAt: String, publishAt: String, tags: [String]
    let featured: Bool, durationSec: Int, location: String, duration: String
    let ayahStart: Int, ayahEnd: Int, recordedAt: String
    /// A video recitation: its copies by height (largest first) and the cover frame; `audio` is its sound-only copy.
    let video: VideoInfo?
    var isVideo: Bool { !(video?.q.isEmpty ?? true) }
    /// The picture for lists and the lock screen: the chosen image, else the video's cover frame.
    var cover: String { image.isEmpty ? (video?.poster ?? "") : image }
    init(_ j: J) {
        ayahStart = j["ayahStart"].int; ayahEnd = j["ayahEnd"].int; recordedAt = j["recordedAt"].str
        let v = j["video"]; let qs = v["q"].array.map { VideoQ(h: $0["h"].int, url: $0["url"].str, size: Int64($0["size"].double ?? 0)) }.filter { !$0.url.isEmpty }
        video = qs.isEmpty ? nil : VideoInfo(q: qs.sorted { $0.h > $1.h }, poster: v["poster"].str, w: v["w"].int, h: v["h"].int, audioSize: Int64(v["audioSize"].double ?? 0))
        id = j["id"].str; reciterId = j["reciterId"].str; title = j["title"].str; surah = j["surah"].str; surahNumber = j["surahNumber"].int
        audio = j["audio"].str; image = j["image"].str; description = j["description"].str; downloadable = j["downloadable"].bool(true)
        order = j["order"].int; createdAt = j["createdAt"].str; publishAt = j["publishAt"].str; tags = j["tags"].strings
        featured = j["featured"].bool(); durationSec = j["durationSec"].int; location = j["location"].str; duration = j["duration"].str
        stamp = Fmt.parse(publishAt) ?? Fmt.parse(createdAt) ?? .distantPast
    }
    /// A recitation made in the app (a surah of «القرآن الكريم كاملًا»).
    init(id: String, reciterId: String, title: String, surah: String, surahNumber: Int, audio: String, image: String, durationSec: Int) {
        self.id = id; self.reciterId = reciterId; self.title = title; self.surah = surah; self.surahNumber = surahNumber; self.audio = audio; self.image = image
        description = ""; downloadable = true; order = 0; createdAt = ""; publishAt = ""; tags = []; featured = false; self.durationSec = durationSec
        location = ""; duration = ""; ayahStart = 0; ayahEnd = 0; recordedAt = ""; video = nil; stamp = .distantPast
    }
    /// newest first (publish date, else creation date)
    /// read once (it was read again on every sort, many times per screen)
    let stamp: Date
    var durationText: String { !duration.isEmpty ? duration : Fmt.dur(durationSec) }
}

struct VideoQ: Hashable { let h: Int, url: String, size: Int64 }
struct VideoInfo: Hashable { let q: [VideoQ], poster: String, w: Int, h: Int, audioSize: Int64 }

struct Fiqh: Identifiable { let id: String, title: String, video: String, teacher: String, description: String
    init(_ j: J) { id = j["id"].str; title = j["title"].str; video = j["video"].str; teacher = j["teacher"].str; description = j["description"].str }
}
struct Notice: Identifiable { let id: String, title: String, text: String, link: String, date: String
    init(_ j: J) { id = j["id"].str; title = j["title"].str; text = j["body"].str.isEmpty ? j["text"].str : j["body"].str; link = j["link"].str; date = j["publishAt"].str.isEmpty ? j["createdAt"].str : j["publishAt"].str }
}
struct TimelineEvent: Identifiable { let id: String, title: String, text: String, date: String, image: String, place: String
    init(_ j: J) { id = j["id"].str; title = j["title"].str; text = !j["body"].str.isEmpty ? j["body"].str : (j["text"].str.isEmpty ? j["description"].str : j["text"].str); date = !j["date"].str.isEmpty ? j["date"].str : (j["publishAt"].str.isEmpty ? j["createdAt"].str : j["publishAt"].str); image = j["image"].str; place = j["location"].str }
}

struct AppUpdate { let latestVersion: String, latestCode: Int, minCode: Int, force: Bool, message: String, url: String
    func required(_ code: Int) -> Bool { minCode > code || (force && latestCode > code) }
}
struct AppNotice { let enabled: Bool, style: String, title: String, text: String, image: String, link: String, linkLabel: String, id: String }

struct Site {
    let j: J
    var title: String { j["title"].str.isEmpty ? "تلاوات الشيخ خالد بن سالم باوزير" : j["title"].str }
    var subtitle: String { j["subtitle"].str }
    var tagline: String { j["tagline"].str }
    var heroTitle: String { j["heroTitle"].str.isEmpty ? title : j["heroTitle"].str }
    var heroText: String { j["heroText"].str }
    var heroImage: String { j["heroImage"].str }
    var featuredReciterId: String { j["featuredReciterId"].str }
    var announcement: String { j["showAnnouncement"].bool() ? j["announcement"].str : "" }
    var announcementLink: String { j["announcementLink"].str }
    var allowDownloads: Bool { j["allowDownloads"].bool(true) && j["app"]["allowDownloads"].bool(true) }
    var adhanUrl: String { j["adhanUrl"].str.isEmpty ? "/Makaah Azan.mp3" : j["adhanUrl"].str }
    var mushafUrl: String { j["mushafUrl"].str.isEmpty ? "/standard1-quran.pdf" : j["mushafUrl"].str }
    var mushafOffset: Int { j["mushafOffset"].int }
    var defaultTheme: String { j["app"]["defaultTheme"].str.isEmpty ? j["defaultTheme"].str : j["app"]["defaultTheme"].str }
    var dailyReciter: String { j["dailyAyah"]["defaultReciter"].str.isEmpty ? "yasser" : j["dailyAyah"]["defaultReciter"].str }
    var live: J { j["live"] }
    var liveOn: Bool { sec("live") && live["enabled"].bool(true) && !live["url"].str.isEmpty }
    var about: J { j["about"] }
    var footer: J { j["footer"] }
    var maintenance: (on: Bool, title: String, message: String) {
        if j["maintenance"]["enabled"].bool() { return (true, j["maintenance"]["title"].str, j["maintenance"]["message"].str) }
        let a = j["app"]["maintenance"]
        return (a["enabled"].bool(), a["title"].str, a["message"].str)
    }
    var tabs: [String] { let t = j["app"]["tabs"].strings; return t.isEmpty ? ["home", "recitations", "quran", "adhkar", "community"] : t }
    var introOn: Bool { feat("intro") && j["app"]["intro"].bool(true) }
    var shareText: String { j["app"]["shareText"].str }
    var update: AppUpdate { let u = j["app"]["update"]
        return AppUpdate(latestVersion: u["latestVersion"].str, latestCode: u["latestCode"].int, minCode: u["minCode"].int, force: u["force"].bool(), message: u["message"].str, url: u["url"].str) }
    var notice: AppNotice { let n = j["app"]["announcement"]
        return AppNotice(enabled: n["enabled"].bool(), style: n["style"].str, title: n["title"].str, text: n["text"].str, image: n["image"].str, link: n["link"].str, linkLabel: n["linkLabel"].str, id: n["id"].str) }
    /// A section shows only if both the site and the app settings allow it.
    func sec(_ n: String) -> Bool { j["sections"][n].bool(true) && j["app"]["sections"][n].bool(true) }
    func feat(_ n: String) -> Bool { j["features"][n].bool(true) }
    func reciterName(_ key: String) -> (name: String, hideAyah: Bool) { let r = j["reciterNames"][key]; return (r["name"].str, r["hideAyah"].bool()) }
}

struct SiteData {
    let rev: String
    let site: Site
    let reciters: [Reciter]
    let recitations: [Track]
    let fiqh: [Fiqh]
    let notices: [Notice]
    let events: [TimelineEvent]
    let weekly: [(id: String, count: Int)]
    let plays: [String: Int]
    let surahReciters: [(id: String, name: String)]
    /// analysed recitations: trackId → [surah, from, to]; whole-surah reciters → surahs
    let readableTracks: [String: [Int]]
    let readableSr: [String: [Int]]
    /// a long VBR recording's exact (constant-bitrate) copy: its version; played instead so a resume lands on the right second
    let readablePlay: [String: Int]
    /// «استمع كاملًا»: the whole-Quran recordings (nil: an older site that only sends quranFull)
    let quranFulls: [QuranRec]?
    let quranFull: (id: String, name: String, base: String, dur: [String: Int])
    /// adhan voices to choose from
    let adhans: [(id: String, name: String, muezzin: String, url: String, fajr: String)]
    let raw: J

    init(_ j: J) {
        rev = j["rev"].str
        site = Site(j: j["site"])
        reciters = j["reciters"].array.map(Reciter.init).sorted { $0.order < $1.order }
        recitations = j["recitations"].array.map(Track.init)
        fiqh = j["fiqh"].array.map(Fiqh.init)
        notices = j["notices"].array.map(Notice.init)
        events = j["events"].array.map(TimelineEvent.init)
        weekly = j["weeklyPopular"].array.map { ($0["id"].str, $0["count"].int) }
        plays = j["plays"].dict.mapValues { $0.int }
        surahReciters = j["surahReciters"].array.map { ($0["id"].str, $0["name"].str) }
        readableTracks = j["readable"]["tracks"].dict.mapValues { $0.array.map { $0.int } }
        readableSr = j["readable"]["sr"].dict.mapValues { $0.array.map { $0.int } }
        readablePlay = j["readable"]["play"].dict.mapValues { $0.int }
        quranFulls = j["quranFulls"].isNull ? nil : j["quranFulls"].array.map(QuranRec.init)
        let qf = j["quranFull"]; quranFull = (qf["id"].str, qf["name"].str, qf["base"].str, qf["dur"].dict.mapValues { $0.int })
        adhans = j["adhans"].array.map { ($0["id"].str, $0["name"].str, $0["muezzin"].str, $0["url"].str, $0["fajr"].str) }
        raw = j
        sortedTracks = recitations.sorted { $0.stamp != $1.stamp ? $0.stamp > $1.stamp : $0.order > $1.order }
        byId = Dictionary(recitations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        reciterById = Dictionary(reciters.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    /// sorted once when the data arrives (it was sorted again on every redraw of every list)
    let sortedTracks: [Track]
    /// found at once by id (lists looked every recitation and reader up one by one)
    let byId: [String: Track]
    let reciterById: [String: Reciter]
}

enum Fmt {
    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    private static let day: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    private static let dayTime: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f }()
    static func parse(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        return iso.date(from: s) ?? dayTime.date(from: String(s.prefix(16))) ?? day.date(from: String(s.prefix(10)))
    }
    static func dur(_ sec: Int) -> String {
        if sec <= 0 { return "" }
        return sec >= 3600 ? String(format: "%d:%02d:%02d", sec / 3600, sec % 3600 / 60, sec % 60) : String(format: "%d:%02d", sec / 60, sec % 60)
    }
    // formatters are slow to make: one per language, kept
    nonisolated(unsafe) private static var fmts: [String: DateFormatter] = [:]
    private static func fmt(_ k: String, _ make: (DateFormatter) -> Void) -> DateFormatter {
        let key = k + "|" + L.locale.identifier
        if let f = fmts[key] { return f }
        let f = DateFormatter(); f.locale = L.locale; make(f); fmts[key] = f; return f
    }
    static func time(_ d: Date) -> String { fmt("t") { $0.dateFormat = "h:mm a" }.string(from: d) }
    static func date(_ d: Date) -> String { fmt("d") { $0.dateStyle = .medium }.string(from: d) }
    static func ago(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "الآن" }; if s < 3600 { return "قبل \((s / 60).ar) د" }; if s < 86400 { return "قبل \((s / 3600).ar) س" }
        if s < 86400 * 30 { return "قبل \((s / 86400).ar) يوم" }; return date(d)
    }
    static func isNew(_ t: Track) -> Bool { Date().timeIntervalSince(t.stamp) < 7 * 86400 }
}
