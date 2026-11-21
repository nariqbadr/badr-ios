import SwiftUI
import MapKit
import CoreLocation
import AVFoundation

/// «بيوت الله»: the mosques around the person (nearest first, with the time on foot and by car), the famous ones, any
/// mosque in the world by name, and the way to one — drawn on the map, every step in the app's language, and the
/// way told inside the app (voice, the next turn, recalculated when the person leaves it). The list and the routes come
/// through the site (OpenStreetMap, cached there), as on Android; Apple Maps fills in when the site can't answer.
struct Mosque: Identifiable, Hashable {
    let id: String, name: String, area: String, lat: Double, lng: Double
    var ar = "", en = "", street = ""
    var coord: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    /// The name in the app's language: Arabic first for Arabic, Urdu and Persian, the English (Latin) name first for the rest;
    /// a place with no name says where it is, and an Arabic name says it is a mosque.
    var title: String {
        let rtl = ["ar", "ur", "fa"].contains(L.code)
        let latin = { (v: String) in !v.isEmpty && v.range(of: "[\\u0600-\\u06FF]", options: .regularExpression) == nil }
        var n = (rtl ? [ar, name, en] : [en, latin(name) ? name : "", name, ar]).first { !$0.isEmpty } ?? ""
        n = n.trimmingCharacters(in: .whitespaces)
        if n.isEmpty || n == "مسجد" {
            let st = street.isEmpty ? (area.components(separatedBy: "،").first ?? "") : street
            return st.isEmpty ? tr("مسجد") : tr("مسجد في {0}", st)
        }
        if L.code == "ar", !latin(n), n.range(of: "مسجد|جامع|مصلى|مصلّى|زاوية", options: .regularExpression) == nil { n = "مسجد " + n }
        return n
    }
    var unnamed: Bool { name.isEmpty && ar.isEmpty && en.isEmpty }
}

/// One step of the way: what to do, where (the turn's place), and how far it runs after it.
struct MqStep: Hashable {
    let type: String, mod: String, road: String, dist: Double, lat: Double, lng: Double
    var raw = ""   // Apple Maps' own wording, when the way came from there
    var text: String { raw.isEmpty ? Mosques.say(type, mod, road) : raw }
    var coord: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}
struct MqRoute {
    let dist: Double, dur: Double, line: [CLLocationCoordinate2D], steps: [MqStep]
    var poly: MKPolyline { MKPolyline(coordinates: line, count: line.count) }
}

