import Foundation
import Adhan
import CoreLocation
import UserNotifications

struct PrayerTime: Identifiable { let key: String, name: String, time: Date; var id: String { key + "\(time.timeIntervalSince1970)" } }

/// Prayer times computed on the phone (work offline) + adhan alerts as scheduled local notifications.
@MainActor
final class Prayers: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = Prayers()
    static let names: [(String, String)] = [("fajr", "الفجر"), ("sunrise", "الشروق"), ("dhuhr", "الظهر"), ("asr", "العصر"), ("maghrib", "المغرب"), ("isha", "العشاء")]
    @Published var rev = 0
    @Published var heading: Double = 0
    private let lm = CLLocationManager()
    private var locCont: CheckedContinuation<CLLocation?, Never>?

    override private init() { super.init(); lm.delegate = self; lm.desiredAccuracy = kCLLocationAccuracyKilometer }

    var place: String { Store.shared.str("place") }
    var hasPlace: Bool { Store.shared.double("lat") != nil }
    var coords: (Double, Double) { (Store.shared.double("lat") ?? 21.4225, Store.shared.double("lon") ?? 39.8262) }

    private func params() -> CalculationParameters {
        let cc = Store.shared.str("cc"); let tz = TimeZone.current.identifier
        var p: CalculationParameters
        if cc == "SA" || tz == "Asia/Riyadh" { p = CalculationMethod.ummAlQura.params }
        else if cc == "EG" || tz == "Africa/Cairo" { p = CalculationMethod.egyptian.params }
        else if cc == "AE" || tz == "Asia/Dubai" { p = CalculationMethod.dubai.params }
        else if cc == "KW" || tz == "Asia/Kuwait" { p = CalculationMethod.kuwait.params }
        else if cc == "QA" || tz == "Asia/Qatar" { p = CalculationMethod.qatar.params }
        else if ["JO", "PS", "SY", "LB", "IQ", "YE", "OM", "BH"].contains(cc) { p = CalculationMethod.ummAlQura.params }
        else { p = CalculationMethod.muslimWorldLeague.params }
        p.madhab = .shafi
        return p
    }
    func forDay(_ date: Date = Date()) -> [PrayerTime] {
        let (lat, lon) = coords
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        guard let pt = PrayerTimes(coordinates: Coordinates(latitude: lat, longitude: lon), date: comps, calculationParameters: params()) else { return [] }
        return [PrayerTime(key: "fajr", name: "الفجر", time: pt.fajr), PrayerTime(key: "sunrise", name: "الشروق", time: pt.sunrise), PrayerTime(key: "dhuhr", name: "الظهر", time: pt.dhuhr),
                PrayerTime(key: "asr", name: "العصر", time: pt.asr), PrayerTime(key: "maghrib", name: "المغرب", time: pt.maghrib), PrayerTime(key: "isha", name: "العشاء", time: pt.isha)]
    }
    func next() -> PrayerTime? {
        let now = Date()
        if let p = forDay().first(where: { $0.key != "sunrise" && $0.time > now }) { return p }
        return forDay(Calendar.current.date(byAdding: .day, value: 1, to: now)!).first
    }
    func qibla() -> Double { let (lat, lon) = coords; return Qibla(coordinates: Coordinates(latitude: lat, longitude: lon)).direction }

    static func hijri(_ d: Date = Date()) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .islamicUmmAlQura); f.locale = Locale(identifier: "ar"); f.dateFormat = "d MMMM y"
        return f.string(from: d) + " هـ"
    }

    // MARK: location
    var authorized: Bool { [.authorizedWhenInUse, .authorizedAlways].contains(lm.authorizationStatus) }
    /// Asks for permission if needed, then one fix; falls back to the internet's guess.
    func locate() async -> Bool {
        if lm.authorizationStatus == .notDetermined {
            lm.requestWhenInUseAuthorization()
            for _ in 0..<60 where lm.authorizationStatus == .notDetermined { try? await Task.sleep(nanoseconds: 500_000_000) }
        }
        if authorized, let loc = await withCheckedContinuation({ (c: CheckedContinuation<CLLocation?, Never>) in locCont = c; lm.requestLocation() }) {
            await save(loc.coordinate.latitude, loc.coordinate.longitude, by: "gps"); return true
        }
        return await locateByIp()
    }
    func locateByIp() async -> Bool {
        guard let u = URL(string: "https://ipapi.co/json/"), let (d, _) = try? await Repo.shared.session.data(from: u) else { return false }
        let j = J(data: d)
        guard let lat = j["latitude"].double, let lon = j["longitude"].double else { return false }
        Store.shared.set("cc", j["country_code"].str)
        await save(lat, lon, by: "ip", fallbackName: [j["city"].str, j["country_name"].str].filter { !$0.isEmpty }.joined(separator: "، "))
        return true
    }
    func setCity(_ city: String, _ country: String) async -> Bool {
        guard let p = try? await CLGeocoder().geocodeAddressString("\(city), \(country)").first, let l = p.location else { return false }
        Store.shared.set("cc", p.isoCountryCode ?? "")
        Store.shared.set("lat", l.coordinate.latitude); Store.shared.set("lon", l.coordinate.longitude)
        Store.shared.set("place", [city, p.country ?? country].filter { !$0.isEmpty }.joined(separator: "، ")); Store.shared.set("placeBy", "manual")
        rev += 1; schedule(); return true
    }
    private func save(_ lat: Double, _ lon: Double, by: String, fallbackName: String = "") async {
        Store.shared.set("lat", lat); Store.shared.set("lon", lon); Store.shared.set("placeBy", by)
        let pm = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon), preferredLocale: Locale(identifier: "ar")).first
        if let pm { Store.shared.set("cc", pm.isoCountryCode ?? Store.shared.str("cc")) }
        let name = [pm?.locality ?? pm?.administrativeArea, pm?.country].compactMap { $0 }.joined(separator: "، ")
        Store.shared.set("place", name.isEmpty ? fallbackName : name)
        rev += 1; schedule()
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in locCont?.resume(returning: locations.last); locCont = nil }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in locCont?.resume(returning: nil); locCont = nil }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading }
    }
    func startHeading() { lm.startUpdatingHeading() }
    func stopHeading() { lm.stopUpdatingHeading() }

    // MARK: alerts (like adhan apps): per prayer adhan / notification / off, plus an early reminder
    static let modes = ["adhan", "notify", "off"]
    func mode(_ k: String) -> String { let m = Store.shared.str("pmode_" + k, k == "sunrise" ? "off" : "adhan"); return Prayers.modes.contains(m) ? m : "adhan" }
    func setMode(_ k: String, _ m: String) { Store.shared.set("pmode_" + k, m); schedule() }
    var alertsOn: Bool { Store.shared.bool("adhan", true) }
    func setAlerts(_ on: Bool) { Store.shared.set("adhan", on); schedule() }
    var preMinutes: Int { Int(Store.shared.str("preMin", "0")) ?? 0 }
    func setPre(_ m: Int) { Store.shared.set("preMin", "\(m)"); schedule() }

    func requestNotifications() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    /// iOS keeps at most 64 pending notifications: the next ~8 days of prayers are scheduled (refreshed each time the app opens).
    func schedule() {
        let c = UNUserNotificationCenter.current()
        c.removeAllPendingNotificationRequests()
        guard alertsOn else { return }
        let pre = preMinutes
        var reqs: [UNNotificationRequest] = []
        let now = Date()
        for d in 0..<10 {
            guard let day = Calendar.current.date(byAdding: .day, value: d, to: now) else { continue }
            for p in forDay(day) {
                let m = mode(p.key); if m == "off" { continue }
                if p.time > now {
                    let n = UNMutableNotificationContent()
                    n.title = p.key == "sunrise" ? "حان وقت الشروق" : "حان الآن موعد صلاة \(p.name)"; n.body = "حيّ على الصلاة"
                    n.sound = m == "adhan" ? UNNotificationSound(named: UNNotificationSoundName("adhan.caf")) : .default
                    if #available(iOS 15.0, *) { n.interruptionLevel = .timeSensitive }
                    reqs.append(UNNotificationRequest(identifier: "p-\(p.key)-\(Int(p.time.timeIntervalSince1970))", content: n, trigger: trigger(p.time)))
                }
                if pre > 0, p.key != "sunrise", p.time.addingTimeInterval(Double(-pre * 60)) > now {
                    let n = UNMutableNotificationContent(); n.title = "اقتربت صلاة \(p.name)"; n.body = "بعد \(pre.ar) دقيقة"; n.sound = .default
                    reqs.append(UNNotificationRequest(identifier: "pre-\(p.key)-\(Int(p.time.timeIntervalSince1970))", content: n, trigger: trigger(p.time.addingTimeInterval(Double(-pre * 60)))))
                }
            }
        }
        for r in reqs.prefix(60) { c.add(r) }
    }
    private func trigger(_ d: Date) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d), repeats: false)
    }
}
