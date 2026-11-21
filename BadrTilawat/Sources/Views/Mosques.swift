import SwiftUI
import MapKit
import CoreLocation

/// «بيوت الله»: the mosques around the person (nearest first, with the time on foot and by car), the famous ones, any
/// mosque in the world by name, and the way to one — drawn with Apple Maps, the steps in Arabic, and «ابدأ الاتجاهات»
/// opening Maps for the turn-by-turn. The list comes through the site (OpenStreetMap, cached there), as on Android.
struct Mosque: Identifiable, Hashable { let id: String, name: String, area: String, lat: Double, lng: Double
    var coord: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) } }

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
            return Mosque(id: id, name: n, area: d["area"] as? String ?? "", lat: la, lng: lo)
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
        guard allowed else { return }
        let l: CLLocation? = await withCheckedContinuation { k in cont?.resume(returning: nil); cont = k; lm.requestLocation() }
        if let l { pos = l.coordinate; UserDefaults.standard.set([l.coordinate.latitude, l.coordinate.longitude], forKey: "mqPos") }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { Task { @MainActor in cont?.resume(returning: locations.last); cont = nil } }
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
            let n = (x["name"] as? String) ?? ""
            return Mosque(id: id, name: n.isEmpty ? tr("مسجد") : n, area: x["area"] as? String ?? "", lat: la, lng: lo)
        }
    }
    func loadNear(force: Bool = false) async {
        guard let p = pos else { return }
        if !force, near != nil, let a = nearAt, abs(a.latitude - p.latitude) < 0.002, abs(a.longitude - p.longitude) < 0.002 { return }
        var r = items(await get(["do": "mosques_near", "lat": String(format: "%.5f", p.latitude), "lng": String(format: "%.5f", p.longitude)]))
        // the site can't answer (or has none): Apple Maps' own places
        if r?.isEmpty ?? true { let a = await apple(near: p); if !a.isEmpty { r = a } }
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
            return Mosque(id: "a\(Int(c.latitude * 1e5)):\(Int(c.longitude * 1e5))", name: it.name ?? tr("مسجد"), area: area.isEmpty ? (it.placemark.country ?? "") : area, lat: c.latitude, lng: c.longitude)
        }
    }

    func dist(_ m: Mosque) -> Double { guard let p = pos else { return 0 }; return CLLocation(latitude: p.latitude, longitude: p.longitude).distance(from: CLLocation(latitude: m.lat, longitude: m.lng)) }
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
    func toggle(_ m: Mosque) {
        if saved.contains(where: { $0.id == m.id }) { saved.removeAll { $0.id == m.id } } else { saved.insert(m, at: 0) }
        saved = Array(saved.prefix(50))
        UserDefaults.standard.set(saved.map { ["id": $0.id, "name": $0.name, "area": $0.area, "lat": $0.lat, "lng": $0.lng] as [String: Any] }, forKey: "mqSaved")
    }
    /// «يُؤذَّن للعصر بعد ٢٤ د» when the next adhan is within three hours
    static func nextAdhan() -> String {
        guard let n = Prayers.shared.next() else { return "" }
        let left = n.time.timeIntervalSinceNow
        return left > 0 && left < 10800 ? tr("يُؤذَّن ل{0} بعد {1}", n.name, mins(left)) : ""
    }
}