@MainActor final class Mosques: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = Mosques()
    @Published var pos: CLLocationCoordinate2D?
    @Published var near: [Mosque]?
    @Published var error = ""
    @Published var saved: [Mosque] = []
    @Published var denied = false
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
        guard let url = u.url, let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
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
    func loadNear(force: Bool = false) async {
        guard let p = pos else { return }
        if !force, near != nil, let a = nearAt, abs(a.latitude - p.latitude) < 0.002, abs(a.longitude - p.longitude) < 0.002 { return }
        var r = items(await get(["do": "mosques_near", "lat": String(format: "%.5f", p.latitude), "lng": String(format: "%.5f", p.longitude)]))
        if r?.isEmpty ?? true {
            // the site can't answer (or has none): Apple Maps' own places
            let a = await apple(near: p); if !a.isEmpty { r = a }
        } else if let rr = r, rr.contains(where: { $0.unnamed }) {
            // a mosque OpenStreetMap has no name for: the name Apple Maps knows at the same place (within 80 m)
            let a = await apple(near: p)
            r = rr.map { m in
                guard m.unnamed, let x = a.min(by: { Self.d(m.coord, $0.coord) < Self.d(m.coord, $1.coord) }), Self.d(m.coord, x.coord) < 80 else { return m }
                return Mosque(id: m.id, name: x.name, area: m.area.isEmpty ? x.area : m.area, lat: m.lat, lng: m.lng, street: m.street)
            }
        }
        error = r == nil ? tr("تعذّر جلب المساجد الآن، حاول بعد قليل") : ""
        near = (r ?? []).sorted { dist($0) < dist($1) }; nearAt = p
    }
    func search(_ q: String) async -> [Mosque] {
        if let r = items(await get(["do": "mosques_search", "q": q])), !r.isEmpty { return r }
        let mq = q.range(of: "مسجد|جامع|mosque|masjid|cami", options: [.regularExpression, .caseInsensitive]) != nil ? q : tr("مسجد") + " " + q
        return await appleSearch(mq, region: nil)
    }
    /// Apple Maps: mosques within ~3 km (two wordings, merged)
    private func apple(near p: CLLocationCoordinate2D) async -> [Mosque] {
        let reg = MKCoordinateRegion(center: p, latitudinalMeters: 6000, longitudinalMeters: 6000)
        var out: [Mosque] = []
        for w in ["mosque", "مسجد"] { out += await appleSearch(w, region: reg) }
        var seen = Set<String>()
        return out.filter { seen.insert("\(Int($0.lat * 5000)):\(Int($0.lng * 5000))").inserted && dist($0) <= 3500 }
    }
    private func appleSearch(_ q: String, region: MKCoordinateRegion?) async -> [Mosque] {
        let r = MKLocalSearch.Request(); r.naturalLanguageQuery = q; r.resultTypes = .pointOfInterest
        if let region { r.region = region }
        guard let res = try? await MKLocalSearch(request: r).start() else { return [] }
        return res.mapItems.compactMap { it in
            let c = it.placemark.coordinate
            let area = [it.placemark.thoroughfare, it.placemark.subLocality ?? it.placemark.locality].compactMap { $0 }.joined(separator: tr("، "))
            return Mosque(id: "a\(Int(c.latitude * 1e5)):\(Int(c.longitude * 1e5))", name: it.name ?? "", area: area.isEmpty ? (it.placemark.country ?? "") : area,
                          lat: c.latitude, lng: c.longitude, street: it.placemark.thoroughfare ?? "")
        }
    }

    // ------------------------------------------------------------------ the way
    /// The way from the site (OpenStreetMap's foot and car networks), or from Apple Maps when the site can't answer.
    func route(from p: CLLocationCoordinate2D, to m: Mosque, foot: Bool) async -> MqRoute? {
        let j = await get(["do": "mosque_route", "flat": String(format: "%.5f", p.latitude), "flng": String(format: "%.5f", p.longitude),
                           "tlat": String(format: "%.6f", m.lat), "tlng": String(format: "%.6f", m.lng), "mode": foot ? "foot" : "car"])
        if let j, j["ok"] as? Bool == true, let line = j["line"] as? [[NSNumber]], let st = j["steps"] as? [[String: Any]], line.count > 1, !st.isEmpty {
            let num = { (x: [String: Any], k: String) in (x[k] as? NSNumber)?.doubleValue ?? 0 }
            return MqRoute(dist: num(j, "dist"), dur: num(j, "dur"),
                           line: line.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[1].doubleValue, longitude: $0[0].doubleValue) : nil },
                           steps: st.map { x in MqStep(type: x["type"] as? String ?? "", mod: x["mod"] as? String ?? "", road: x["road"] as? String ?? "", dist: num(x, "dist"), lat: num(x, "lat"), lng: num(x, "lng")) })
        }
        let r = MKDirections.Request()
        r.source = MKMapItem(placemark: MKPlacemark(coordinate: p)); r.destination = MKMapItem(placemark: MKPlacemark(coordinate: m.coord))
        r.transportType = foot ? .walking : .automobile
        guard let a = try? await MKDirections(request: r).calculate().routes.first else { return nil }
        let pts = a.polyline.points(), line = (0..<a.polyline.pointCount).map { pts[$0].coordinate }
        var steps: [MqStep] = a.steps.enumerated().map { i, s in
            let c = s.polyline.pointCount > 0 ? s.polyline.points()[0].coordinate : p
            return MqStep(type: i == 0 ? "depart" : "", mod: "", road: "", dist: s.distance, lat: c.latitude, lng: c.longitude, raw: s.instructions)
        }
        if steps.isEmpty { steps.append(MqStep(type: "depart", mod: "", road: "", dist: a.distance, lat: p.latitude, lng: p.longitude)) }
        steps.append(MqStep(type: "arrive", mod: "", road: "", dist: 0, lat: m.lat, lng: m.lng))
        return MqRoute(dist: a.distance, dur: a.expectedTravelTime, line: line, steps: steps)
    }
    /// What to do at a step, in the app's language.
    nonisolated static func say(_ type: String, _ mod: String, _ road: String) -> String {
        let to = road.isEmpty ? "" : tr(" إلى {0}", road)
        switch type {
        case "depart": return road.isEmpty ? tr("انطلق") : tr("انطلق عبر {0}", road)
        case "arrive": return tr("وصلت إلى المسجد")
        case "roundabout", "rotary": return tr("في الدوّار خذ المخرج") + to
        default:
            let t: [String: String] = ["uturn": tr("استدر للخلف"), "sharp right": tr("انعطف يمينًا بحدّة"), "right": tr("انعطف يمينًا"), "slight right": tr("اتجه قليلًا إلى اليمين"),
                                       "straight": tr("تابع مباشرة"), "slight left": tr("اتجه قليلًا إلى اليسار"), "left": tr("انعطف يسارًا"), "sharp left": tr("انعطف يسارًا بحدّة")]
            return (t[mod] ?? tr("تابع")) + to
        }
    }
    /// the arrow's turn for a step
    nonisolated static func deg(_ mod: String) -> Double {
        let t: [String: Double] = ["uturn": 180, "sharp right": 135, "right": 90, "slight right": 45, "slight left": -45, "left": -90, "sharp left": -135]
        return t[mod] ?? 0
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

/// The map in the app's colours, with a soft graticule and the place under the centre in degrees.
/// It frames the pins once (when what it shows changes), so moving it by hand stays smooth.
@available(iOS 17.0, *)
private struct MosqueMap: View {
    let pins: [Mosque]; let me: CLLocationCoordinate2D?; let line: MKPolyline?; let sel: String?
    var follow = false
    var onPin: (Mosque) -> Void = { _ in }
    @Environment(\.pal) private var c
    @State private var cam: MapCameraPosition = .automatic
    @State private var center: CLLocationCoordinate2D?
    private var key: String { "\(pins.prefix(30).map(\.id).joined(separator: ",")):\(line?.pointCount ?? 0):\(me == nil ? 0 : 1)" }
    var body: some View {
        Map(position: $cam) {
            if follow { UserAnnotation() } else if let me { Annotation("", coordinate: me) { MePin() } }
            ForEach(Array(pins.prefix(40))) { m in
                Annotation(m.title, coordinate: m.coord) { MosquePin(big: m.id == sel) { onPin(m) } }.annotationTitles(.hidden)
            }
            if let line { routeLine(line) }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .environment(\.colorScheme, c.dark ? .dark : .light)
        .onMapCameraChange(frequency: .onEnd) { center = $0.region.center }
        .overlay { MapFinish().allowsHitTesting(false) }
        .overlay(alignment: .topLeading) { if !follow, let center { Readout(p: center) } }
        .onAppear { fit() }
        .onChange(of: key) { _ in if !follow { fit() } }
    }
    @MapContentBuilder private func routeLine(_ line: MKPolyline) -> some MapContent {
        MapPolyline(line).stroke(MosquePin.blue.opacity(0.3), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
        MapPolyline(line).stroke(MosquePin.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
    }
    private func fit() {
        if follow {
            let fb: MapCameraPosition = me.map { .camera(MapCamera(centerCoordinate: $0, distance: 700, pitch: 40)) } ?? .automatic
            cam = .userLocation(followsHeading: true, fallback: fb); return
        }
        if let line, line.pointCount > 1 { let r = line.boundingMapRect; cam = .rect(r.insetBy(dx: -r.width * 0.25 - 200, dy: -r.height * 0.25 - 200)); return }
        // open at the person and the nearest few (never the whole world)
        var pts = pins.prefix(8).map(\.coord); if let me { pts.append(me) }
        guard !pts.isEmpty else { return }
        var r = MKMapRect.null
        for p in pts { let mp = MKMapPoint(p); r = r.union(MKMapRect(x: mp.x, y: mp.y, width: 1, height: 1)) }
        cam = .rect(r.insetBy(dx: -max(r.width * 0.2, 600), dy: -max(r.height * 0.3, 900)))
    }
}

/// a graticule in the theme's gold and a vignette
private struct MapFinish: View {
    @Environment(\.pal) private var c
    var body: some View {
        ZStack {
            Canvas { ctx, sz in
                var p = Path(); var x: CGFloat = 0; while x < sz.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: sz.height)); x += 48 }
                var y: CGFloat = 0; while y < sz.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: sz.width, y: y)); y += 48 }
                ctx.stroke(p, with: .color(c.gold.opacity(0.09)), lineWidth: 1)
            }
            RadialGradient(colors: [.clear, c.bg.opacity(0.45)], center: .center, startRadius: 120, endRadius: 420)
        }.drawingGroup()
    }
}
private struct Readout: View {
    let p: CLLocationCoordinate2D
    @Environment(\.pal) private var c
    var body: some View {
        Text(String(format: "%.4f° %@  ·  %.4f° %@", abs(p.latitude), p.latitude >= 0 ? "N" : "S", abs(p.longitude), p.longitude >= 0 ? "E" : "W"))
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced)).foregroundStyle(c.gold)
            .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(c.bg.opacity(0.82))).overlay(Capsule().stroke(c.gold.opacity(0.35)))
            .environment(\.layoutDirection, .leftToRight).padding(10)
    }
}

