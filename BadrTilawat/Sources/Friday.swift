import Foundation

/// «سنن يوم الجمعة» and «فضائل يوم الجمعة»: the texts set in the dashboard (التحكم في التطبيق ← يوم الجمعة), else the ones
/// bundled with the app; each sunnah's time window on Friday; what the user marked done this Friday; and the salawat counter.
@MainActor
enum Friday {
    struct Sunnah { let key, icon, title, time, sub: String; let points: [String]; let rawi, hadith, src: String }
    struct Virtue { let title, rawi, hadith, src: String }

    private static let bundled: J = {
        guard let u = Bundle.main.url(forResource: "friday", withExtension: "json"), let d = try? Data(contentsOf: u) else { return J(nil) }
        return J(data: d)
    }()
    private static var j: J {
        if let f = Repo.shared.data?.site.j["friday"], !f.isNull, !f["sunnahs"].array.isEmpty { return f }
        return bundled
    }
    static var sunnahs: [Sunnah] {
        j["sunnahs"].array.map { x in
            Sunnah(key: x["key"].str, icon: x["icon"].str, title: x["t"].str, time: x["when"].str, sub: x["sub"].str,
                   points: x["points"].strings.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, rawi: x["rawi"].str, hadith: x["hadith"].str, src: x["src"].str)
        }.filter { !$0.title.isEmpty }
    }
    static var virtues: [Virtue] {
        j["fadail"].array.map { Virtue(title: $0["t"].str, rawi: $0["rawi"].str, hadith: $0["h"].str, src: $0["src"].str) }.filter { !$0.hadith.isEmpty }
    }
    /// the sunnah reminder: this many hours before the Friday prayer
    static var sunnahHours: Double { min(6, max(0.5, j["remind"]["sunnahHours"].double ?? bundled["remind"]["sunnahHours"].double ?? 2)) }
    /// the hour of Friday morning's Kahf reminder
    static var kahfHour: Int { min(11, max(5, Int(j["remind"]["kahfHour"].double ?? 9))) }

    static func isFriday(_ d: Date = Date()) -> Bool { Calendar.current.component(.weekday, from: d) == 6 }
    /// this Friday (today when it is Friday), else the next one
    static func nextFriday(_ d: Date = Date()) -> Date {
        var x = d; while !isFriday(x) { x = Calendar.current.date(byAdding: .day, value: 1, to: x)! }; return x
    }
    private static func dayKey(_ d: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
    /// done this Friday (starts again every Friday)
    static func done(_ i: Int) -> Bool { UserDefaults.standard.string(forKey: "jm-\(dayKey(nextFriday()))-\(i)") == "1" }
    static func setDone(_ i: Int, _ on: Bool) { UserDefaults.standard.set(on ? "1" : "0", forKey: "jm-\(dayKey(nextFriday()))-\(i)") }
    static var salawatToday: Int {
        get { UserDefaults.standard.integer(forKey: "slw-\(dayKey(Date()))") }
        set { UserDefaults.standard.set(newValue, forKey: "slw-\(dayKey(Date()))") }
    }

    /// the sunnah whose time it is now (Friday only, the first not done), or -1
    static func current(_ now: Date = Date()) -> Int {
        let day = Prayers.shared.forDay(now)
        func t(_ k: String) -> Date { day.first { $0.key == k }?.time ?? .distantPast }
        let fri = isFriday(now)
        let thuEve = Calendar.current.component(.weekday, from: now) == 5 && t("maghrib") < now
        for (i, s) in sunnahs.enumerated() where !done(i) {
            let inWin: Bool
            switch s.key {
            case "pre": inWin = fri && now >= t("fajr") && now < t("dhuhr")
            case "early": inWin = fri && now >= t("sunrise") && now < t("dhuhr")
            case "kahf", "salawat": inWin = thuEve || (fri && now < t("maghrib"))
            case "khutba": inWin = fri && now >= t("dhuhr").addingTimeInterval(-20 * 60) && now < t("dhuhr").addingTimeInterval(40 * 60)
            case "ijaba": inWin = fri && now >= t("maghrib").addingTimeInterval(-3600) && now < t("maghrib")
            default: inWin = false
            }
            if inWin { return i }
        }
        return -1
    }
}
