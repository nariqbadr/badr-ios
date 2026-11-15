import Foundation
import Adhan
import UserNotifications

/// The two Holy Mosques: their live streams (Makkah / Madinah, the last choice remembered), their prayer times
/// (Umm al-Qura, Makkah time), the weekly imams from the dashboard, what is happening now (adhan → iqama → prayer),
/// and «تنبيهات الأئمة» — a notification before a prayer led by an imam the person follows.
enum Haram {
    struct Mosque { let key: String, name: String, city: String, short: String, lat: Double, lon: Double }
    static var mk: Mosque { Mosque(key: "mk", name: tr("المسجد الحرام"), city: tr("مكة المكرمة"), short: tr("الحرم المكي"), lat: 21.4225, lon: 39.8262) }
    static var md: Mosque { Mosque(key: "md", name: tr("المسجد النبوي"), city: tr("المدينة المنورة"), short: tr("المسجد النبوي"), lat: 24.4672, lon: 39.6111) }
    static func mosque(_ k: String) -> Mosque { k == "md" ? md : mk }
    static let prayerKeys = ["fajr", "dhuhr", "asr", "maghrib", "isha"]
    static func prayerName(_ k: String) -> String { tr(["fajr": "الفجر", "dhuhr": "الظهر", "asr": "العصر", "maghrib": "المغرب", "isha": "العشاء"][k] ?? "") }

    @MainActor static var live: J? { Repo.shared.data?.site.live }
    @MainActor static var madinahOn: Bool { (live?["madinah"]["enabled"].bool(true) ?? true) && !(live?["madinah"]["url"].str ?? "").isEmpty }
    /// The mosque chosen last time (Makkah the first time).
    @MainActor static var chosen: String {
        let k = UserDefaults.standard.string(forKey: "liveMosque") ?? "mk"
        return k == "md" && madinahOn ? "md" : "mk"
    }
    static func choose(_ k: String) { UserDefaults.standard.set(k, forKey: "liveMosque") }

    /// The stream: its title, its page, and what to embed (a video, or a channel's current live).
    struct Src { let title: String, url: String, embed: String, poster: String }
    @MainActor static func src(_ k: String) -> Src {
        let l = k == "md" ? live?["madinah"] : live
        let url = l?["url"].str ?? ""
        let vid = (l?["videoId"].str).flatMap { $0.isEmpty ? nil : $0 } ?? ytId(url) ?? (k == "mk" ? "eC4LfEVxvKg" : "")
        let ch = l?["channel"].str ?? ""
        let embed = !vid.isEmpty ? vid : !ch.isEmpty ? "live_stream?channel=\(ch)" : ""
        let t = l?["title"].str ?? ""
        return Src(title: tr(t.isEmpty ? (k == "md" ? "البث المباشر من المسجد النبوي" : "البث المباشر من المسجد الحرام") : t),
                   url: url.isEmpty ? "https://www.youtube.com/live/\(vid)" : url, embed: embed, poster: vid.isEmpty ? "" : "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg")
    }

