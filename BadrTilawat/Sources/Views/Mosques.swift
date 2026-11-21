import SwiftUI
import MapKit
import CoreLocation

/// «بيوت الله»: the mosques around the person, nearest first, with the distance and the time on foot and by car.
/// The phone asks OpenStreetMap (its servers and its search) and Apple Maps itself, with the site alongside; the last list
/// is kept, so the page opens with it at once.
struct Mosque: Identifiable, Hashable {
    let id: String, name: String; var area: String; let lat: Double, lng: Double
    var ar = "", en = "", street = ""
    var coord: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    /// The name in the app's language: Arabic first for Arabic, Urdu and Persian, the English (Latin) name first for the rest;
    /// a place with no name says where it is, and an Arabic name says it is a mosque.
    var title: String {
        // only a name written in the app's own script: Arabic letters for Arabic, Urdu and Persian, Latin for the rest
        let rtl = ["ar", "ur", "fa"].contains(L.code)
        let fits = { (v: String) in !v.isEmpty && (v.range(of: "[\\u0621-\\u064A\\u0671-\\u06D3]", options: .regularExpression) != nil) == rtl }
        var n = ((rtl ? [ar, name, en] : [en, name, ar]).first(where: fits) ?? "").trimmingCharacters(in: .whitespaces)
        if n.isEmpty || n == "مسجد" { return tr("مسجد") }
        if L.code == "ar", n.range(of: "مسجد|جامع|مصلى|مصلّى|زاوية", options: .regularExpression) == nil { n = "مسجد " + n }
        return n
    }
    /// the place under the name, only in the app's own script
    var place: String {
        let rtl = ["ar", "ur", "fa"].contains(L.code)
        let fits = { (v: String) in !v.isEmpty && (v.range(of: "[\\u0621-\\u064A\\u0671-\\u06D3]", options: .regularExpression) != nil) == rtl }
        return fits(area) ? area : fits(street) ? street : ""
    }
    var unnamed: Bool { name.isEmpty && ar.isEmpty && en.isEmpty }
}

