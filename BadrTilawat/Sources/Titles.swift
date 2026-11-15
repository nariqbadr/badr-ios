import Foundation

/*
 * Lists show a recitation the way the site (and the Android app) does:
 *  - the title: «تلاوة من سورة …» / «تلاوة من سورتي … و…» / «تلاوة من سورة … إلى …»
 *  - under it, smaller: the rest of the title without the reciter's name
 */
private func normAr(_ s: String) -> String {
    String(s.map { c -> Character in switch c { case "أ", "إ", "آ": return "ا"; case "ى": return "ي"; case "ة": return "ه"; default: return c } })
}
private let SURAH_N: [(String, Int)] = Quran.surahs.enumerated().map { (normAr($0.element), $0.offset) }.sorted { $0.0.count > $1.0.count }
private func isLetter(_ c: Character?) -> Bool { guard let c, let u = c.unicodeScalars.first?.value else { return false }; return (0x621...0x64A).contains(u) }

private func firstMatch(_ re: String, _ s: String) -> Range<String.Index>? { s.range(of: re, options: .regularExpression) }

private struct SurahHit { let text: String; let start: Int; let end: Int; var local: String = "" }   // character offsets

private func surahMatch(_ title: String) -> SurahHit? {
    let t = Array(normAr(title)); let ts = String(t)
    func at(_ pos: Int) -> (Int, Int)? {
        let rest = pos >= t.count ? [] : Array(t[pos...])
        for (n, i) in SURAH_N { let nn = Array(n); if rest.count >= nn.count && Array(rest[0..<nn.count]) == nn && !isLetter(nn.count < rest.count ? rest[nn.count] : nil) { return (i, nn.count) } }
        return nil
    }
    guard let m = firstMatch("سور(ه|تي|تا)\\s+", ts) else { return nil }
    let mStart = ts.distance(from: ts.startIndex, to: m.lowerBound), p1 = ts.distance(from: ts.startIndex, to: m.upperBound)
    guard let a = at(p1) else { return nil }
    let after = String(t[min(t.count, p1 + a.1)...])
    var b: (Int, Int)? = nil, jLen = 0, joinWord = ""
    if let j = firstMatch("^\\s*(و|الي|إلى|حتي|حتى)\\s*(?:سوره\\s+)?", after) {
        jLen = after.distance(from: j.lowerBound, to: j.upperBound)
        joinWord = String(after[j]).trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).first ?? ""
        b = at(p1 + a.1 + jLen)
    }
    let end = b != nil ? p1 + a.1 + jLen + b!.1 : p1 + a.1
    let pre = String(t[0..<mStart])
    let beforeLen: Int = {
        if pre.hasSuffix("ل") { return 1 }
        if let r = firstMatch("(?:تلاوه\\s+)?(?:من\\s+)?$", pre) { return pre.distance(from: r.lowerBound, to: r.upperBound) }
        return 0
    }()
    let s1 = Quran.surahs[a.0]
    let text: String
    if let b { text = joinWord.hasPrefix("و") ? "تلاوة من سورتي \(s1) و\(Quran.surahs[b.0])" : "تلاوة من سورة \(s1) إلى \(Quran.surahs[b.0])" }
    else { text = "تلاوة من سورة \(s1)" }
    // the same in the app's language (the surah names translated too)
    let local: String
    if let b { local = joinWord.hasPrefix("و") ? tr("تلاوة من سورتي {0} و{1}", s1, Quran.surahs[b.0]) : tr("تلاوة من سورة {0} إلى {1}", s1, Quran.surahs[b.0]) }
    else { local = tr("تلاوة من سورة {0}", s1) }
    return SurahHit(text: text, start: mStart - beforeLen, end: end, local: local)
}

private let CUT = "\\s(?:ل|ب|لـ)?(?:فضيلة\\s+)?(?:الشيخ|للشيخ|بصوت|لفضيلة|القارئ)\\s|\\s[-–—|]\\s"

/// The short title in the app's language.
func shortTitleL(_ t: Track) -> String { surahMatch(t.title)?.local ?? shortTitle(t) }
/// The short title for lists and cards (Arabic).
func shortTitle(_ t: Track) -> String {
    if let h = surahMatch(t.title) { return h.text }
    var s = (t.title.isEmpty ? (t.surah.isEmpty ? "تلاوة" : t.surah) : t.title).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    if let r = firstMatch(CUT, s), s.distance(from: s.startIndex, to: r.lowerBound) > 6 { s = String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespaces) }
    while let l = s.last, " ،,:-–|".contains(l) { s.removeLast() }
    return s
}

