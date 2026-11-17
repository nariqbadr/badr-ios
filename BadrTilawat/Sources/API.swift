import Foundation
import UIKit

/// Everything the app shows comes from the site (same API as the website and the Android app), cached for offline use.
@MainActor
final class Repo: ObservableObject {
    static let shared = Repo()
    static let site = "https://bawazirquran.com/"
    static let ajax = site + "wp-admin/admin-ajax.php"
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    static var build: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") ?? 1 }
    /// «iPhone 15 Pro»-style name for the dashboard's device list (the hardware code, e.g. iPhone16,1)
    static let deviceModel: String = {
        var u = utsname(); uname(&u)
        let code = withUnsafeBytes(of: &u.machine) { b in String(decoding: b.prefix { $0 != 0 }, as: UTF8.self) }
        return code.hasPrefix("iPhone") || code.hasPrefix("iPad") ? code : "iPhone"
    }()
    static let ua = "BadrTilawat/\(version) (iOS \(UIDevice.current.systemVersion); iPhone)"

    @Published private(set) var data: SiteData? { didSet { gen &+= 1 } }
    /// changes with each new data (for caches of things worked out from it)
    private(set) var gen = 0
    @Published private(set) var offline = false
    /// the screen shown now («يتصفح» in the dashboard)
    var page = tr("الرئيسية")