/// The page's opening: ﴿فِي بُيُوتٍ أَذِنَ اللَّهُ أَن تُرْفَعَ﴾ — النور ٣٦ (the mushaf's own text as soon as it is at hand).
private struct MosquesAyah: View {
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    @State private var t = "فِى بُيُوتٍ أَذِنَ ٱللَّهُ أَن تُرْفَعَ وَيُذْكَرَ فِيهَا ٱسْمُهُۥ يُسَبِّحُ لَهُۥ فِيهَا بِٱلْغُدُوِّ وَٱلْءَاصَالِ"
    var body: some View {
        VStack(spacing: 2) {
            Ornament(width: 120)
            Text(orn(t)).font(F.quran(22)).foregroundStyle(c.text).lineSpacing(14).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Text(tr("سورة النور · الآية {0}", 36.ar)).font(F.plex(12, .medium)).foregroundStyle(c.gold)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(LinearGradient(colors: [c.gold.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom))
        .task { if let x = await repo.surahText(24)?[safe: 35], !x.isEmpty { t = x } }
    }
}

/// The map in the app's colours, with a soft graticule and the place under the centre in degrees.
@available(iOS 17.0, *)
private struct MosqueMap: View {
    let pins: [Mosque]; let me: CLLocationCoordinate2D?; let line: MKPolyline?; let sel: String?; var onPin: (Mosque) -> Void = { _ in }
    @Environment(\.pal) private var c
    @State private var cam: MapCameraPosition = .automatic
    @State private var center = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    var body: some View {
        Map(position: $cam) {
            if let me { Annotation("", coordinate: me) { MePin() } }
            ForEach(Array(pins.prefix(40))) { m in
                Annotation(m.name, coordinate: m.coord) { MosquePin(big: m.id == sel) { onPin(m) } }.annotationTitles(.hidden)
            }
            if let line { routeLine(line) }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .environment(\.colorScheme, c.dark ? .dark : .light)
        .onMapCameraChange(frequency: .continuous) { center = $0.region.center }
        .overlay {
            // the finish: a graticule in the theme's gold and a vignette
            Canvas { ctx, sz in
                var p = Path(); var x: CGFloat = 0; while x < sz.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: sz.height)); x += 48 }
                var y: CGFloat = 0; while y < sz.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: sz.width, y: y)); y += 48 }
                ctx.stroke(p, with: .color(c.gold.opacity(0.09)), lineWidth: 1)
            }.allowsHitTesting(false)
            RadialGradient(colors: [.clear, c.bg.opacity(0.5)], center: .center, startRadius: 120, endRadius: 420).allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            Text(String(format: "%.4f° %@  ·  %.4f° %@", abs(center.latitude), center.latitude >= 0 ? "N" : "S", abs(center.longitude), center.longitude >= 0 ? "E" : "W"))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced)).foregroundStyle(c.gold)
                .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(c.bg.opacity(0.82))).overlay(Capsule().stroke(c.gold.opacity(0.35)))
                .environment(\.layoutDirection, .leftToRight).padding(10)
        }
        .onAppear { fit() }
        .onChange(of: pins.map(\.id)) { _ in fit() }
        .onChange(of: line?.pointCount ?? 0) { _ in fit() }
    }
    @MapContentBuilder private func routeLine(_ line: MKPolyline) -> some MapContent {
        MapPolyline(line).stroke(MosquePin.blue.opacity(0.3), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
        MapPolyline(line).stroke(MosquePin.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
    }
    private func fit() {
        var pts = pins.prefix(30).map(\.coord); if let me { pts.append(me) }
        if let line, line.pointCount > 1 { cam = .rect(line.boundingMapRect.insetBy(dx: -line.boundingMapRect.width * 0.25 - 200, dy: -line.boundingMapRect.height * 0.25 - 200)); return }
        guard !pts.isEmpty else { cam = .automatic; return }
        var r = MKMapRect.null
        for p in pts { let mp = MKMapPoint(p); r = r.union(MKMapRect(x: mp.x, y: mp.y, width: 1, height: 1)) }
        cam = .rect(r.insetBy(dx: -max(r.width * 0.2, 600), dy: -max(r.height * 0.3, 900)))
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
        ScrollView {
            VStack(spacing: 0) {
                MosquesAyah()
                MosqueMap(pins: list, me: mq.pos, line: nil, sel: nil) { sel = $0 }
                    .frame(height: 260)
                    .overlay(alignment: .bottomTrailing) {
                        Button { Task { busy = true; await mq.locate(ask: true); await mq.loadNear(force: true); busy = false } } label: {
                            SiteIcon(name: "locate", size: 20, color: c.text).frame(width: 42, height: 42).background(Circle().fill(c.bg.opacity(0.9))).overlay(Circle().stroke(c.line))
                        }.buttonStyle(Press()).padding(.trailing, 12).padding(.bottom, 34)
                    }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        SiteIcon(name: "search", size: 18, color: c.muted)
                        TextField(tr("ابحث عن أي مسجد في العالم…"), text: $q).font(F.plex(14)).foregroundStyle(c.text).submitLabel(.search)
                    }.padding(.horizontal, 14).frame(height: 46).background(RoundedRectangle(cornerRadius: 16).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 16).stroke(c.line))
                    if results != nil {
                        HStack { Text(tr("نتائج البحث")).font(F.plex(12.5)).foregroundStyle(c.muted); Spacer(); Button(tr("إلغاء")) { q = "" }.font(F.plex(13, .semibold)).foregroundStyle(c.gold) }
                    } else {
                        HStack(spacing: 8) {
                            Pill(title: tr("القريبة منك"), on: tab == 0, icon: "pin") { tab = 0 }
                            Pill(title: tr("المشهورة"), on: tab == 1, icon: "mosque") { tab = 1 }
                            Pill(title: tr("المحفوظة"), on: tab == 2, icon: "star") { tab = 2 }
                        }
                    }
                    if tab == 0, results == nil, let n = mq.near, !n.isEmpty {
                        HStack { Text(tr("{0} مسجدًا قريبًا منك", n.count.ar)); Spacer(); Text(tr("الأقرب أولًا")) }.font(F.plex(12)).foregroundStyle(c.muted)
                    }
                    if tab == 0, results == nil, mq.pos == nil, !busy {
                        empty(mq.denied ? tr("فعّل الوصول إلى الموقع من الإعدادات لنعرض لك أقرب المساجد") : tr("اسمح بتحديد موقعك لنعرض لك أقرب المساجد"), action: mq.denied ? nil : tr("تحديد موقعي")) {
                            Task { busy = true; await mq.locate(ask: true); await mq.loadNear(force: true); busy = false }
                        }
                    } else if tab == 0, results == nil, mq.near == nil || busy {
                        empty(tr("جارٍ البحث عن المساجد القريبة…"))
                    } else if list.isEmpty {
                        empty(!mq.error.isEmpty && tab == 0 ? mq.error : results != nil ? tr("لم نجد مسجدًا بهذا الاسم") : tab == 2 ? tr("لم تحفظ أي مسجد بعد — اضغط النجمة في صفحة المسجد") : tr("لا توجد مساجد قريبة في نطاق ٣ كم"))
                    } else {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, m in row(m, first: i == 0 && tab == 0 && results == nil) }
                    }
                }
                .padding(16).padding(.bottom, 20)
                .background(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24).fill(c.bg))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24).stroke(c.line))
                .padding(.top, -22)
            }
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
    @ViewBuilder private func empty(_ t: String, action: String? = nil, _ f: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 12) {
            SiteIcon(name: "mosque", size: 34, color: c.muted)
            Text(t).font(F.plex(14)).foregroundStyle(c.muted).multilineTextAlignment(.center)
            if let action { GoldButton(title: action, icon: "locate", action: f) }
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }
    private func row(_ m: Mosque, first: Bool) -> some View {
        let d: Double? = mq.pos == nil ? nil : mq.dist(m)
        return Button { sel = m } label: {
            HStack(spacing: 12) {
                SiteIcon(name: "mosque", size: 28, color: c.text).frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 15).fill(c.text.opacity(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(F.plex(15, .bold)).foregroundStyle(c.text).lineLimit(1)
                    if !m.area.isEmpty { Text(m.area).font(F.plex(11.5)).foregroundStyle(c.muted).lineLimit(1) }
                    if let d, d < 60_000 {
                        HStack(spacing: 10) {
                            HStack(spacing: 3) { SiteIcon(name: "walk", size: 14, color: c.muted); Text(Mosques.mins(Mosques.walkS(d))) }
                            HStack(spacing: 3) { SiteIcon(name: "car", size: 14, color: c.muted); Text(Mosques.mins(Mosques.carS(d))) }
                            if first { Text(tr("الأقرب")).foregroundStyle(Color(red: 0.31, green: 0.75, blue: 0.52)) }
                        }.font(F.plex(11.5)).foregroundStyle(c.muted).padding(.top, 3)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 6) {
                    if let d { Text(Mosques.km(d)).font(F.plex(14, .bold)).foregroundStyle(c.text) }
                    SiteIcon(name: "nav", size: 17, color: c.onGold).frame(width: 36, height: 36).background(Circle().fill(c.gold))
                }
            }.padding(12).background(RoundedRectangle(cornerRadius: 20).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 20).stroke(c.lineSoft))
        }.buttonStyle(Press(scale: 0.98))
    }
}