private struct MePin: View {
    var body: some View {
        ZStack { Circle().fill(Color.blue.opacity(0.2)).frame(width: 36, height: 36); Circle().fill(Color.white).frame(width: 18, height: 18); Circle().fill(MosquePin.blue).frame(width: 12, height: 12) }
    }
}
private struct MosquePin: View {
    static let blue = Color(red: 0.3, green: 0.62, blue: 1)
    let big: Bool; let tap: () -> Void
    @Environment(\.pal) private var c
    var body: some View {
        let s: CGFloat = big ? 42 : 32
        Button(action: tap) {
            SiteIcon(name: "mosque", size: s * 0.62, color: c.bg).frame(width: s, height: s).background(Circle().fill(c.text)).overlay(Circle().stroke(c.bg, lineWidth: 3)).shadow(radius: 4, y: 2)
        }.buttonStyle(.plain)
    }
}

@available(iOS 17.0, *)
struct MosquesView: View {
    @StateObject private var mq = Mosques.shared
    @Environment(\.pal) private var c
    @State private var tab = 0
    @State private var q = ""
    @State private var results: [Mosque]?
    @State private var sel: Mosque?
    @State private var busy = false
    private var list: [Mosque] {
        let src = results ?? (tab == 1 ? Mosques.famous : tab == 2 ? mq.saved : mq.near ?? [])
        return tab == 0 && results == nil ? src.sorted { mq.dist($0) < mq.dist($1) } : src
    }
    var body: some View {
        VStack(spacing: 0) {
            map.frame(height: 320).clipped()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    searchBox
                    filters
                    content
                }
                .padding(16).padding(.bottom, 20)
            }
            .background(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24).fill(c.bg))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24).stroke(c.line))
            .padding(.top, -22)
        }
        .background(c.bg.ignoresSafeArea())
        .environment(\.layoutDirection, L.dir)
        .navigationDestination(item: $sel) { MosqueDetailView(m: $0) }
        .task { busy = true; await mq.locate(ask: true); await mq.loadNear(); busy = false }
        .task(id: q) {
            let t = q.trimmingCharacters(in: .whitespaces)
            guard t.count >= 2 else { results = nil; return }
            try? await Task.sleep(nanoseconds: 600_000_000); if Task.isCancelled { return }
            results = await mq.search(t)
        }
    }
    @ViewBuilder private var map: some View {
        if mq.pos == nil && results == nil && tab == 0 {
            // until the place is known: the frame alone (no world map that then jumps)
            ZStack { c.surface; MapFinish(); SiteIcon(name: "locate", size: 30, color: c.muted) }
        } else {
            MosqueMap(pins: list, me: mq.pos, line: nil, sel: nil) { sel = $0 }
                .overlay(alignment: .bottomTrailing) {
                    Button { Task { busy = true; await mq.locate(ask: true); await mq.loadNear(force: true); busy = false } } label: {
                        SiteIcon(name: "locate", size: 20, color: c.text).frame(width: 42, height: 42).background(Circle().fill(c.bg.opacity(0.9))).overlay(Circle().stroke(c.line))
                    }.buttonStyle(Press()).padding(.trailing, 12).padding(.bottom, 34)
                }
        }
    }
    private var searchBox: some View {
        HStack(spacing: 8) {
            SiteIcon(name: "search", size: 18, color: c.muted)
            TextField(tr("ابحث عن أي مسجد في العالم…"), text: $q).font(F.plex(14)).foregroundStyle(c.text).submitLabel(.search)
        }.padding(.horizontal, 14).frame(height: 46).background(RoundedRectangle(cornerRadius: 16).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 16).stroke(c.line))
    }
    @ViewBuilder private var filters: some View {
        if results != nil {
            HStack { Text(tr("نتائج البحث")).font(F.plex(12.5)).foregroundStyle(c.muted); Spacer(); Button(tr("إلغاء")) { q = "" }.font(F.plex(13, .semibold)).foregroundStyle(c.gold) }
        } else {
            HStack(spacing: 8) {
                Pill(title: tr("القريبة منك"), on: tab == 0, icon: "pin") { tab = 0 }
                Pill(title: tr("المشهورة"), on: tab == 1, icon: "mosque") { tab = 1 }
                Pill(title: tr("المحفوظة"), on: tab == 2, icon: "star") { tab = 2 }
            }
            if tab == 0, let n = mq.near, !n.isEmpty {
                HStack { Text(tr("{0} مسجدًا قريبًا منك", n.count.ar)); Spacer(); Text(tr("الأقرب أولًا")) }.font(F.plex(12)).foregroundStyle(c.muted)
            }
        }
    }
    @ViewBuilder private var content: some View {
        if tab == 0, results == nil, mq.pos == nil, !busy {
            empty(mq.denied ? tr("فعّل الوصول إلى الموقع من الإعدادات لنعرض لك أقرب المساجد") : tr("اسمح بتحديد موقعك لنعرض لك أقرب المساجد"), action: mq.denied ? nil : tr("تحديد موقعي")) {
                Task { busy = true; await mq.locate(ask: true); await mq.loadNear(force: true); busy = false }
            }
        } else if tab == 0, results == nil, mq.near == nil || busy {
            empty(tr("جارٍ البحث عن المساجد القريبة…"))
        } else if list.isEmpty {
            empty(!mq.error.isEmpty && tab == 0 ? mq.error : results != nil ? tr("لم نجد مسجدًا بهذا الاسم") : tab == 2 ? tr("لم تحفظ أي مسجد بعد — اضغط النجمة في صفحة المسجد") : tr("لا توجد مساجد قريبة في نطاق ٣ كم"))
        } else {
            LazyVStack(spacing: 10) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, m in MosqueRow(m: m, first: i == 0 && tab == 0 && results == nil) { sel = m } }
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

private struct MosqueRow: View {
    let m: Mosque; let first: Bool; let tap: () -> Void
    @ObservedObject private var mq = Mosques.shared
    @Environment(\.pal) private var c
    var body: some View {
        let d: Double? = mq.pos == nil ? nil : mq.dist(m)
        Button(action: tap) {
            HStack(spacing: 12) {
                SiteIcon(name: "mosque", size: 28, color: c.text).frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 15).fill(c.text.opacity(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title).font(F.plex(15, .bold)).foregroundStyle(c.text).lineLimit(1)
                    if !m.area.isEmpty { Text(m.area).font(F.plex(11.5)).foregroundStyle(c.muted).lineLimit(1) }
                    if let d, d < 60_000 { times(d) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 6) {
                    if let d { Text(Mosques.km(d)).font(F.plex(14, .bold)).foregroundStyle(c.text) }
                    SiteIcon(name: "nav", size: 17, color: c.onGold).frame(width: 36, height: 36).background(Circle().fill(c.gold))
                }
            }.padding(12).background(RoundedRectangle(cornerRadius: 20).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 20).stroke(c.lineSoft))
        }.buttonStyle(Press(scale: 0.98))
    }
    private func times(_ d: Double) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) { SiteIcon(name: "walk", size: 14, color: c.muted); Text(Mosques.mins(Mosques.walkS(d))) }
            HStack(spacing: 3) { SiteIcon(name: "car", size: 14, color: c.muted); Text(Mosques.mins(Mosques.carS(d))) }
            if first { Text(tr("الأقرب")).foregroundStyle(Color(red: 0.31, green: 0.75, blue: 0.52)) }
        }.font(F.plex(11.5)).foregroundStyle(c.muted).padding(.top, 3)
    }
}