@MainActor final class Mosques: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = Mosques()
    @Published var pos: CLLocationCoordinate2D?
    @Published var near: [Mosque]?
    @Published var error = ""
    @Published var saved: [Mosque] = []
    @Published var denied = false
    /// the well-known mosques of the person's region (nil until asked; empty when none is known there)
    @Published var famousNear: [Mosque]?
    private var famousAt: CLLocationCoordinate2D?
    private var nearAt: CLLocationCoordinate2D?
    private let lm = CLLocationManager()
    private var cont: CheckedContinuation<CLLocation?, Never>?
    /// in-app directions: every fix while they are open
    private var onFix: ((CLLocation) -> Void)?

    static let famous: [Mosque] = [
        ("المسجد الحرام", "مكة المكرمة", 21.4225, 39.8262), ("المسجد النبوي", "المدينة المنورة", 24.4672, 39.6111), ("المسجد الأقصى", "القدس", 31.7761, 35.2358),
        ("مسجد قباء", "المدينة المنورة", 24.4393, 39.6173), ("مسجد القبلتين", "المدينة المنورة", 24.4842, 39.5789), ("الجامع الأزهر", "القاهرة", 30.0457, 31.2627),
        ("مسجد الإمام الحسين", "القاهرة", 30.0478, 31.263), ("مسجد عمرو بن العاص", "القاهرة", 30.0103, 31.2333), ("مسجد محمد علي", "قلعة صلاح الدين، القاهرة", 30.0287, 31.2599),
        ("الجامع الأموي", "دمشق", 33.5117, 36.3064), ("جامع الشيخ زايد الكبير", "أبوظبي", 24.4128, 54.475), ("جامع السلطان أحمد", "إسطنبول", 41.0054, 28.9768),
        ("مسجد الحسن الثاني", "الدار البيضاء", 33.6083, -7.6325), ("جامع القرويين", "فاس", 34.0646, -4.9736), ("جامع الزيتونة", "تونس", 36.7975, 10.1711),
    ].enumerated().map { i, m in Mosque(id: "f\(i)", name: tr(m.0), area: tr(m.1), lat: m.2, lng: m.3) }

    override private init() {
        super.init(); lm.delegate = self; lm.desiredAccuracy = kCLLocationAccuracyBest
        saved = (UserDefaults.standard.array(forKey: "mqSaved") as? [[String: Any]] ?? []).compactMap { d in
            guard let id = d["id"] as? String, let n = d["name"] as? String, let la = d["lat"] as? Double, let lo = d["lng"] as? Double else { return nil }
            return Mosque(id: id, name: n, area: d["area"] as? String ?? "", lat: la, lng: lo, ar: d["ar"] as? String ?? "", en: d["en"] as? String ?? "", street: d["street"] as? String ?? "")
        }
        if let p = UserDefaults.standard.array(forKey: "mqPos") as? [Double], p.count == 2 { pos = CLLocationCoordinate2D(latitude: p[0], longitude: p[1]) }
        restoreNear()
    }
    var allowed: Bool { [.authorizedWhenInUse, .authorizedAlways].contains(lm.authorizationStatus) }

    /// asks once (on this page only); then a fresh, exact fix
    func locate(ask: Bool) async {
        if lm.authorizationStatus == .notDetermined {
            guard ask else { return }
            lm.requestWhenInUseAuthorization()
            for _ in 0..<60 where lm.authorizationStatus == .notDetermined { try? await Task.sleep(nanoseconds: 500_000_000) }
        }
        denied = [.denied, .restricted].contains(lm.authorizationStatus)
        guard allowed, onFix == nil else { return }
        let l: CLLocation? = await withCheckedContinuation { k in cont?.resume(returning: nil); cont = k; lm.requestLocation() }
        if let l { keep(l) }
    }
    private func keep(_ l: CLLocation) { pos = l.coordinate; UserDefaults.standard.set([l.coordinate.latitude, l.coordinate.longitude], forKey: "mqPos") }
    /// follow the person while the directions are open
    func follow(_ on: Bool, _ f: ((CLLocation) -> Void)? = nil) {
        onFix = on ? f : nil
        if on { lm.distanceFilter = 2; lm.startUpdatingLocation() } else { lm.stopUpdatingLocation(); lm.distanceFilter = kCLDistanceFilterNone }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let l = locations.last else { return }
            if let k = cont { cont = nil; k.resume(returning: l) }
            if let f = onFix, l.horizontalAccuracy >= 0, l.horizontalAccuracy < 80 { keep(l); f(l) }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { Task { @MainActor in cont?.resume(returning: nil); cont = nil } }

    private func get(_ q: [String: String]) async -> [String: Any]? {
        var u = URLComponents(string: Repo.ajax)!; u.queryItems = [URLQueryItem(name: "action", value: "bz")] + q.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = u.url else { return nil }
        // the app's own session (its User-Agent): the host turns away the default one
        var req = URLRequest(url: url); req.timeoutInterval = 45
        guard let (d, r) = try? await Repo.shared.session.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
    private func items(_ j: [String: Any]?) -> [Mosque]? {
        guard let j, j["ok"] as? Bool == true, let a = j["items"] as? [[String: Any]] else { return nil }
        return a.compactMap { x in
            guard let id = x["id"] as? String, let la = (x["lat"] as? NSNumber)?.doubleValue, let lo = (x["lng"] as? NSNumber)?.doubleValue else { return nil }
            let s = { (k: String) in (x[k] as? String ?? "").trimmingCharacters(in: .whitespaces) }
            return Mosque(id: id, name: s("name"), area: s("area"), lat: la, lng: lo, ar: s("ar"), en: s("en"), street: s("street"))
        }
    }
    /// what each source answered last time (shown small under «تعذّر…», to find out why)
    @Published var diag = ""
    private var nearTime = Date.distantPast
    /// The mosques around: from the phone itself first — OpenStreetMap (four servers, the first to answer) and Apple Maps,
    /// all at once — and the site alongside; whichever answers first with mosques is used. The last list is kept, so the
    /// page opens with it at once and is refreshed behind it.
    func loadNear(force: Bool = false) async {
        guard let p = pos else { return }
        if !force, (near?.count ?? 0) >= 5, let a = nearAt, abs(a.latitude - p.latitude) < 0.002, abs(a.longitude - p.longitude) < 0.002, Date().timeIntervalSince(nearTime) < 86400 { return }
        var why: [String] = []
        async let ap = apple(near: p)
        // every source is asked at once and ALL their answers are put together (the first answer alone was sometimes a
        // short one — two mosques — and the full lists that came a moment later were thrown away). Up to 7 s is waited
        // for the rest once one has answered; nothing yet by then: up to 20 s for the first.
        let osm: [Mosque]? = await withTaskGroup(of: ([Mosque]?, String).self) { g in
            for ep in Self.overpassServers { g.addTask { await self.overpass(p, ep) } }
            g.addTask { await self.nominatim(p) }
            g.addTask {
                let j = await self.get(["do": "mosques_near", "lat": String(format: "%.5f", p.latitude), "lng": String(format: "%.5f", p.longitude)])
                let r = await self.items(j)
                return (r, "site:" + (r.map { "\($0.count)" } ?? "x"))
            }
            g.addTask { try? await Task.sleep(nanoseconds: 7_000_000_000); return (nil, "t") }
            g.addTask { try? await Task.sleep(nanoseconds: 20_000_000_000); return (nil, "T") }
            var all: [Mosque] = [], answered = false, overpassFull = false, left = Self.overpassServers.count + 2
            for await (r, tag) in g {
                if tag == "t" { if answered { break }; continue }
                if tag == "T" { break }
                why.append(tag); left -= 1
                if let r { answered = true; all += r; if !tag.hasPrefix("site") && !tag.hasPrefix("nominatim") && !r.isEmpty { overpassFull = true } }
                // a full OpenStreetMap list and the site's both in: nothing more is needed
                if left == 0 || (overpassFull && why.contains(where: { $0.hasPrefix("site") }) && why.contains(where: { $0.hasPrefix("nominatim") })) { break }
            }
            g.cancelAll()
            return answered ? all : nil
        }
        var r = osm.map(Self.dedupe)
        let a = await ap
        why.append("apple:\(a.count)")
        if r?.isEmpty ?? true {
            if !a.isEmpty { r = a }
        } else if let rr = r {
            // the mosques Apple Maps knows that OpenStreetMap lacks (none of its own within 60 m)
            r = rr + a.filter { x in !rr.contains { Self.d($0.coord, x.coord) < 60 } }
        }
        if let rr = r, rr.contains(where: { $0.unnamed }) {
            // a mosque OpenStreetMap has no name for: the name Apple Maps knows at the same place (within 80 m)
            r = rr.map { m in
                guard m.unnamed, let x = a.min(by: { Self.d(m.coord, $0.coord) < Self.d(m.coord, $1.coord) }), Self.d(m.coord, x.coord) < 80 else { return m }
                return Mosque(id: m.id, name: x.name, area: m.area.isEmpty ? x.area : m.area, lat: m.lat, lng: m.lng, street: m.street)
            }
        }
        // the mosques added by hand in the dashboard, within 3 km (an unnamed point at the same place gives way to them)
        let extra: [Mosque] = (Repo.shared.data?.site.mosquesExtra ?? []).compactMap { x in
            guard let la = x["lat"].double, let lo = x["lng"].double, !x["name"].str.isEmpty else { return nil }
            let n = x["name"].str, arabic = n.range(of: "[\\u0621-\\u064A]", options: .regularExpression) != nil
            let m = Mosque(id: "x" + x["id"].str, name: n, area: x["area"].str, lat: la, lng: lo, ar: arabic ? n : "", en: x["en"].str.isEmpty ? (arabic ? "" : n) : x["en"].str)
            return Self.d(p, m.coord) <= 3000 ? m : nil
        }
        if !extra.isEmpty {
            let base = (r ?? []).filter { o in !o.id.hasPrefix("x") && !extra.contains { Self.d($0.coord, o.coord) < 40 } }
            r = extra + base
        }
        diag = why.joined(separator: " · ")
        if r == nil, near?.isEmpty == false { error = ""; return }   // the kept list stays
        error = r == nil ? tr("تعذّر جلب المساجد الآن، حاول بعد قليل") : ""
        near = (r ?? []).sorted { dist($0) < dist($1) }; nearAt = p; nearTime = Date()
        if let n = near, r != nil { keepNear(n, p) }
        await placeNames(p)
    }
    /// under each of the nearest, where it is — in the app's language (the phone's map, asked in that language)
    private func placeNames(_ p: CLLocationCoordinate2D) async {
        guard var n = near else { return }
        let g = CLGeocoder(); var changed = false
        for i in n.indices.prefix(10) where n[i].place.isEmpty {
            guard let pm = try? await g.reverseGeocodeLocation(CLLocation(latitude: n[i].lat, longitude: n[i].lng), preferredLocale: L.locale).first else { continue }
            let a = [pm.thoroughfare, pm.subLocality ?? pm.locality].compactMap { $0 }.joined(separator: tr("، "))
            if !a.isEmpty { n[i].area = a; changed = true }
        }
        if changed, nearAt?.latitude == p.latitude, nearAt?.longitude == p.longitude { near = n; keepNear(n, p) }
    }
    private func keepNear(_ n: [Mosque], _ p: CLLocationCoordinate2D) {
        let a = n.prefix(60).map { ["id": $0.id, "name": $0.name, "area": $0.area, "lat": $0.lat, "lng": $0.lng, "ar": $0.ar, "en": $0.en, "street": $0.street] as [String: Any] }
        UserDefaults.standard.set(["lat": p.latitude, "lng": p.longitude, "at": Date().timeIntervalSince1970, "items": a] as [String: Any], forKey: "mqNear")
    }
    private func restoreNear() {
        guard let d = UserDefaults.standard.dictionary(forKey: "mqNear"), let la = d["lat"] as? Double, let lo = d["lng"] as? Double, let a = d["items"] as? [[String: Any]] else { return }
        near = a.compactMap { d in
            guard let id = d["id"] as? String, let n = d["name"] as? String, let la = d["lat"] as? Double, let lo = d["lng"] as? Double else { return nil }
            return Mosque(id: id, name: n, area: d["area"] as? String ?? "", lat: la, lng: lo, ar: d["ar"] as? String ?? "", en: d["en"] as? String ?? "", street: d["street"] as? String ?? "")
        }
        nearAt = CLLocationCoordinate2D(latitude: la, longitude: lo)
        nearTime = Date(timeIntervalSince1970: d["at"] as? Double ?? 0)
    }
    /// one entry per mosque: its point and its building outline (or two servers' copies) become one, the named one kept
    nonisolated static func dedupe(_ l: [Mosque]) -> [Mosque] {
        var out: [Mosque] = []
        for m in l.sorted(by: { !$0.unnamed && $1.unnamed }) where !out.contains(where: { d($0.coord, m.coord) < (m.unnamed ? 45 : 12) }) { out.append(m) }
        return out
    }
    /// a mosque on OpenStreetMap: a Muslim place of worship, or a mosque building
    nonisolated static func osmQuery(_ la: Double, _ lo: Double, _ r: Int) -> String {
        let a = "(around:\(r),\(la),\(lo))"
        return "[out:json][timeout:20];(nwr[\"amenity\"=\"place_of_worship\"][\"religion\"=\"muslim\"]\(a);nwr[\"building\"=\"mosque\"]\(a););out center tags 120;"
    }
    static let overpassServers = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter", "https://overpass.private.coffee/api/interpreter"]
    /// «المشهورة»: the region's well-known mosques (the world's famous ones only when none is known around)
    func loadFamous() async {
        guard let p = pos else { return }
        if famousNear != nil, let a = famousAt, abs(a.latitude - p.latitude) < 0.05, abs(a.longitude - p.longitude) < 0.05 { return }
        guard let r = items(await get(["do": "mosques_famous", "lat": String(format: "%.4f", p.latitude), "lng": String(format: "%.4f", p.longitude)])) else { return }
        famousNear = r.sorted { dist($0) < dist($1) }; famousAt = p
    }
    /// OpenStreetMap's search (Nominatim): the places of worship in a box around the person, the mosques among them — quick
    nonisolated private func nominatim(_ p: CLLocationCoordinate2D) async -> ([Mosque]?, String) {
        let d = 0.027, la = p.latitude, lo = p.longitude
        var u = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        u.queryItems = [URLQueryItem(name: "amenity", value: "place_of_worship"), URLQueryItem(name: "viewbox", value: "\(lo - d),\(la + d),\(lo + d),\(la - d)"),
                        URLQueryItem(name: "bounded", value: "1"), URLQueryItem(name: "format", value: "jsonv2"), URLQueryItem(name: "limit", value: "40"),
                        URLQueryItem(name: "extratags", value: "1"), URLQueryItem(name: "namedetails", value: "1")]
        var req = URLRequest(url: u.url!); req.timeoutInterval = 15
        req.setValue("BadrTilawat/iOS (+https://bawazirquran.com)", forHTTPHeaderField: "User-Agent")
        guard let (data, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200,
              let a = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return (nil, "nominatim:x") }
        let out: [Mosque] = a.compactMap { x in
            let nd = x["namedetails"] as? [String: String] ?? [:], ex = x["extratags"] as? [String: String] ?? [:]
            let n = nd["name"] ?? (x["name"] as? String ?? "")
            let muslim = ex["religion"] == "muslim" || ex["building"] == "mosque" || n.range(of: "مسجد|جامع|مصلى|زاوية|mosque|masjid", options: [.regularExpression, .caseInsensitive]) != nil
            guard muslim, let la = Double(x["lat"] as? String ?? ""), let lo = Double(x["lon"] as? String ?? "") else { return nil }
            return Mosque(id: "\((x["osm_type"] as? String ?? "n").prefix(1))\((x["osm_id"] as? NSNumber)?.int64Value ?? 0)", name: n, area: "", lat: la, lng: lo,
                          ar: nd["name:ar"] ?? "", en: nd["name:en"] ?? "", street: "")
        }
        return (out, "nominatim:\(out.count)")
    }
    /// straight from OpenStreetMap, from the phone
    nonisolated private func overpass(_ p: CLLocationCoordinate2D, _ ep: String) async -> ([Mosque]?, String) {
        let host = URL(string: ep)?.host ?? ep
        let q = Mosques.osmQuery(p.latitude, p.longitude, 3000)
        var req = URLRequest(url: URL(string: ep)!); req.httpMethod = "POST"; req.timeoutInterval = 20
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("BadrTilawat/iOS (+https://bawazirquran.com)", forHTTPHeaderField: "User-Agent")
        req.httpBody = ("data=" + (q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")).data(using: .utf8)
        guard let (d, r) = try? await URLSession.shared.data(for: req) else { return (nil, host + ":x") }
        let code = (r as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let els = j["elements"] as? [[String: Any]] else { return (nil, host + ":\(code)") }
        let out: [Mosque] = els.compactMap { e in
            let t = e["tags"] as? [String: String] ?? [:], c = e["center"] as? [String: Any]
            guard let la = ((e["lat"] ?? c?["lat"]) as? NSNumber)?.doubleValue, let lo = ((e["lon"] ?? c?["lon"]) as? NSNumber)?.doubleValue else { return nil }
            let area = [t["addr:street"], t["addr:suburb"] ?? t["addr:city"]].compactMap { $0 }.joined(separator: "، ")
            return Mosque(id: "\((e["type"] as? String ?? "n").prefix(1))\((e["id"] as? NSNumber)?.int64Value ?? 0)", name: t["name"] ?? "", area: area, lat: la, lng: lo,
                          ar: t["name:ar"] ?? "", en: t["name:en"] ?? "", street: t["addr:street"] ?? "")
        }
        return (out, host + ":\(out.count)")
    }
    func search(_ q: String) async -> [Mosque] {
        if let r = items(await get(["do": "mosques_search", "q": q])), !r.isEmpty { return r }
        let mq = q.range(of: "مسجد|جامع|mosque|masjid|cami", options: [.regularExpression, .caseInsensitive]) != nil ? q : tr("مسجد") + " " + q
        return await appleSearch(mq, region: nil)
    }
    /// Apple Maps: mosques within ~3 km (two wordings, merged)
    private func apple(near p: CLLocationCoordinate2D) async -> [Mosque] {
        let reg = MKCoordinateRegion(center: p, latitudinalMeters: 6000, longitudinalMeters: 6000)
        async let a1 = appleSearch("مسجد", region: reg); async let a2 = appleSearch("mosque", region: reg); async let a3 = appleSearch("جامع", region: reg)
        let out = await a1 + a2 + a3
        var seen = Set<String>()
        return out.filter { seen.insert("\(Int($0.lat * 5000)):\(Int($0.lng * 5000))").inserted && dist($0) <= 3500 }
    }
    private func appleSearch(_ q: String, region: MKCoordinateRegion?) async -> [Mosque] {
        let r = MKLocalSearch.Request(); r.naturalLanguageQuery = q; r.resultTypes = .pointOfInterest
        if let region { r.region = region }
        guard let res = try? await MKLocalSearch(request: r).start() else { return [] }
        return res.mapItems.compactMap { it in
            // only a place whose name says it is a mosque (Apple's search also returns shops named after a nearby mosque)
            let n = (it.name ?? "").trimmingCharacters(in: .whitespaces)
            guard n.range(of: "^(ال)?(مسجد|جامع|زاوية|مصلى|مصلّى)", options: .regularExpression) != nil
                    || n.range(of: "\\b(mosque|masjid|masjed|cami|jami)\\b", options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
            let c = it.placemark.coordinate
            let area = [it.placemark.thoroughfare, it.placemark.subLocality ?? it.placemark.locality].compactMap { $0 }.joined(separator: tr("، "))
            return Mosque(id: "a\(Int(c.latitude * 1e5)):\(Int(c.longitude * 1e5))", name: it.name ?? "", area: area.isEmpty ? (it.placemark.country ?? "") : area,
                          lat: c.latitude, lng: c.longitude, street: it.placemark.thoroughfare ?? "")
        }
    }

    nonisolated static func d(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double { CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) }
    func dist(_ m: Mosque) -> Double { guard let p = pos else { return 0 }; return Self.d(p, m.coord) }
    /// rough times before a real route: streets aren't straight (×1.3), 80 m a minute on foot, 25 km/h by car in town
    static func walkS(_ m: Double) -> Double { m * 1.3 / 80 * 60 }
    static func carS(_ m: Double) -> Double { m * 1.4 / 416 * 60 + 60 }
    static func km(_ m: Double) -> String {
        if m < 1000 { return tr("{0} م", (Int((m / 10).rounded()) * 10).ar) }
        if m < 100_000 { return tr("{0} كم", L.digits(String(format: "%.1f", m / 1000))) }
        return tr("{0} كم", Int((m / 1000).rounded()).ar)
    }
    static func mins(_ s: Double) -> String {
        s < 3600 ? tr("{0} د", max(1, Int((s / 60).rounded())).ar) : tr("{0} س {1} د", Int(s / 3600).ar, Int((s.truncatingRemainder(dividingBy: 3600) / 60).rounded()).ar)
    }
    static func clock(_ s: Double) -> String { L.digits(Date().addingTimeInterval(s).formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L.locale))) }
    func toggle(_ m: Mosque) {
        if saved.contains(where: { $0.id == m.id }) { saved.removeAll { $0.id == m.id } } else { saved.insert(m, at: 0) }
        saved = Array(saved.prefix(50))
        UserDefaults.standard.set(saved.map { ["id": $0.id, "name": $0.name, "area": $0.area, "lat": $0.lat, "lng": $0.lng, "ar": $0.ar, "en": $0.en, "street": $0.street] as [String: Any] }, forKey: "mqSaved")
    }
    /// «يُؤذَّن للعصر بعد ٢٤ د» when the next adhan is within three hours
    static func nextAdhan() -> String {
        guard let n = Prayers.shared.next() else { return "" }
        let left = n.time.timeIntervalSinceNow
        return left > 0 && left < 10800 ? tr("يُؤذَّن ل{0} بعد {1}", n.name, mins(left)) : ""
    }
}

struct MosquesView: View {
    @StateObject private var mq = Mosques.shared
    @Environment(\.pal) private var c
    @State private var busy = false
    @State private var picked: String?
    private var list: [Mosque] { (mq.near ?? []).sorted { mq.dist($0) < mq.dist($1) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(16).padding(.bottom, 20)
        }
        .refreshable { await mq.locate(ask: true); await mq.loadNear(force: true) }
        .background(c.bg.ignoresSafeArea())
        .environment(\.layoutDirection, L.dir)
        .task { busy = true; await mq.locate(ask: true); await mq.loadNear(); busy = false }
    }
    @ViewBuilder private var content: some View {
        if mq.pos == nil, !busy {
            empty(mq.denied ? tr("فعّل الوصول إلى الموقع من الإعدادات لنعرض لك أقرب المساجد") : tr("اسمح بتحديد موقعك لنعرض لك أقرب المساجد"), action: mq.denied ? nil : tr("تحديد موقعي")) {
                Task { busy = true; await mq.locate(ask: true); await mq.loadNear(force: true); busy = false }
            }
        } else if mq.near == nil || (busy && mq.near?.isEmpty != false) {
            empty(tr("جارٍ البحث عن المساجد القريبة…"))
        } else if list.isEmpty {
            empty(!mq.error.isEmpty ? mq.error : tr("لا توجد مساجد قريبة في نطاق ٣ كم"))
        } else {
            // the chosen one (the nearest until another is tapped) large at the top, the others ranked under it
            let top = list.first { $0.id == picked } ?? list[0]
            NearestCard(m: top, chosen: top.id != list[0].id).id(top.id)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            if list.count > 1 {
                Text(tr("مساجد حولك")).font(F.amiri(19, bold: true)).foregroundStyle(c.text).padding(.top, 10)
                let far = max(list.map { mq.dist($0) }.max() ?? 1, 1)
                LazyVStack(spacing: 8) {
                    ForEach(Array(list.enumerated()).filter { $0.element.id != top.id }, id: \.element.id) { i, m in
                        Button { withAnimation(.easeInOut(duration: 0.3)) { picked = m.id } } label: { MosqueRow(m: m, n: i + 1, far: far) }.buttonStyle(Press(scale: 0.98))
                    }
                }
            }
        }
    }
    private func empty(_ t: String, action: String? = nil, _ f: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 12) {
            SiteIcon(name: "mosque", size: 34, color: c.muted)
            Text(t).font(F.plex(14)).foregroundStyle(c.muted).multilineTextAlignment(.center)
            if let action { GoldButton(title: action, icon: "locate", action: f) }
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}

/// The nearest mosque, large: its name, where it is, and the three numbers that matter — how far, on foot, by car —
/// with the coming adhan under them.
private struct NearestCard: View {
    let m: Mosque; var chosen = false
    @Environment(\.openURL) private var openURL
    @ObservedObject private var mq = Mosques.shared
    @Environment(\.pal) private var c
    var body: some View {
        let d = mq.dist(m), adhan = Mosques.nextAdhan()
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                SiteIcon(name: "mosque", size: 34, color: c.onGold)
                    .frame(width: 64, height: 72)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 32, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 32).fill(c.gold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(chosen ? tr("المسجد الذي اخترته") : tr("أقرب مسجد إليك")).font(F.plex(12, .semibold)).foregroundStyle(c.gold)
                    Text(m.title).font(F.amiri(23, bold: true)).foregroundStyle(c.text).lineLimit(2).minimumScaleFactor(0.8)
                    if !m.place.isEmpty { Text(m.place).font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                stat(Mosques.km(d), tr("المسافة"), nil)
                Rectangle().fill(c.line).frame(width: 1, height: 34)
                stat(Mosques.mins(Mosques.walkS(d)), tr("مشيًا"), "walk")
                Rectangle().fill(c.line).frame(width: 1, height: 34)
                stat(Mosques.mins(Mosques.carS(d)), tr("بالسيارة"), "car")
            }
            .padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 16).fill(c.bg.opacity(0.55)))
            if !adhan.isEmpty {
                HStack(spacing: 6) { SiteIcon(name: "clock", size: 15, color: c.gold); Text(adhan).font(F.plex(12.5, .medium)).foregroundStyle(c.text) }
            }
            // the way there: in the phone's maps app (Google Maps when it is installed)
            Button {
                if let u = URL(string: "https://www.google.com/maps/search/?api=1&query=\(m.lat),\(m.lng)") { openURL(u) }
            } label: {
                HStack(spacing: 6) { SiteIcon(name: "pin", size: 16, color: c.gold); Text(tr("افتح في الخرائط")).font(F.plex(13, .semibold)).foregroundStyle(c.gold) }
                    .padding(.horizontal, 14).padding(.vertical, 8).overlay(Capsule().stroke(c.gold.opacity(0.55)))
            }.buttonStyle(Press())
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26).fill(LinearGradient(colors: [c.gold.opacity(0.16), c.surface], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(c.gold.opacity(0.45)))
    }
    private func stat(_ v: String, _ l: String, _ icon: String?) -> some View {
        VStack(spacing: 3) {
            Text(v).font(F.plex(17, .bold)).foregroundStyle(c.text)
            HStack(spacing: 3) { if let icon { SiteIcon(name: icon, size: 13, color: c.muted) }; Text(l).font(F.plex(11)).foregroundStyle(c.muted) }
        }.frame(maxWidth: .infinity)
    }
}

/// One of the others: its place in the order, the name, where it is, the times, and a bar for how far it is.
private struct MosqueRow: View {
    let m: Mosque; let n: Int; let far: Double
    @ObservedObject private var mq = Mosques.shared
    @Environment(\.pal) private var c
    var body: some View {
        let d = mq.dist(m)
        HStack(spacing: 12) {
            Text(n.ar).font(F.plex(14, .bold)).foregroundStyle(c.gold)
                .frame(width: 38, height: 44)
                .background(UnevenRoundedRectangle(topLeadingRadius: 19, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 19).stroke(c.gold.opacity(0.5)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(m.title).font(F.plex(14.5, .bold)).foregroundStyle(c.text).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(Mosques.km(d)).font(F.plex(13.5, .bold)).foregroundStyle(c.gold2)
                }
                if !m.place.isEmpty { Text(m.place).font(F.plex(11.5)).foregroundStyle(c.muted).lineLimit(1) }
                HStack(spacing: 10) {
                    HStack(spacing: 3) { SiteIcon(name: "walk", size: 13, color: c.muted); Text(Mosques.mins(Mosques.walkS(d))) }
                    HStack(spacing: 3) { SiteIcon(name: "car", size: 13, color: c.muted); Text(Mosques.mins(Mosques.carS(d))) }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(c.line)
                            Capsule().fill(c.gold.opacity(0.7)).frame(width: max(6, g.size.width * min(1, d / far)))
                        }
                    }.frame(height: 4)
                }.font(F.plex(11.5)).foregroundStyle(c.muted)
            }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 18).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.lineSoft))
    }
}