/// The rest of the title, shown smaller under it (empty when there is nothing more).
@MainActor func titleDetail(_ t: Track) -> String {
    let raw = t.title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    if raw.isEmpty { return "" }
    let st = shortTitle(t)
    var s: String
    if let h = surahMatch(raw) { let a = Array(raw); s = String(a[0..<max(0, min(h.start, a.count))]) + " " + String(a[min(h.end, a.count)...]) }
    else { s = raw.replacingOccurrences(of: st, with: " | ") }
    var name = Repo.shared.reciter(t.reciterId)?.name ?? ""
    if name.hasPrefix("الشيخ ") { name = String(name.dropFirst(6)) }
    let words = Set(name.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init).filter { $0.count > 1 }).union(["بن", "ابن", "آل"])
    let hon: Set<String> = ["الشيخ", "للشيخ", "لفضيلة", "فضيلة", "بصوت", "القارئ", "للقارئ", "لشيخ"]
    let tk = s.components(separatedBy: " "); var keep = Array(repeating: true, count: tk.count)
    var i = 0
    while i < tk.count {
        if hon.contains(tk[i]) {
            var k = i; while k < tk.count && hon.contains(tk[k]) { k += 1 }
            var e = k; while e < tk.count && words.contains(tk[e]) { e += 1 }
            if e > k || k > i + 1 { for x in i..<e { keep[x] = false }; i = e; continue }
            if tk[i] == "الشيخ" || tk[i] == "للشيخ" { keep[i] = false }
        } else if words.contains(tk[i]) && i + 1 < tk.count && words.contains(tk[i + 1]) && tk[i] != "بن" {
            var e = i; while e < tk.count && words.contains(tk[e]) { e += 1 }
            for x in i..<e { keep[x] = false }; i = e; continue
        }
        i += 1
    }
    s = tk.enumerated().filter { keep[$0.offset] }.map(\.element).joined(separator: " ").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    let parts = s.replacingOccurrences(of: "\\s+[-–—]\\s+|\\s*[|:،]\\s*", with: "\u{1}", options: .regularExpression).components(separatedBy: "\u{1}").map { p -> String in
        var x = p.trimmingCharacters(in: .whitespaces)
        x = x.replacingOccurrences(of: "^(?:تلاوة|تلاوه)(?:\\s+من)?$", with: "", options: .regularExpression)
        x = x.replacingOccurrences(of: "^(?:تلاوة|تلاوه)\\s+(?=(?:من\\s+)?(?:تراويح|صلاة|قيام|ليلة|فجرية|عشائية))", with: "", options: .regularExpression)
        x = x.replacingOccurrences(of: "^من\\s+(?=تراويح|صلاة|قيام|ليلة)", with: "", options: .regularExpression)
        x = x.replacingOccurrences(of: "\\s+(?:من|في|و|عام)$", with: "", options: .regularExpression)
        x = x.replacingOccurrences(of: "^(?:من|في|و)$", with: "", options: .regularExpression)
        return x.trimmingCharacters(in: .whitespaces)
    }.filter { $0.count > 1 }
    let d = parts.joined(separator: " · ")
    return !d.isEmpty && d != st ? d : ""
}

/// «منذ ٣ أيام» from the date it was added.
func relAgo(_ t: Track) -> String {
    guard let d = Fmt.parse(t.createdAt.isEmpty ? t.publishAt : t.createdAt) else { return "" }
    let days = Int(Date().timeIntervalSince(d) / 86400)
    switch days {
    case ..<1: return tr("اليوم")
    case ..<2: return tr("أمس")
    case ..<3: return tr("منذ يومين")
    case ..<7: return tr("منذ {0} أيام", days.ar)
    case ..<30: let w = days / 7; return w == 1 ? tr("منذ أسبوع") : w == 2 ? tr("منذ أسبوعين") : tr("منذ {0} أسابيع", w.ar)
    case ..<365: let m = days / 30; return m == 1 ? tr("منذ شهر") : m == 2 ? tr("منذ شهرين") : m <= 10 ? tr("منذ {0} أشهر", m.ar) : tr("منذ {0} شهرًا", m.ar)
    default: let y = days / 365; return y == 1 ? tr("منذ سنة") : y == 2 ? tr("منذ سنتين") : tr("منذ {0} سنوات", y.ar)
    }
}
/// «هذا الأسبوع» / «هذا الشهر» / «قبل ذلك»
func ageGroup(_ t: Track) -> String { let d = Date().timeIntervalSince(t.stamp) / 86400; return d < 7 ? tr("هذا الأسبوع") : d < 31 ? tr("هذا الشهر") : tr("قبل ذلك") }
/// «جديد» for the number of days the dashboard sets (14 by default).
@MainActor func isNewTrack(_ t: Track) -> Bool {
    let days = Repo.shared.data?.site.j["newBadgeDays"].isNull == false ? Repo.shared.data!.site.j["newBadgeDays"].int : 14
    guard days > 0, let d = Fmt.parse(t.createdAt.isEmpty ? t.publishAt : t.createdAt) else { return false }
    return Date().timeIntervalSince(d) < Double(days) * 86400
}