@available(iOS 17.0, *)
/// One mosque: the way on the map (on foot or by car), time, distance, arrival, the next turn and every step;
/// «ابدأ الاتجاهات» starts the directions inside the app.
struct MosqueDetailView: View {
    let m: Mosque
    @StateObject private var mq = Mosques.shared
    @Environment(\.pal) private var c
    @State private var foot = true
    @State private var route: MqRoute?
    @State private var loading = false
    @State private var nav = false
    private var ui: UIState { UIState.shared! }
    var body: some View {
        let d: Double? = mq.pos == nil ? nil : mq.dist(m)
        let far = (d ?? 0) > 300_000
        ScrollView {
            VStack(spacing: 0) {
                MosqueMap(pins: [m], me: mq.pos, line: route?.poly, sel: m.id)
                    .frame(height: 360)
                    .overlay(alignment: .top) { if let r = route, r.steps.count > 1 { NextTurn(st: r.steps[1], dist: r.steps[0].dist).padding(.horizontal, 12).padding(.top, 48) } }
                VStack(alignment: .leading, spacing: 14) {
                    head
                    if far, let d {
                        Text(tr("يبعد عنك {0}", Mosques.km(d))).font(F.plex(14)).foregroundStyle(c.muted)
                    } else {
                        modes
                        stats(d)
                        if loading { Text(tr("جارٍ رسم الطريق…")).font(F.plex(12.5)).foregroundStyle(c.muted).frame(maxWidth: .infinity) }
                    }
                    actions
                    if let r = route, r.steps.count > 1 { StepsList(steps: r.steps) }
                }
                .padding(18).padding(.bottom, 20)
                .background(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26).fill(c.bg))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26).stroke(c.line))
                .padding(.top, -24)
            }
        }
        .background(c.bg.ignoresSafeArea())
        .environment(\.layoutDirection, L.dir)
        .navigationTitle(m.title)
        .task(id: foot) { await load(far: far) }
        .fullScreenCover(isPresented: $nav) { if let r = route { MosqueNavView(m: m, route0: r, foot: foot) { route = $0 } } }
    }
    private var head: some View {
        let saved = mq.saved.contains { $0.id == m.id }
        let sub = [m.area, Mosques.nextAdhan()].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title).font(F.plex(19, .bold)).foregroundStyle(c.text)
                if !sub.isEmpty { Text(sub).font(F.plex(12.5)).foregroundStyle(c.muted) }
            }
            Spacer()
            Chip(text: nil, icon: saved ? "star-f" : "star", on: saved) { mq.toggle(m); ui.say(saved ? tr("أُزيل من المحفوظة") : tr("حُفظ المسجد")) }
        }
    }
    private var actions: some View {
        HStack(spacing: 10) {
            GoldButton(title: tr("ابدأ الاتجاهات"), icon: "nav") { if route != nil { nav = true } }.frame(maxWidth: .infinity).opacity(route == nil ? 0.5 : 1)
            Chip(text: nil, icon: "share") { share("\(m.title)\(m.area.isEmpty ? "" : " — " + m.area)\nhttps://maps.apple.com/?ll=\(m.lat),\(m.lng)") }
        }
    }
    private var modes: some View {
        HStack(spacing: 6) {
            ForEach([true, false], id: \.self) { f in
                Button { foot = f } label: {
                    HStack(spacing: 6) { SiteIcon(name: f ? "walk" : "car", size: 18, color: foot == f ? c.onGold : c.text); Text(f ? tr("مشيًا") : tr("بالسيارة")).font(F.plex(14, .semibold)).foregroundStyle(foot == f ? c.onGold : c.text) }
                        .frame(maxWidth: .infinity).frame(height: 40).background(Capsule().fill(foot == f ? c.gold : .clear))
                }.buttonStyle(.plain)
            }
        }.padding(4).background(Capsule().fill(c.surface)).overlay(Capsule().stroke(c.lineSoft))
    }
    private func stats(_ d: Double?) -> some View {
        let dur: Double? = route?.dur ?? d.map { foot ? Mosques.walkS($0) : Mosques.carS($0) }
        let dist: Double? = route?.dist ?? d
        return HStack {
            stat(dur.map { Mosques.mins($0) } ?? "—", tr("المدة"))
            stat(dist.map { Mosques.km($0) } ?? "—", tr("المسافة"))
            stat(dur.map { Mosques.clock($0) } ?? "—", tr("الوصول"))
        }
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) { Text(v).font(F.plex(19, .bold)).foregroundStyle(c.text); Text(l).font(F.plex(11)).foregroundStyle(c.muted) }.frame(maxWidth: .infinity)
    }
    private func load(far: Bool) async {
        guard let p = mq.pos, !far else { route = nil; return }
        loading = true
        route = await mq.route(from: p, to: m, foot: foot)
        loading = false
    }
}