    // ------------------------------------------------------------------ times (Makkah time)
    static let ksa = TimeZone(identifier: "Asia/Riyadh")!
    static var ksaCal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = ksa; return c }
    static func times(_ k: String, _ day: Date = Date()) -> [String: Date] {
        let m = mosque(k)
        let comps = ksaCal.dateComponents([.year, .month, .day], from: day)
        var p = CalculationMethod.ummAlQura.params; p.madhab = .shafi
        guard let pt = PrayerTimes(coordinates: Coordinates(latitude: m.lat, longitude: m.lon), date: comps, calculationParameters: p) else { return [:] }
        return ["fajr": pt.fajr, "dhuhr": pt.dhuhr, "asr": pt.asr, "maghrib": pt.maghrib, "isha": pt.isha]
    }
    /// «٧:٠٧ م» in Makkah time.
    static func clock(_ d: Date) -> String { let f = DateFormatter(); f.locale = L.locale; f.timeZone = ksa; f.dateFormat = "h:mm a"; return L.digits(f.string(from: d)) }
    static func ymd(_ d: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = ksa; f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }

    // ------------------------------------------------------------------ the imams
    struct Person: Identifiable { let id: String, mosque: String, name: String, full: String, title: String, photo: String; var nameAr: String }
    /// The people, with their names in the app language (Arabic for Arabic, Urdu and Persian; the dashboard's English names for the rest).
    @MainActor static func people() -> [Person] {
        let latin = !["ar", "ur", "fa"].contains(L.code)
        return (live?["imams"]["people"].array ?? []).map { p in
            let n = p["name"].str, f = p["full"].str.isEmpty ? n : p["full"].str, ne = p["nameEn"].str, fe = p["fullEn"].str
            return Person(id: p["id"].str, mosque: p["mosque"].str == "md" ? "md" : "mk",
                          name: latin ? (ne.isEmpty ? Names.of(n) : ne) : n, full: latin ? (fe.isEmpty ? (ne.isEmpty ? Names.of(f) : ne) : fe) : f,
                          title: tr(p["title"].str), photo: p["photo"].str, nameAr: n)
        }
    }
    @MainActor static func person(_ id: String?) -> Person? { guard let id, !id.isEmpty else { return nil }; return people().first { $0.id == id } }
    /// Who leads each prayer on a Makkah calendar day (the week's schedule, then that day's changes); nil outside the week.
    @MainActor static func slots(_ k: String, _ day: Date = Date()) -> [String: (imam: String, backup: String)]? {
        let w = live?["imams"][k], d = ymd(day)
        guard let w, !w["from"].str.isEmpty, d >= w["from"].str, d <= w["to"].str else { return nil }
        var out: [String: (imam: String, backup: String)] = [:]
        for (p, s) in w["slots"].dict { out[p] = (s["imam"].str, s["backup"].str) }
        for o in live?["imams"]["overrides"].array ?? [] where o["date"].str == d && (o["mosque"].str == "md" ? "md" : "mk") == k {
            out[o["prayer"].str] = (o["imam"].str, o["backup"].str)
        }
        return out
    }
    @MainActor static func week(_ k: String) -> (from: String, to: String)? { let w = live?["imams"][k]; guard let w, !w["from"].str.isEmpty else { return nil }; return (w["from"].str, w["to"].str) }

    // ------------------------------------------------------------------ timing (editable in the dashboard)
    static let iqamaDef = ["fajr": 25, "dhuhr": 20, "asr": 20, "maghrib": 10, "isha": 20], prayDef = ["fajr": 12, "dhuhr": 10, "asr": 10, "maghrib": 9, "isha": 10]
    @MainActor static var timing: J? { live?["imams"]["timing"] }
    @MainActor static func iqamaMin(_ k: String, _ p: String) -> Int { let v = timing?[k]["iqama"][p].int ?? 0; return v > 0 ? v : iqamaDef[p] ?? 20 }
    @MainActor static func prayMin(_ k: String, _ p: String) -> Int { let v = timing?[k]["pray"][p].int ?? 0; return v > 0 ? v : prayDef[p] ?? 10 }
    @MainActor static var adhanMin: Int { let v = timing?["adhan"].int ?? 0; return v > 0 ? v : 4 }
    @MainActor static var khutbahMin: Int { let v = timing?["khutbah"].int ?? 0; return v > 0 ? v : 30 }
    /// How long before the adhan the stream shows its countdown (0 = always).
    @MainActor static var beforeMin: Int { guard let t = timing, !t["before"].isNull else { return 30 }; return max(0, t["before"].int) }

    // ------------------------------------------------------------------ now: adhan → iqama → prayer
    struct State { let kind: String, step: Int, key: String, label: String, value: String, sub: String; var remain: TimeInterval = 0 }
    static func hms(_ s: TimeInterval) -> String { let v = max(0, Int(s)); return String(format: "%02d:%02d:%02d", v / 3600, v % 3600 / 60, v % 60) }
    @MainActor static func state(_ k: String, _ now: Date = Date()) -> State {
        let t = times(k, now), sl = slots(k, now), fri = ksaCal.component(.weekday, from: now) == 6
        func who(_ p: String, _ jum: Bool) -> String { person(sl?[p]?.imam).map { tr(jum ? "يخطب الشيخ {0}" : "بإمامة الشيخ {0}", $0.name) } ?? "" }
        for p in prayerKeys {
            guard let at = t[p] else { continue }
            let jum = fri && p == "dhuhr", name = jum ? tr("الجمعة") : prayerName(p)
            let ad = TimeInterval(adhanMin * 60), iq = TimeInterval((jum ? khutbahMin : iqamaMin(k, p)) * 60), end = iq + TimeInterval(prayMin(k, p) * 60)
            let d = now.timeIntervalSince(at)
            if d >= 0 && d < ad { return State(kind: "now", step: 1, key: p, label: tr("يُرفع الآن أذان {0}", name), value: tr("حيّ على الصلاة"), sub: "") }
            if d >= ad && d < iq { return jum ? State(kind: "now", step: 2, key: p, label: tr("خطبة الجمعة"), value: tr("تُلقى الآن"), sub: who(p, true))
                : State(kind: "wait", step: 2, key: p, label: tr("تُقام صلاة {0} بعد", name), value: hms(iq - d), sub: who(p, false)) }
            if d >= iq && d < end { return State(kind: "now", step: 3, key: p, label: tr("صلاة {0}", name), value: tr("أُقيمت الصلاة"), sub: who(p, false)) }
        }
        let m = mosque(k)
        for off in 0...1 {
            let day = ksaCal.date(byAdding: .day, value: off, to: now)!, tt = times(k, day), dfri = ksaCal.component(.weekday, from: day) == 6
            for p in prayerKeys { if let at = tt[p], at > now {
                let name = p == "dhuhr" && dfri ? tr("الجمعة") : prayerName(p)
                return State(kind: "next", step: 0, key: p, label: tr("أذان {0} في {1} بعد", name, m.short), value: hms(at.timeIntervalSince(now)), sub: "", remain: at.timeIntervalSince(now)) } }
        }
        return State(kind: "next", step: 0, key: "fajr", label: "", value: "", sub: "", remain: .infinity)
    }
    /// The prayer whose imam to show: the current one until its prayer ends, then the next.
    @MainActor static func next(_ k: String, _ now: Date = Date()) -> (key: String, at: Date, imam: Person?, backup: Person?)? {
        for off in 0...1 {
            let day = ksaCal.date(byAdding: .day, value: off, to: now)!, t = times(k, day), sl = slots(k, day)
            for p in prayerKeys { if let at = t[p] {
                let fri = ksaCal.component(.weekday, from: day) == 6 && p == "dhuhr"
                let end = at.addingTimeInterval(TimeInterval(((fri ? khutbahMin : iqamaMin(k, p)) + prayMin(k, p)) * 60))
                if end > now { return (fri ? "jumuah" : p, at, person(sl?[fri ? "jumuah" : p]?.imam ?? sl?[p]?.imam), person(sl?[fri ? "jumuah" : p]?.backup ?? sl?[p]?.backup)) }
            } }
        }
        return nil
    }

    // ------------------------------------------------------------------ «تنبيهات الأئمة»
    static var follows: Set<String> { Set(UserDefaults.standard.stringArray(forKey: "imamFollow") ?? []) }
    /// 0 = at the adhan, 1 = 10 minutes before the iqama, 2 = half an hour before the prayer
    static var whenMode: Int { get { UserDefaults.standard.object(forKey: "imamWhen") as? Int ?? 1 } set { UserDefaults.standard.set(newValue, forKey: "imamWhen") } }
    static var backupToo: Bool { get { UserDefaults.standard.bool(forKey: "imamBackup") } set { UserDefaults.standard.set(newValue, forKey: "imamBackup") } }
    @MainActor static func setFollow(_ id: String, _ on: Bool) {
        var f = follows; if on { f.insert(id) } else { f.remove(id) }
        UserDefaults.standard.set(Array(f), forKey: "imamFollow")
        if on { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        schedule()
    }
    /// Notifications for the followed imams' prayers this week (both mosques).
    @MainActor static func schedule() {
        let c = UNUserNotificationCenter.current()
        c.getPendingNotificationRequests { reqs in
            let old = reqs.map(\.identifier).filter { $0.hasPrefix("imam-") }
            c.removePendingNotificationRequests(withIdentifiers: old)
        }
        let f = follows; guard !f.isEmpty else { return }
        let now = Date()
        var n = 0
        for k in ["mk", "md"] {
            for off in 0..<7 {
                let day = ksaCal.date(byAdding: .day, value: off, to: now)!
                guard let sl = slots(k, day) else { continue }
                let t = times(k, day), fri = ksaCal.component(.weekday, from: day) == 6
                for p in prayerKeys {
                    guard let at = t[p] else { continue }
                    let jum = fri && p == "dhuhr", s = jum ? (sl["jumuah"] ?? sl[p]) : sl[p]
                    guard let s else { continue }
                    let asBackup = !f.contains(s.imam) && backupToo && f.contains(s.backup)
                    guard f.contains(s.imam) || asBackup, let who = person(asBackup ? s.backup : s.imam) else { continue }
                    let iq = TimeInterval((jum ? khutbahMin : iqamaMin(k, p)) * 60)
                    let fire = whenMode == 0 ? at : whenMode == 1 ? at.addingTimeInterval(iq - 600) : at.addingTimeInterval(-1800)
                    guard fire > now, n < 60 else { continue }
                    let name = jum ? tr("الجمعة") : prayerName(p), m = mosque(k)
                    let mins = Int((at.addingTimeInterval(iq).timeIntervalSince(fire)) / 60)
                    let whenTxt = mins > 1 ? tr("بعد {0} دقيقة", mins.ar) : tr("الآن")
                    let content = UNMutableNotificationContent()
                    content.title = tr("الشيخ {0} {1} صلاة {2}", who.name, asBackup ? tr("قد يؤم") : tr("يؤم"), name)
                    content.body = tr("{0} في {1} ({2} بتوقيت {3}){4}. اضغط لمشاهدة البث المباشر.", whenTxt, m.name, clock(at.addingTimeInterval(iq)), m.city, asBackup ? tr(" — إمامًا احتياطيًا") : "")
                    content.sound = .default; content.userInfo = ["open": "live/\(k)"]
                    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                    c.add(UNNotificationRequest(identifier: "imam-\(k)-\(ymd(day))-\(p)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
                    n += 1
                }
            }
        }
    }
}

/// People's names in the app language: Arabic, Urdu and Persian read the Arabic name; every other language gets the
/// dashboard's English name, or the name in Latin letters (known words from the list, the rest letter by letter).
enum Names {
    static let words: [String: String] = NamesData.words
    private static let let_: [Character: String] = ["ا": "a", "أ": "a", "إ": "i", "آ": "a", "ء": "", "ؤ": "u", "ئ": "i", "ب": "b", "ت": "t", "ث": "th", "ج": "j", "ح": "h", "خ": "kh",
        "د": "d", "ذ": "dh", "ر": "r", "ز": "z", "س": "s", "ش": "sh", "ص": "s", "ض": "d", "ط": "t", "ظ": "z", "ع": "a", "غ": "gh", "ف": "f", "ق": "q", "ك": "k", "ل": "l", "م": "m",
        "ن": "n", "ه": "h", "ة": "a", "و": "w", "ي": "y", "ى": "a"]
    private static let vow = Set("اويىأإآة")
    private static func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
    static func word(_ w: String) -> String {
        let bare = String(w.unicodeScalars.filter { !(0x064B...0x0652).contains($0.value) && $0.value != 0x0670 && $0.value != 0x0640 }.map(Character.init))
        if let x = words[w] ?? words[bare] { return x }
        if bare.hasPrefix("ال") && bare.count > 3 { return "Al-" + cap(word(String(bare.dropFirst(2)))) }
        if bare.hasPrefix("عبد") && bare.count > 4 { var r = word(String(bare.dropFirst(3))).lowercased(); if r.hasPrefix("al-") { r.removeFirst(3) }; return "Abdul" + r }
        let a = Array(bare); var out = ""
        for (i, c) in a.enumerated() {
            guard let l = let_[c] else { out.append(c); continue }
            if c == "و" { out += i == 0 ? "w" : "o" }
            else if c == "ي" { out += i == 0 ? "y" : "i" }
            else { out += l; if i == 0, i + 1 < a.count, !vow.contains(a[i + 1]), a.count > 2 { out += "a" } }
        }
        while out.contains("aa") { out = out.replacingOccurrences(of: "aa", with: "a") }
        return cap(out)
    }
    static func latin(_ s: String) -> String { s.split(separator: " ").map { word(String($0)) }.joined(separator: " ") }
    /// A reciter's or sheikh's name in the app language («الشيخ …» keeps its title, translated).
    @MainActor static func of(_ name: String?) -> String {
        let s = (name ?? "").trimmingCharacters(in: .whitespaces)
        guard !["ar", "ur", "fa"].contains(L.code), !s.isEmpty, s.range(of: "[\\u0600-\\u06FF]", options: .regularExpression) != nil else { return s }
        if let t = L.table[s] { return t }
        let short = s.hasPrefix("الشيخ ") ? String(s.dropFirst(6)).trimmingCharacters(in: .whitespaces) : s
        let en = (Repo.shared.data?.reciters ?? []).first { $0.name.trimmingCharacters(in: .whitespaces) == s || $0.name.replacingOccurrences(of: "الشيخ ", with: "").trimmingCharacters(in: .whitespaces) == short }?.nameEn ?? ""
        let sh = tr("الشيخ ").trimmingCharacters(in: .whitespaces)
        var e = en.isEmpty ? latin(short) : en
        for p in ["Sheikh ", "Шейх ", "Syekh ", "Syeikh ", "Şeyh ", "Cheikh "] where e.hasPrefix(p) { e.removeFirst(p.count) }
        return s.hasPrefix("الشيخ ") || (!en.isEmpty && en != e) ? "\(sh.isEmpty ? "Sheikh" : sh) \(e)" : e
    }
}
/// Shorthand for [Names.of].
@MainActor func nm(_ name: String?) -> String { Names.of(name) }