    let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["User-Agent": Repo.ua]
        c.timeoutIntervalForRequest = 30
        c.httpCookieStorage = HTTPCookieStorage.shared
        return URLSession(configuration: c)
    }()
    private var cacheURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("site.json") }

    private init() {
        if let d = try? Data(contentsOf: cacheURL) { data = SiteData(J(data: d)) }
    }

    func refresh() async {
        var u = Repo.ajax + "?action=bz&do=data"
        if let r = data?.rev, !r.isEmpty { u += "&rev=" + Repo.enc(r) }
        guard let url = URL(string: u) else { return }
        do {
            let (d, resp) = try await session.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { offline = true; return }
            if offline { offline = false }
            // the site's data is read off the main thread (a big download: reading it here froze the screen)
            let cache = cacheURL
            let sd: SiteData? = await Task.detached(priority: .userInitiated) { () -> SiteData? in
                let j = J(data: d)
                if j["same"].bool() || j["site"].isNull { return nil }
                try? d.write(to: cache)
                return SiteData(j)
            }.value
            if let sd { data = sd }
        } catch { offline = true }
    }

    static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? s }

    /// Site media paths are relative to the site root (Arabic names, spaces) → absolute, encoded URL.
    static func media(_ raw: String?) -> URL? {
        let s = (raw ?? "").trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return URL(string: s) ?? URL(string: s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s) }
        if s.hasPrefix("//") { return URL(string: "https:" + s) }
        // an imam's photo from the theme, as older saved data names it («@imams/x.jpg»)
        if s.hasPrefix("@imams/") { return URL(string: site + "wp-content/themes/bawazir-library-premium-v2/assets/img/" + s.dropFirst()) }
        let path = s.split(separator: "/").map { enc(String($0)) }.joined(separator: "/")
        return URL(string: site + path)
    }

    func reciter(_ id: String?) -> Reciter? { id.flatMap { data?.reciterById[$0] } }
    /// a part of a longer recording (one surah of a whole juz…) is listed as "<id>__s<surah>"
    /// A reciter's photo for a choice («آية اليوم», the mushaf): the dashboard's photo for that name, the site reciter's, the recording's.
    func recImg(_ v: String, _ label: String) -> String {
        let names = data?.site.j["reciterNames"]
        let img = names?[v]["image"].str ?? ""
        if !img.isEmpty { return img }
        if v.hasPrefix("tk:") || v.hasPrefix("tkr:") { let id = String(v.split(separator: ":", maxSplits: 1).last ?? ""); if let r = reciter(id), !r.image.isEmpty { return r.image } }
        if v.hasPrefix("sr:"), let q = quranRec(String(v.dropFirst(3))) { let i = quranImage(q); if !i.isEmpty { return i } }
        let norm = { (x: String) in x.replacingOccurrences(of: "^\\s*(الشيخ|القارئ|الإمام)\\s+", with: "", options: .regularExpression).split(separator: " ").map(String.init) }
        let w = norm(label); guard w.count >= 2 else { return "" }
        return data?.reciters.first { r in let y = norm(r.name); return y.first == w.first && y.last == w.last }?.image ?? ""
    }
    static func partBase(_ id: String?) -> String? { id?.replacingOccurrences(of: "__s\\d{1,3}$", with: "", options: .regularExpression) }
    func track(_ id: String?) -> Track? { let b = Repo.partBase(id); return b.flatMap { data?.byId[$0] } ?? quranTrack(b) }
    func image(for t: Track) -> String { t.image.isEmpty ? (reciter(t.reciterId)?.image ?? "") : t.image }
    static func withSheikh(_ n: String) -> String {
        let t = n.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.range(of: "^(الشيخ|الإمام|القارئ|د\\.|الدكتور)", options: .regularExpression) != nil { return t }
        return tr("الشيخ ") + t
    }

    // MARK: Quran text
    private var surahCache: [Int: [String]] = [:]
    func surahText(_ s: Int) async -> [String]? {
        if let c = surahCache[s] { return c }
        let f = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("surah-\(s).json")
        var body: Data?
        if let url = URL(string: Repo.ajax + "?action=bz&do=quran_surah&surah=\(s)"), let (d, r) = try? await session.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 {
            body = d; try? d.write(to: f)
        }
        if body == nil { body = try? Data(contentsOf: f) }
        guard let b = body else { return nil }
        let a = J(data: b)["data"]["ayahs"].array.map { $0["text"].str }
        if a.isEmpty { return nil }
        surahCache[s] = a; return a
    }

    /// Tafsir (quran_edition): ayah number → text.
    func tafsir(_ s: Int, edition: String = "ar.muyassar") async -> [Int: String] {
        guard let url = URL(string: Repo.ajax + "?action=bz&do=quran_edition&kind=surah&n=\(s)&edition=\(edition)"),
              let (d, _) = try? await session.data(from: url) else { return [:] }
        var out: [Int: String] = [:]
        for a in J(data: d)["data"]["ayahs"].array { out[a["ayah"].int] = a["text"].str }
        return out
    }

    // MARK: statistics — the same events as the site, so the dashboard counts iPhone listeners too
    nonisolated func event(_ type: String, _ fields: [String: String] = [:]) {
        Task { @MainActor in
            var f: [String: String] = ["type": type, "device": "mobile", "visitor": Store.shared.visitorId, "src": "app",
                                       "appVer": "ios-" + Repo.version, "appCode": "\(Repo.build)", "model": Repo.deviceModel, "android": "", "ios": UIDevice.current.systemVersion,
                                       "timezone": TimeZone.current.identifier, "pageLabel": self.page]
            let place = Store.shared.str("place").components(separatedBy: tr("، ")).filter { !$0.isEmpty }
            if place.count >= 2 { f["city"] = place.first; f["country"] = place.last } else if let c = place.first { f["country"] = c }
            let p = AudioPlayer.shared
            if let t = p.current { f["audioState"] = p.playing ? "playing" : "paused"; f["listeningTitle"] = t.title; f["listeningReciter"] = self.reciter(t.reciterId)?.name ?? "" } else { f["audioState"] = "idle" }
            if !Store.shared.name.isEmpty { f["visitorName"] = Store.shared.name }
            fields.forEach { f[$0.key] = $0.value }
            var req = URLRequest(url: URL(string: Repo.ajax + "?action=bz&do=track")!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = f.map { Repo.enc($0.key) + "=" + Repo.enc($0.value) }.joined(separator: "&").data(using: .utf8)
            _ = try? await self.session.data(for: req)
        }
    }
}