private struct NextTurn: View {
    let st: MqStep; let dist: Double
    @Environment(\.pal) private var c
    var body: some View {
        HStack(spacing: 12) {
            SiteIcon(name: "nav", size: 22, color: c.onGold).rotationEffect(.degrees(Mosques.deg(st.mod))).frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 14).fill(c.gold))
            VStack(alignment: .leading, spacing: 1) { Text(Mosques.km(dist)).font(F.plex(19, .bold)).foregroundStyle(c.text); Text(st.text).font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(2) }
            Spacer(minLength: 0)
        }.padding(12).background(RoundedRectangle(cornerRadius: 20).fill(c.bg)).overlay(RoundedRectangle(cornerRadius: 20).stroke(c.line)).shadow(radius: 10, y: 4)
    }
}

private struct StepsList: View {
    let steps: [MqStep]
    @Environment(\.pal) private var c
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("خطوات الطريق")).font(F.plex(14, .bold)).foregroundStyle(c.text)
            ForEach(steps.indices, id: \.self) { i in row(steps[i]) }
        }
    }
    private func row(_ s: MqStep) -> some View {
        let end = s.type == "arrive"
        return HStack(alignment: .top, spacing: 10) {
            SiteIcon(name: end ? "mosque" : "nav", size: 16, color: c.gold).rotationEffect(.degrees(end ? 0 : Mosques.deg(s.mod))).frame(width: 22)
            Text(s.text).font(F.plex(13.5)).foregroundStyle(c.text).frame(maxWidth: .infinity, alignment: .leading)
            if s.dist > 0 { Text(Mosques.km(s.dist)).font(F.plex(11.5)).foregroundStyle(c.muted) }
        }
    }
}