@available(iOS 17.0, *)
/// One mosque: the way on the map (on foot or by car), time, distance, arrival, the next turn and every step;
/// «ابدأ الاتجاهات» hands it to Maps for the spoken turn-by-turn.
struct MosqueDetailView: View {
    let m: Mosque
    @StateObject private var mq = Mosques.shared
    @Environment(\.pal) private var c
    @State private var foot = true
    @State private var route: MKRoute?
    @State private var loading = false
    private var ui: UIState { UIState.shared! }
    var body: some View {
        let d: Double? = mq.pos == nil ? nil : mq.dist(m)
        let far = (d ?? 0) > 300_000
        let dur = route?.expectedTravelTime ?? d.map { foot ? Mosques.walkS($0) : Mosques.carS($0) }
        let dist = route?.distance ?? d
        let saved = mq.saved.contains { $0.id == m.id }
        ScrollView {
            VStack(spacing: 0) {
                MosqueMap(pins: [m], me: mq.pos, line: route?.polyline, sel: m.id)
                    .frame(height: 380)
                    .overlay(alignment: .top) {
                        if let st = route?.steps.dropFirst().first(where: { !$0.instructions.isEmpty }), let first = route?.steps.first {
                            HStack(spacing: 12) {
                                SiteIcon(name: "nav", size: 22, color: c.onGold).frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 14).fill(c.gold))
                                VStack(alignment: .leading, spacing: 1) { Text(Mosques.km(first.distance)).font(F.plex(19, .bold)).foregroundStyle(c.text); Text(st.instructions).font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(2) }
                                Spacer(minLength: 0)
                            }.padding(12).background(RoundedRectangle(cornerRadius: 20).fill(c.bg)).overlay(RoundedRectangle(cornerRadius: 20).stroke(c.line)).shadow(radius: 10, y: 4)
                            .padding(.horizontal, 12).padding(.top, 48)
                        }
                    }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name).font(F.plex(19, .bold)).foregroundStyle(c.text)
                            let sub = [m.area, Mosques.nextAdhan()].filter { !$0.isEmpty }.joined(separator: " · ")
                            if !sub.isEmpty { Text(sub).font(F.plex(12.5)).foregroundStyle(c.muted) }
                        }
                        Spacer()
                        Chip(text: nil, icon: saved ? "star-f" : "star", on: saved) { mq.toggle(m); ui.say(saved ? tr("أُزيل من المحفوظة") : tr("حُفظ المسجد")) }
                    }
                    if far, let d {
                        Text(tr("يبعد عنك {0} — افتح الخريطة لمعرفة الطريق إليه", Mosques.km(d))).font(F.plex(14)).foregroundStyle(c.muted)
                    } else {
                        HStack(spacing: 6) {
                            ForEach([true, false], id: \.self) { f in
                                Button { foot = f } label: {
                                    HStack(spacing: 6) { SiteIcon(name: f ? "walk" : "car", size: 18, color: foot == f ? c.onGold : c.text); Text(f ? tr("مشيًا") : tr("بالسيارة")).font(F.plex(14, .semibold)).foregroundStyle(foot == f ? c.onGold : c.text) }
                                        .frame(maxWidth: .infinity).frame(height: 40).background(Capsule().fill(foot == f ? c.gold : .clear))
                                }.buttonStyle(.plain)
                            }
                        }.padding(4).background(Capsule().fill(c.surface)).overlay(Capsule().stroke(c.lineSoft))
                        HStack {
                            stat(dur.map { Mosques.mins($0) } ?? "—", tr("المدة")); stat(dist.map { Mosques.km($0) } ?? "—", tr("المسافة"))
                            stat(dur.map { Date().addingTimeInterval($0).formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L.locale)) } ?? "—", tr("الوصول"))
                        }
                        if loading { Text(tr("جارٍ رسم الطريق…")).font(F.plex(12.5)).foregroundStyle(c.muted).frame(maxWidth: .infinity) }
                    }
                    HStack(spacing: 10) {
                        GoldButton(title: tr("ابدأ الاتجاهات"), icon: "nav") { openMaps() }.frame(maxWidth: .infinity)
                        Chip(text: nil, icon: "share") { share("\(m.name)\(m.area.isEmpty ? "" : " — " + m.area)\nhttps://maps.apple.com/?ll=\(m.lat),\(m.lng)&q=\(m.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") }
                    }
                    if let steps = route?.steps.filter({ !$0.instructions.isEmpty }), steps.count > 1 {
                        Text(tr("خطوات الطريق")).font(F.plex(14, .bold)).foregroundStyle(c.text)
                        ForEach(steps.indices, id: \.self) { i in
                            HStack(alignment: .top) { Text(steps[i].instructions).font(F.plex(13.5)).foregroundStyle(c.text); Spacer(); if steps[i].distance > 0 { Text(Mosques.km(steps[i].distance)).font(F.plex(11.5)).foregroundStyle(c.muted) } }
                        }
                    }
                }
                .padding(18).padding(.bottom, 20)
                .background(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26).fill(c.bg))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26).stroke(c.line))
                .padding(.top, -24)
            }
        }
        .background(c.bg.ignoresSafeArea())
        .environment(\.layoutDirection, L.dir)
        .navigationTitle(m.name)
        .task(id: foot) { await load(far: far) }
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) { Text(v).font(F.plex(19, .bold)).foregroundStyle(c.text); Text(l).font(F.plex(11)).foregroundStyle(c.muted) }.frame(maxWidth: .infinity)
    }
    private func load(far: Bool) async {
        guard let p = mq.pos, !far else { route = nil; return }
        loading = true
        let r = MKDirections.Request()
        r.source = MKMapItem(placemark: MKPlacemark(coordinate: p)); r.destination = MKMapItem(placemark: MKPlacemark(coordinate: m.coord))
        r.transportType = foot ? .walking : .automobile
        route = try? await MKDirections(request: r).calculate().routes.first
        loading = false
    }
    private func openMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: m.coord)); item.name = m.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: foot ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeDriving])
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
                        Text(n.name).font(F.plex(12.5, .bold)).foregroundStyle(c.text).lineLimit(1)
                        HStack(spacing: 2) { SiteIcon(name: "walk", size: 15, color: c.muted); Text(Mosques.mins(Mosques.walkS(mq.dist(n)))).font(F.plex(12.5)).foregroundStyle(c.muted) }
                        SiteIcon(name: "chev-l", size: 15, color: c.muted)
                    }.padding(.leading, 5).padding(.trailing, 10).padding(.vertical, 4).background(Capsule().fill(c.text.opacity(0.06))).overlay(Capsule().stroke(c.line))
                }.buttonStyle(Press()).padding(.top, 8)
            }
        }
        .task { if mq.allowed { await mq.locate(ask: false); await mq.loadNear() } }
    }
}
