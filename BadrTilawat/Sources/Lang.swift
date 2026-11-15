import Foundation
import SwiftUI

/// The app's language. The first time it follows the phone's language (English when the phone's language isn't one
/// of ours); the person can change it from the menu. Texts are written in Arabic in the code and looked up in the
/// bundled <code>.json (Arabic text → translation); anything not translated stays Arabic.
@MainActor
final class Lang: ObservableObject {
    static let shared = Lang()
    /// Code and name in its own language.
    static let all: [(String, String)] = [("ar", "العربية"), ("en", "English"), ("ur", "اردو"), ("hi", "हिन्दी"), ("bn", "বাংলা"), ("id", "Bahasa Indonesia"),
                                          ("tr", "Türkçe"), ("fr", "Français"), ("ms", "Bahasa Melayu"), ("fa", "فارسی"), ("ru", "Русский")]
    static let codes = Set(all.map { $0.0 })

    @Published private(set) var code: String
    private(set) var table: [String: String] = [:]

    private init() {
        // screenshots on the build machine: BZ_LANG picks the language
        let saved = ProcessInfo.processInfo.environment["BZ_LANG"] ?? UserDefaults.standard.string(forKey: "lang") ?? ""
        code = Lang.codes.contains(saved) ? saved : Lang.device()
        table = Lang.load(code)
        L.code = code; L.table = table
    }
    /// The phone's language, if we have it.
    static func device() -> String {
        for p in Locale.preferredLanguages {
            let c = String(p.split(separator: "-").first ?? "").lowercased()
            let k = c == "in" ? "id" : c
            if codes.contains(k) { return k }
        }
        return "en"
    }
    static func load(_ c: String) -> [String: String] {
        guard c != "ar", let u = Bundle.main.url(forResource: c, withExtension: "json"), let d = try? Data(contentsOf: u),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        return o
    }
    /// Switches the language now; the whole app is drawn again in it.
    func set(_ c: String) {
        guard Lang.codes.contains(c), c != code else { return }
        UserDefaults.standard.set(c, forKey: "lang")
        table = Lang.load(c); L.code = c; L.table = table
        code = c
    }
    var rtl: Bool { L.rtl }
    var direction: LayoutDirection { rtl ? .rightToLeft : .leftToRight }
    var name: String { Lang.all.first { $0.0 == code }?.1 ?? "" }
}

/// The current language, readable from anywhere (also off the main actor).
enum L {
    static var code = "ar"
    static var table: [String: String] = [:]
    static var rtl: Bool { code == "ar" || code == "ur" || code == "fa" }
    static var dir: LayoutDirection { rtl ? .rightToLeft : .leftToRight }
    static var ar: Bool { code == "ar" }
    static var locale: Locale { Locale(identifier: code == "ar" ? "ar" : code) }
    static func t(_ s: String) -> String { table[s] ?? s }
    /// Digits as this language writes them.
    static func digits(_ s: String) -> String {
        let to: [Character]
        switch code { case "ar": to = Array("٠١٢٣٤٥٦٧٨٩"); case "fa", "ur": to = Array("۰۱۲۳۴۵۶۷۸۹"); default: return s }
        return String(s.map { c in if let v = c.wholeNumberValue, c.isASCII { return to[v] }; return c })
    }
    /// The translation of the Quran's meanings shown under the ayahs (alquran.cloud editions, served through the site).
    static let quran: [String: (String, String)] = ["en": ("en.sahih", "Saheeh International"), "ur": ("ur.jalandhry", "فتح محمد جالندھری"), "hi": ("hi.hindi", "सुहेल फ़ारूक़ ख़ान"),
        "bn": ("bn.bengali", "মুহিউদ্দীন খান"), "id": ("id.indonesian", "Kementerian Agama RI"), "tr": ("tr.diyanet", "Diyanet İşleri"), "fr": ("fr.hamidullah", "Muhammad Hamidullah"),
        "ms": ("ms.basmeih", "Abdullah Muhammad Basmeih"), "fa": ("fa.khorramdel", "مصطفی خرمدل"), "ru": ("ru.kuliev", "Эльмир Кулиев")]
}

/// The text in the app's language; {0}, {1}… are replaced by the arguments (Arabic words among them — a prayer, a surah — are translated too).
func tr(_ s: String, _ a: Any...) -> String {
    var r = L.t(s)
    // «سورة {0}»: a surah's own name (Al-Fajr, Al-Asr — not the prayers of the same names)
    let sur = s.contains("سور")
    for (i, v) in a.enumerated() {
        let x: String
        if let str = v as? String { x = (sur ? L.table["surah:" + str] : nil) ?? L.t(str) } else { x = "\(v)" }
        r = r.replacingOccurrences(of: "{\(i)}", with: x)
    }
    return r
}
