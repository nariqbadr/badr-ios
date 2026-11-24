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
    /// (the qibla screen has its own compass now: a heading published here redrew every screen many times a second)
    var heading: Double = 0
    private let lm = CLLocationManager()
    private var locCont: CheckedContinuation<CLLocation?, Never>?

    override private init() { super.init(); lm.delegate = self; lm.desiredAccuracy = kCLLocationAccuracyHundredMeters }

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
    /// the day's times worked out once (the home card asks every second): by the day, the place, the method's country and the language
    private var dayCache: [String: (six: [PrayerTime], ex: [PrayerTime])] = [:]
    private func cached(_ date: Date, _ make: () -> (six: [PrayerTime], ex: [PrayerTime])) -> (six: [PrayerTime], ex: [PrayerTime]) {
        let (lat, lon) = coords
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        let k = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)|\(lat)|\(lon)|\(Store.shared.str("cc"))|\(TimeZone.current.identifier)|\(L.code)"
        if let v = dayCache[k] { return v }
        if dayCache.count > 40 { dayCache.removeAll() }
        let v = make(); dayCache[k] = v; return v
    }
    func forDay(_ date: Date = Date()) -> [PrayerTime] { cached(date) { (computeDay(date), computeExtras(date)) }.six }
    func extras(_ date: Date = Date()) -> [PrayerTime] { cached(date) { (computeDay(date), computeExtras(date)) }.ex }
    private func computeDay(_ date: Date) -> [PrayerTime] {
        let (lat, lon) = coords
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        guard let pt = PrayerTimes(coordinates: Coordinates(latitude: lat, longitude: lon), date: comps, calculationParameters: params()) else { return [] }
        return [PrayerTime(key: "fajr", name: tr("الفجر"), time: pt.fajr), PrayerTime(key: "sunrise", name: tr("الشروق"), time: pt.sunrise), PrayerTime(key: "dhuhr", name: tr("الظهر"), time: pt.dhuhr),
                PrayerTime(key: "asr", name: tr("العصر"), time: pt.asr), PrayerTime(key: "maghrib", name: tr("المغرب"), time: pt.maghrib), PrayerTime(key: "isha", name: tr("العشاء"), time: pt.isha)]
    }
    /// «الضحى» (a quarter of an hour after sunrise: the sun a spear's length high) and «قيام الليل» (the start of the night's
    /// last third, from this day's maghrib to the next fajr) — after forDay's six, as on Android.
    static let duhaMin = 15
    private func computeExtras(_ date: Date) -> [PrayerTime] {
        let (lat, lon) = coords
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        guard let pt = PrayerTimes(coordinates: Coordinates(latitude: lat, longitude: lon), date: comps, calculationParameters: params()) else { return [] }
        var out = [PrayerTime(key: "duha", name: tr("الضحى"), time: pt.sunrise.addingTimeInterval(Double(Prayers.duhaMin * 60)))]
        if let st = SunnahTimes(from: pt) { out.append(PrayerTime(key: "qiyam", name: tr("قيام الليل"), time: st.lastThirdOfTheNight)) }
        return out
    }
    /// today's whole timeline: fajr, sunrise, duha, dhuhr, asr, maghrib, isha, then the night's last third
    func timeline(_ date: Date = Date()) -> [PrayerTime] {
        let six = forDay(date), ex = extras(date)
        guard !six.isEmpty else { return six }
        return Array(six.prefix(2)) + ex.filter { $0.key == "duha" } + Array(six.dropFirst(2)) + ex.filter { $0.key == "qiyam" }
    }
    func next() -> PrayerTime? {
        let now = Date()
        if let p = forDay().first(where: { $0.key != "sunrise" && $0.time > now }) { return p }
        return forDay(Calendar.current.date(byAdding: .day, value: 1, to: now)!).first
    }
    func qibla() -> Double { let (lat, lon) = coords; return Qibla(coordinates: Coordinates(latitude: lat, longitude: lon)).direction }

    static func hijri(_ d: Date = Date()) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .islamicUmmAlQura); f.locale = L.locale; f.dateFormat = "d MMMM y"
        return f.string(from: d) + tr(" هـ")
    }

    // MARK: location
    var authorized: Bool { [.authorizedWhenInUse, .authorizedAlways].contains(lm.authorizationStatus) }
    /// Asks for permission if needed, then one fix; falls back to the internet's guess.
    func locate() async -> Bool {
        if lm.authorizationStatus == .notDetermined {
            lm.requestWhenInUseAuthorization()
            for _ in 0..<60 where lm.authorizationStatus == .notDetermined { try? await Task.sleep(nanoseconds: 500_000_000) }
        }
        if authorized, let loc = await withCheckedContinuation({ (c: CheckedContinuation<CLLocation?, Never>) in locCont?.resume(returning: nil); locCont = c; lm.requestLocation() }) {
            // the same spot (within a kilometre): nothing to compute again
            if let la = Store.shared.double("lat"), let lo = Store.shared.double("lon"), Store.shared.str("placeBy") == "gps", !Store.shared.str("place").isEmpty,
               loc.distance(from: CLLocation(latitude: la, longitude: lo)) < 1000 { return true }
            await save(loc.coordinate.latitude, loc.coordinate.longitude, by: "gps"); return true
        }
        // the internet's guess (often a town away) only when there is no place yet, or the one there is was a guess too
        if hasPlace && Store.shared.str("placeBy") != "ip" { return false }
        return await locateByIp()
    }
    /// Each time the app opens or comes back (at most every 15 minutes): the place follows the phone, unless a city was chosen by hand.
    private var lastAuto = Date.distantPast
    func relocateIfStale() async {
        guard authorized, Store.shared.str("placeBy") != "manual", Date().timeIntervalSince(lastAuto) > 15 * 60 else { return }
        lastAuto = Date(); _ = await locate()
    }
    func locateByIp() async -> Bool {
        guard let u = URL(string: "https://ipapi.co/json/"), let (d, _) = try? await Repo.shared.session.data(from: u) else { return false }
        let j = J(data: d)
        guard let lat = j["latitude"].double, let lon = j["longitude"].double else { return false }
        Store.shared.set("cc", j["country_code"].str)
        await save(lat, lon, by: "ip", fallbackName: [j["city"].str, j["country_name"].str].filter { !$0.isEmpty }.joined(separator: tr("، ")))
        return true
    }
    func setCity(_ city: String, _ country: String) async -> Bool {
        guard let p = try? await CLGeocoder().geocodeAddressString("\(city), \(country)").first, let l = p.location else { return false }
        Store.shared.set("cc", p.isoCountryCode ?? "")
        Store.shared.set("lat", l.coordinate.latitude); Store.shared.set("lon", l.coordinate.longitude)
        Store.shared.set("place", [city, p.country ?? country].filter { !$0.isEmpty }.joined(separator: tr("، "))); Store.shared.set("placeBy", "manual")
        rev += 1; schedule(); return true
    }
    private func save(_ lat: Double, _ lon: Double, by: String, fallbackName: String = "") async {
        Store.shared.set("lat", lat); Store.shared.set("lon", lon); Store.shared.set("placeBy", by)
        let pm = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon), preferredLocale: Locale(identifier: "ar")).first
        if let pm { Store.shared.set("cc", pm.isoCountryCode ?? Store.shared.str("cc")) }
        let name = [pm?.locality ?? pm?.administrativeArea, pm?.country].compactMap { $0 }.joined(separator: tr("، "))
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
    /// the keys with no adhan (a notification or nothing)
    static let quiet: Set<String> = ["sunrise", "duha", "qiyam"]
    func mode(_ k: String) -> String {
        let q = Prayers.quiet.contains(k)
        let m = Store.shared.str("pmode_" + k, q ? "off" : "adhan")
        if !Prayers.modes.contains(m) { return q ? "off" : "adhan" }
        return q && m == "adhan" ? "notify" : m
    }
    func setMode(_ k: String, _ m: String) { Store.shared.set("pmode_" + k, m); rev += 1; schedule() }
    /// «يرنّ حتى في الصامت»: on iOS 26 the adhan is also set as a system alarm (AlarmKit), which sounds through the silent switch
    var ringSilent: Bool { Store.shared.str("ringSilent", "0") == "1" }
    var ringSilentAvailable: Bool { if #available(iOS 26.0, *) { return true }; return false }
    func setRingSilent(_ on: Bool) async -> Bool {
        if on {
            guard await SilentAlarms.authorize() else { Store.shared.set("ringSilent", "0"); rev += 1; return false }
        }
        Store.shared.set("ringSilent", on ? "1" : "0"); rev += 1; schedule(); return true
    }
    var alertsOn: Bool { Store.shared.bool("adhan", true) }
    func setAlerts(_ on: Bool) { Store.shared.set("adhan", on); schedule() }
    // «الإقامة»: a notification a set number of minutes after each adhan (not Friday's jumuah, whose khutbah sets the time) — as on Android
    static let iqDef: [String: Int] = ["fajr": 20, "dhuhr": 15, "asr": 15, "maghrib": 10, "isha": 15]
    static let iqKeys = ["fajr", "dhuhr", "asr", "maghrib", "isha"]
    var iqOn: Bool { Store.shared.str("iqOn", "1") == "1" }
    func setIqOn(_ on: Bool) { Store.shared.set("iqOn", on ? "1" : "0"); schedule() }
    func iqMin(_ k: String) -> Int { min(90, max(1, Int(Store.shared.str("iq_" + k, "\(Prayers.iqDef[k] ?? 15)")) ?? 15)) }
    func setIqMin(_ k: String, _ m: Int) { Store.shared.set("iq_" + k, "\(min(90, max(1, m)))"); schedule() }
    /// the iqama time of a prayer, or nil (off, sunrise, its alert off, or Friday's dhuhr)
    func iqamaAt(_ p: PrayerTime) -> Date? {
        guard iqOn, Prayers.iqDef[p.key] != nil, mode(p.key) != "off" else { return nil }
        if p.key == "dhuhr" && Calendar.current.component(.weekday, from: p.time) == 6 { return nil }
        return p.time.addingTimeInterval(Double(iqMin(p.key) * 60))
    }
    /// «تجربة الأذان»: the very notification a prayer time gives (its title, the muezzin, the adhan's sound), at once —
    /// the app can be closed or the screen locked to see it arrive (as on Android)
    func testNotification() async -> Bool {
        let c = UNUserNotificationCenter.current()
        let st = await c.notificationSettings()
        if st.authorizationStatus != .authorized && st.authorizationStatus != .provisional {
            guard (try? await c.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return false }
        }
        let nx = forDay().first { $0.key != "sunrise" && $0.time > Date() } ?? forDay().first { $0.key == "maghrib" }
        let k = nx?.key ?? "maghrib", name = nx?.name ?? tr("المغرب")
        // it goes out at once: the chosen voice is waited for at most 3 s (it is downloaded once), else the built-in adhan sounds
        if Adhan.soundName(k == "fajr") == nil {
            let prep = Task { await Adhan.prepare() }
            for _ in 0..<15 where Adhan.soundName(k == "fajr") == nil { try? await Task.sleep(nanoseconds: 200_000_000) }
            _ = prep
        }
        let n = UNMutableNotificationContent()
        n.title = tr("حان الآن موعد صلاة {0}", name)
        let who = Adhan.voice.map { $0.muezzin.isEmpty ? $0.name : $0.muezzin } ?? ""
        n.body = who.isEmpty ? tr("انقر للاستماع إلى الأذان كاملًا") : tr("بصوت {0} · انقر للاستماع إلى الأذان كاملًا", who)
        n.sound = UNNotificationSound(named: UNNotificationSoundName(Adhan.soundName(k == "fajr") ?? "adhan.caf"))
        n.userInfo = ["adhan": k]
        if #available(iOS 15.0, *) { n.interruptionLevel = .timeSensitive }
        // the last test is taken away first, so this one comes as a new banner with its sound
        c.removePendingNotificationRequests(withIdentifiers: ["adhan-test"])
        c.removeDeliveredNotifications(withIdentifiers: ["adhan-test"])
        do { try await c.add(UNNotificationRequest(identifier: "adhan-test", content: n, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))) }
        catch { return false }
        return true
    }
    /// «تجربة إشعار الإقامة»: the iqama notification itself (its title, the hadith, the chosen voice), at once
    func testIqama() async -> Bool {
        let c = UNUserNotificationCenter.current()
        let st = await c.notificationSettings()
        if st.authorizationStatus != .authorized && st.authorizationStatus != .provisional {
            guard (try? await c.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return false }
        }
        if Adhan.iqVoice != nil && Adhan.iqSoundName() == nil {
            let prep = Task { await Adhan.prepare() }
            for _ in 0..<15 where Adhan.iqSoundName() == nil { try? await Task.sleep(nanoseconds: 200_000_000) }
            _ = prep
        }
        let nx = forDay().first { $0.key != "sunrise" && $0.time > Date() } ?? forDay().first { $0.key == "dhuhr" }
        let n = UNMutableNotificationContent()
        n.title = tr("حان وقت إقامة صلاة {0}", nx?.name ?? tr("الظهر"))
        n.body = tr("قال رسول الله صلى الله عليه وسلم: «إذا أُقيمَت الصلاةُ فلا تأتوها تَسْعَوْن، وأْتوها تمشون، وعليكم السَّكينة، فما أدركتم فصلُّوا، وما فاتكم فأتِمُّوا»")
        n.sound = Adhan.iqSoundName().map { UNNotificationSound(named: UNNotificationSoundName($0)) } ?? .default
        n.userInfo = ["iqama": nx?.key ?? "dhuhr"]
        if #available(iOS 15.0, *) { n.interruptionLevel = .timeSensitive }
        c.removePendingNotificationRequests(withIdentifiers: ["iqama-test"])
        c.removeDeliveredNotifications(withIdentifiers: ["iqama-test"])
        do { try await c.add(UNNotificationRequest(identifier: "iqama-test", content: n, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))) }
        catch { return false }
        return true
    }
    // MARK: reminders: «صلِّ على محمد ﷺ», «سورة الكهف», «سنن يوم الجمعة» — they come with the prayer alerts off too
    /// how often «صلِّ على محمد ﷺ» comes, in minutes (0 off, 30, 60, 120, 1440 once a day after maghrib); day and night
    var salawatEvery: Int { let m = Int(Store.shared.str("salawatEvery", "0")) ?? 0; return [0, 30, 60, 120, 1440].contains(m) ? m : 0 }
    func setSalawat(_ m: Int) { Store.shared.set("salawatEvery", "\(m)"); rev += 1; schedule() }
    var kahfOn: Bool { Store.shared.str("kahfOn", "1") == "1" }
    func setKahf(_ on: Bool) { Store.shared.set("kahfOn", on ? "1" : "0"); rev += 1; schedule() }
    var fridayOn: Bool { Store.shared.str("fridayOn", "1") == "1" }
    func setFriday(_ on: Bool) { Store.shared.set("fridayOn", on ? "1" : "0"); rev += 1; schedule() }
    /// a reminder's voice: «badr» (Sheikh Badr al-Turki) or «default» (the notification sound)
    func voice(_ k: String) -> String { let v = Store.shared.str("voice_" + k, "badr"); return v == "default" ? "default" : "badr" }
    func setVoice(_ k: String, _ v: String) { Store.shared.set("voice_" + k, v); rev += 1; schedule() }
    private func sound(_ k: String) -> UNNotificationSound { voice(k) == "badr" ? UNNotificationSound(named: UNNotificationSoundName("\(k).caf")) : .default }
    static let salawatBody = "قال رسول الله ﷺ: «من صلّى عليَّ واحدةً صلّى الله عليه عشرًا» رواه مسلم"
    private func salawatContent() -> UNMutableNotificationContent {
        let n = UNMutableNotificationContent(); n.title = tr("صلِّ على محمد ﷺ"); n.body = tr(Prayers.salawatBody)
        n.sound = sound("salawat"); n.userInfo = ["voice": "salawat"]; return n
    }
    private func qiyamContent() -> UNMutableNotificationContent {
        let n = UNMutableNotificationContent(); n.title = tr("الثلث الأخير من الليل"); n.body = tr("قال رسول الله ﷺ: «ينزل ربُّنا تبارك وتعالى كلَّ ليلةٍ إلى السماء الدنيا حين يبقى ثلثُ الليل الآخر، يقول: من يدعوني فأستجيب له، من يسألني فأعطيه، من يستغفرني فأغفر له» متفق عليه")
        n.sound = sound("qiyam"); n.userInfo = ["voice": "qiyam"]; if #available(iOS 15.0, *) { n.interruptionLevel = .timeSensitive }; return n
    }
    /// «تجربة الإشعار» of a reminder: the notification itself, at once
    func testReminder(_ k: String) async -> Bool {
        let c = UNUserNotificationCenter.current()
        let st = await c.notificationSettings()
        if st.authorizationStatus != .authorized && st.authorizationStatus != .provisional {
            guard (try? await c.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return false }
        }
        let id = "\(k)-test"
        c.removePendingNotificationRequests(withIdentifiers: [id]); c.removeDeliveredNotifications(withIdentifiers: [id])
        do { try await c.add(UNNotificationRequest(identifier: id, content: k == "qiyam" ? qiyamContent() : salawatContent(), trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))) }
        catch { return false }
        return true
    }
    /// the reminders' requests: the salawat repeat by the clock (iOS keeps 64 pending), Kahf and the sunnahs for the next two Fridays
    private func reminders(_ now: Date) -> [UNNotificationRequest] {
        var r: [UNNotificationRequest] = []
        let every = salawatEvery
        if every == 1440 {
            for d in 0..<7 {
                guard let day = Calendar.current.date(byAdding: .day, value: d, to: now), let m = forDay(day).first(where: { $0.key == "maghrib" }) else { continue }
                let at = m.time.addingTimeInterval(15 * 60); guard at > now else { continue }
                r.append(UNNotificationRequest(identifier: "slw-\(Int(at.timeIntervalSince1970))", content: salawatContent(), trigger: trigger(at)))
            }
        } else if every > 0 {
            // every half hour: at :00 and :30 · every hour: at :00 · every two hours: the even hours — each repeating
            let comps: [DateComponents] = every == 30 ? [DateComponents(minute: 0), DateComponents(minute: 30)] : every == 60 ? [DateComponents(minute: 0)]
                : stride(from: 0, to: 24, by: 2).map { DateComponents(hour: $0, minute: 0) }
            for (i, dc) in comps.enumerated() {
                r.append(UNNotificationRequest(identifier: "slw-r\(i)", content: salawatContent(), trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)))
            }
        }
        for d in 0..<14 {
            guard let day = Calendar.current.date(byAdding: .day, value: d, to: now) else { continue }
            let wd = Calendar.current.component(.weekday, from: day)
            if kahfOn {
                var at: [Date] = []
                if wd == 5, let m = forDay(day).first(where: { $0.key == "maghrib" }) { at.append(m.time.addingTimeInterval(20 * 60)) }
                if wd == 6, let t = Calendar.current.date(bySettingHour: Friday.kahfHour, minute: 0, second: 0, of: day) { at.append(t) }
                for t in at where t > now {
                    let n = UNMutableNotificationContent(); n.title = tr("اقرأ سورة الكهف")
                    n.body = tr("«من قرأ سورة الكهف في يوم الجمعة أضاء له من النور ما بين الجمعتين»"); n.sound = .default; n.userInfo = ["open": "kahf"]
                    r.append(UNNotificationRequest(identifier: "kahf-\(Int(t.timeIntervalSince1970))", content: n, trigger: trigger(t)))
                }
            }
            if fridayOn, wd == 6, let dh = forDay(day).first(where: { $0.key == "dhuhr" }) {
                let t = dh.time.addingTimeInterval(-Friday.sunnahHours * 3600)
                if t > now {
                    let n = UNMutableNotificationContent(); n.title = tr("سنن يوم الجمعة")
                    n.body = tr("الاغتسال، والطيب، والتبكير إلى المسجد، والإنصات للخطبة، والإكثار من الصلاة على النبي ﷺ"); n.sound = .default; n.userInfo = ["open": "friday"]
                    r.append(UNNotificationRequest(identifier: "fsn-\(Int(t.timeIntervalSince1970))", content: n, trigger: trigger(t)))
                }
            }
        }
        return r
    }
    var preMinutes: Int { Int(Store.shared.str("preMin", "0")) ?? 0 }
    func setPre(_ m: Int) { Store.shared.set("preMin", "\(m)"); schedule() }

    func requestNotifications() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    /// iOS keeps at most 64 pending notifications: the next ~8 days of prayers are scheduled (refreshed each time the app opens).
    func schedule() {
        let c = UNUserNotificationCenter.current()
        WidgetBridge.prayers()
        let wird = Wird.requests() + reminders(Date())
        /// replaces this app's prayer and wird alerts, and leaves the imams' alerts (Haram.schedule) alone
        func replace(_ reqs: [UNNotificationRequest]) {
            c.getPendingNotificationRequests { old in
                c.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier).filter { !$0.hasPrefix("imam-") && !$0.hasSuffix("-test") })
                for r in reqs { c.add(r) }
            }
        }
        // «يرنّ حتى في الصامت»: the next two days' adhans as system alarms (their notifications then come without a second sound)
        let alarmDays = ringSilent && alertsOn ? 2 : 0
        SilentAlarms.sync(alarmDays == 0 ? [] : (0..<alarmDays).flatMap { d -> [PrayerTime] in
            guard let day = Calendar.current.date(byAdding: .day, value: d, to: Date()) else { return [] }
            return forDay(day).filter { $0.key != "sunrise" && mode($0.key) == "adhan" && $0.time > Date() }
        })
        let alarmUntil = Calendar.current.date(byAdding: .day, value: alarmDays, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        guard alertsOn else { replace(wird); return }
        let pre = preMinutes
        var reqs: [UNNotificationRequest] = []
        let now = Date()
        for d in 0..<10 {
            guard let day = Calendar.current.date(byAdding: .day, value: d, to: now) else { continue }
            for p in forDay(day) {
                let m = mode(p.key); if m == "off" { continue }
                if p.time > now {
                    let n = UNMutableNotificationContent()
                    n.title = p.key == "sunrise" ? tr("حان وقت الشروق") : tr("حان الآن موعد صلاة {0}", p.name)
                    // the adhan's voice, and that a tap plays it whole (the notification itself plays 30 s)
                    let who = Adhan.voice.map { $0.muezzin.isEmpty ? $0.name : $0.muezzin } ?? ""
                    n.body = m == "adhan" && p.key != "sunrise" ? (who.isEmpty ? tr("انقر للاستماع إلى الأذان كاملًا") : tr("بصوت {0} · انقر للاستماع إلى الأذان كاملًا", who)) : tr("حيّ على الصلاة")
                    n.sound = m == "adhan" ? UNNotificationSound(named: UNNotificationSoundName(Adhan.soundName(p.key == "fajr") ?? "adhan.caf")) : .default
                    if m == "adhan" && p.key != "sunrise" && alarmDays > 0 && p.time < alarmUntil { n.sound = nil }
                    if m == "adhan" && p.key != "sunrise" { n.userInfo = ["adhan": p.key] }
                    if #available(iOS 15.0, *) { n.interruptionLevel = .timeSensitive }
                    reqs.append(UNNotificationRequest(identifier: "p-\(p.key)-\(Int(p.time.timeIntervalSince1970))", content: n, trigger: trigger(p.time)))
                }
                if let iq = iqamaAt(p), iq > now {
                    let n = UNMutableNotificationContent(); n.title = tr("حان وقت إقامة صلاة {0}", p.name)
                    n.body = tr("قال رسول الله صلى الله عليه وسلم: «إذا أُقيمَت الصلاةُ فلا تأتوها تَسْعَوْن، وأْتوها تمشون، وعليكم السَّكينة، فما أدركتم فصلُّوا، وما فاتكم فأتِمُّوا»")
                    // the chosen iqama voice (its first 30 s), else the usual alert sound
                    n.sound = Adhan.iqSoundName().map { UNNotificationSound(named: UNNotificationSoundName($0)) } ?? .default; n.userInfo = ["iqama": p.key]
                    if #available(iOS 15.0, *) { n.interruptionLevel = .timeSensitive }
                    reqs.append(UNNotificationRequest(identifier: "iq-\(p.key)-\(Int(p.time.timeIntervalSince1970))", content: n, trigger: trigger(iq)))
                }
                if pre > 0, p.key != "sunrise", p.time.addingTimeInterval(Double(-pre * 60)) > now {
                    let n = UNMutableNotificationContent(); n.title = tr("اقتربت صلاة {0}", p.name); n.body = tr("بعد {0} دقيقة", pre.ar); n.sound = .default
                    reqs.append(UNNotificationRequest(identifier: "pre-\(p.key)-\(Int(p.time.timeIntervalSince1970))", content: n, trigger: trigger(p.time.addingTimeInterval(Double(-pre * 60)))))
                }
            }
        }
        // «الضحى» and «قيام الليل»: a notification only, when chosen
        for d in 0..<10 {
            guard let day = Calendar.current.date(byAdding: .day, value: d, to: now) else { continue }
            for p in extras(day) where mode(p.key) != "off" && p.time > now {
                let n = p.key == "qiyam" ? qiyamContent() : UNMutableNotificationContent()
                if p.key == "duha" { n.title = tr("دخل وقت صلاة الضحى"); n.body = tr("صلاة الأوّابين حين ترمض الفصال"); n.sound = .default }
                reqs.append(UNNotificationRequest(identifier: "x-\(p.key)-\(Int(p.time.timeIntervalSince1970))", content: n, trigger: trigger(p.time)))
            }
        }
        // «ذكّرني قبل الجمعة»: before Friday's prayer (at dhuhr), with my mosque's name
        let jm = mosquesOn ? Mosques.shared.jumuahMin : 0
        if jm > 0 {
            for d in 0..<10 {
                guard let day = Calendar.current.date(byAdding: .day, value: d, to: now), Calendar.current.component(.weekday, from: day) == 6,
                      let dh = forDay(day).first(where: { $0.key == "dhuhr" }) else { continue }
                let at = dh.time.addingTimeInterval(Double(-jm * 60)); guard at > now else { continue }
                let n = UNMutableNotificationContent()
                n.title = Mosques.shared.mine.map { tr("اقتربت صلاة الجمعة في {0}", $0.title) } ?? tr("اقتربت صلاة الجمعة")
                n.body = tr("الغسل والطيب والتبكير وقراءة سورة الكهف، والصلاة على النبي ﷺ"); n.sound = .default; n.userInfo = ["open": "mosques"]
                reqs.append(UNNotificationRequest(identifier: "jum-\(Int(at.timeIntervalSince1970))", content: n, trigger: trigger(at)))
            }
        }
        // iOS keeps 64: the imams' alerts keep up to 16 of them
        // the soonest first (the prayer, its iqama and the next one's reminder are kept in time order)
        reqs.sort { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture < ($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture }
        replace(Array(reqs.prefix(max(8, 48 - wird.count))) + wird)
    }
    private func trigger(_ d: Date) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d), repeats: false)
    }
}