/// Home: «أقرب مسجد · مسجد … · ٥ د مشيًا» under the date — only when the place is already allowed (it never asks from here).
struct NearestMosquePill: View {
    @StateObject private var mq = Mosques.shared
    @Environment(\.pal) private var c
    private var ui: UIState { UIState.shared! }
    var body: some View {
        Group {
            if let n = mq.near?.min(by: { mq.dist($0) < mq.dist($1) }), mq.pos != nil {
                Button { ui.path.append(.mosques) } label: {
                    HStack(spacing: 7) {
                        SiteIcon(name: "mosque", size: 17, color: c.onGold).frame(width: 26, height: 26).background(Circle().fill(c.gold))
                        Text(tr("أقرب مسجد")).font(F.plex(12.5)).foregroundStyle(c.text)
                        Text(n.title).font(F.plex(12.5, .bold)).foregroundStyle(c.text).lineLimit(1)
                        HStack(spacing: 2) { SiteIcon(name: "walk", size: 15, color: c.muted); Text(Mosques.mins(Mosques.walkS(mq.dist(n)))).font(F.plex(12.5)).foregroundStyle(c.muted) }
                        SiteIcon(name: "chev-l", size: 15, color: c.muted)
                    }.padding(.leading, 5).padding(.trailing, 10).padding(.vertical, 4).background(Capsule().fill(c.text.opacity(0.06))).overlay(Capsule().stroke(c.line))
                }.buttonStyle(Press()).padding(.top, 8)
            }
        }
        .task { if mq.allowed { await mq.locate(ask: false); await mq.loadNear() } }
    }
}