/// The way told inside the app: it follows the person, says each turn before it comes and again at it, draws the way
/// again from where they are when they leave it, and says when they have arrived. The screen stays on meanwhile.
@available(iOS 17.0, *)
struct MosqueNavView: View {
    let m: Mosque; let route0: MqRoute; let foot: Bool; var onRoute: (MqRoute) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pal) private var c
    @StateObject private var mq = Mosques.shared
    @State private var route: MqRoute?
    @State private var step = 1
    @State private var mute = false
    @State private var arrived = false
    @State private var said = Set<String>()
    @State private var off = 0
    @State private var busy = false
    private static let voice = AVSpeechSynthesizer()
    private var r: MqRoute { route ?? route0 }
    private var st: MqStep { r.steps[safe: step] ?? r.steps[r.steps.count - 1] }
    private var toTurn: Double { mq.pos.map { Mosques.d($0, st.coord) } ?? st.dist }
    private var left: Double {
        let rest = r.steps.dropFirst(step).dropLast().reduce(0.0) { $0 + $1.dist }
        return max(toTurn + rest, mq.pos.map { Mosques.d($0, m.coord) } ?? 0)
    }
    var body: some View {
        ZStack {
            MosqueMap(pins: [m], me: mq.pos, line: r.poly, sel: m.id, follow: true).ignoresSafeArea()
            VStack { banner; Spacer(); bottom }
        }
        .environment(\.layoutDirection, L.dir)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            step = min(1, route0.steps.count - 1)
            speak(tr("لنبدأ — الطريق إلى {0}", m.title) + ". " + (route0.steps[safe: step]?.text ?? ""))
            mq.follow(true) { fix($0) }
        }
        .onDisappear { mq.follow(false); Self.voice.stopSpeaking(at: .immediate); UIApplication.shared.isIdleTimerDisabled = false }
        .task(id: arrived) { if arrived { try? await Task.sleep(nanoseconds: 6_000_000_000); dismiss() } }
    }
    private var banner: some View {
        HStack(spacing: 14) {
            SiteIcon(name: arrived ? "mosque" : "nav", size: 30, color: c.onGold).rotationEffect(.degrees(arrived ? 0 : Mosques.deg(st.mod)))
                .frame(width: 56, height: 56).background(RoundedRectangle(cornerRadius: 18).fill(c.gold))
            VStack(alignment: .leading, spacing: 2) {
                if !arrived { Text(Mosques.km(toTurn)).font(F.plex(24, .bold)).foregroundStyle(c.text) }
                Text(arrived ? tr("وصلت إلى المسجد") : st.text).font(F.plex(arrived ? 20 : 15, arrived ? .bold : .regular)).foregroundStyle(arrived ? c.text : c.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(14).background(RoundedRectangle(cornerRadius: 22).fill(c.bg)).overlay(RoundedRectangle(cornerRadius: 22).stroke(c.line)).shadow(radius: 12, y: 4)
            .padding(12)
    }
    private var bottom: some View {
        let secs = left / (foot ? 1.3 : 7.0)
        return HStack {
            navBtn("close") { dismiss() }
            VStack(spacing: 2) {
                Text(Mosques.mins(secs)).font(F.plex(22, .bold)).foregroundStyle(Color(red: 0.31, green: 0.75, blue: 0.52))
                Text(Mosques.km(left) + " · " + Mosques.clock(secs)).font(F.plex(12.5)).foregroundStyle(c.muted)
            }.frame(maxWidth: .infinity)
            navBtn(mute ? "mute" : "volume") { mute.toggle(); if mute { Self.voice.stopSpeaking(at: .immediate) } }
        }.padding(.horizontal, 16).padding(.vertical, 14)
            .background(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24).fill(c.bg).ignoresSafeArea(edges: .bottom))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24).stroke(c.line))
    }
    private func navBtn(_ icon: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) { SiteIcon(name: icon, size: 22, color: c.text).frame(width: 48, height: 48).background(Circle().fill(c.surface)).overlay(Circle().stroke(c.line)) }.buttonStyle(Press())
    }
    private func speak(_ t: String) {
        guard !mute, !t.isEmpty else { return }
        let u = AVSpeechUtterance(string: t)
        u.voice = AVSpeechSynthesisVoice(language: L.locale.identifier) ?? AVSpeechSynthesisVoice(language: L.code)
        Self.voice.stopSpeaking(at: .immediate); Self.voice.speak(u)
    }
    private func fix(_ l: CLLocation) {
        guard !arrived else { return }
        let p = l.coordinate, r = self.r
        if Mosques.d(p, m.coord) < 25 { arrived = true; speak(tr("وصلت إلى المسجد") + ". " + tr("تقبّل الله منك")); return }
        // off the way for two fixes: drawn again from here
        let near = zip(r.line, r.line.dropFirst()).map { seg(p, $0.0, $0.1) }.min() ?? 0
        if near > (foot ? 40 : 70) {
            off += 1
            if off >= 2, !busy {
                busy = true; speak(tr("جارٍ إعادة حساب الطريق"))
                Task {
                    if let n = await mq.route(from: p, to: m, foot: foot) { route = n; onRoute(n); step = min(1, n.steps.count - 1); said.removeAll() }
                    busy = false; off = 0
                }
            }
        } else { off = 0 }
        guard let s = r.steps[safe: step] else { return }
        let d = Mosques.d(p, s.coord), close = foot ? 15.0 : 30.0
        if d < close, step < r.steps.count - 1 { step += 1; return }
        if d < (foot ? 60 : 250), said.insert("\(step)-a").inserted { speak(tr("بعد {0}", Mosques.km(d)) + tr("، ") + s.text) }
        if d < close * 2, said.insert("\(step)-b").inserted { speak(s.text + " " + tr("الآن")) }
    }
    /// metres from a point to a segment (flat enough at street scale)
    private func seg(_ p: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let kx = cos(p.latitude * .pi / 180) * 111_320.0, ky = 110_540.0
        let ax = (a.longitude - p.longitude) * kx, ay = (a.latitude - p.latitude) * ky
        let dx = (b.longitude - a.longitude) * kx, dy = (b.latitude - a.latitude) * ky
        let l2 = dx * dx + dy * dy
        let t = l2 == 0 ? 0 : max(0, min(1, -(ax * dx + ay * dy) / l2))
        let x = ax + t * dx, y = ay + t * dy
        return (x * x + y * y).squareRoot()
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
