import SwiftUI
import AVFoundation
import CoreImage
import Photos

// MARK: - data

/// Ayah timings of an analysed recitation: [ayah, startMs, endMs], words per ayah ([share×1000 or startMs, ms]).
struct AyahTimes { let ayahs: [[Int]]; let words: [[[Int]]]; let surah: Int; var url: String = ""
    /// the other parts heard in the recording: the surahs it goes on to, and al-Fatiha of each rak'ah (shown in the clip too)
    struct Part { let surah: Int; let ayahs: [[Int]]; let words: [[[Int]]]; var rakah = false }
    var parts: [Part] = []
}

extension Repo {
    func trackTimes(_ id: String) async -> AyahTimes? {
        guard let u = URL(string: Repo.ajax + "?action=bz&do=track_times&id=" + Repo.enc(id)), let (d, _) = try? await session.data(from: u) else { return nil }
        let j = J(data: d)
        guard j["ok"].bool() else { return nil }
        let ay = j["ayahs"].array.map { $0.array.map { Int($0.double ?? 0) } }.filter { $0.count >= 3 }
        let w = j["words"].array.map { $0.array.map { $0.array.map { Int($0.double ?? 0) } }.filter { $0.count >= 2 } }
        func part(_ x: J, _ sur: Int?) -> AyahTimes.Part? {
            let sn = sur ?? Int(x["surah"].double ?? 0)
            let a = x["ayahs"].array.map { $0.array.map { Int($0.double ?? 0) } }.filter { $0.count >= 3 }
            guard (1...114).contains(sn), !a.isEmpty else { return nil }
            let ww = x["words"].array.map { $0.array.map { $0.array.map { Int($0.double ?? 0) } }.filter { $0.count >= 2 } }
            return AyahTimes.Part(surah: sn, ayahs: a, words: ww.count == a.count ? ww : [])
        }
        let parts = j["extra"].array.compactMap { part($0, nil) } + j["fatiha"].array.compactMap { x -> AyahTimes.Part? in var q = part(x, 1); q?.rakah = true; return q }
        return ay.isEmpty ? nil : AyahTimes(ayahs: ay, words: w, surah: Int(j["surah"].double ?? 0), url: j["url"].str, parts: parts)
    }
}

/// The text of an ayah as recited: the first ayah of every surah but al-Fatihah without the basmala in front.
func ayahClean(_ s: Int, _ a: Int, _ text: String) -> String {
    let t = text.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespaces)
    guard s != 1, a == 1 else { return t }
    let w = t.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    let bare = { (x: String) in x.replacingOccurrences(of: "[\\u0640\\u064B-\\u065F\\u0670\\u06D6-\\u06ED]", with: "", options: .regularExpression).replacingOccurrences(of: "ٱ", with: "ا") }
    if w.count > 4, bare(w.prefix(4).joined(separator: " ")) == "بسم الله الرحمن الرحيم" { return w.dropFirst(4).joined(separator: " ") }
    return t
}

/// Everything the person chose for the clip (kept between visits, like on the site).
struct ClipOpts: Codable, Equatable {
    var size = "auto", show = true, per = 4, num = true, font = "uthmani", color = "#fff7e6", fs = 64, anim = "fade", ty = -1.0, band = false
    var blur = 60, dark = 35, layout = "center", vscale = 100
    var name = true, sh = true, sur = true, brand = true, ipos = "bot", ifont = "plex", ifs = 100, icolor = "#f1d9a0"
    var lh = 175, wmax = 86, stroke = false, glow = 35
    var tfade = 0.5, vfi = 0.6, vfo = 0.8, afi = 1.0, afo = 1.5
    /// where the ayah text sits when moved by hand (0…1 of the width; -1 = the middle)
    var tx = -1.0
    /// the video moved by hand (part of the frame) and the names line moved by hand (0…1; -1 = its usual place), as on the site and Android
    var vx = 0.0, vy = 0.0, ix = -1.0, iy = -1.0
    /// the details as separate pieces (the sheikh's name, the surah, the site name), each with its own place, size, font and colour
    var isplit = false
    var L: [String: ILayer] = [:]
    func lay(_ k: String) -> ILayer { L[k] ?? ILayer(fs: ILayer.defFs(k)) }
    @MainActor static func load() -> ClipOpts { (try? JSONDecoder().decode(ClipOpts.self, from: Data(Store.shared.str("clipOpts").utf8))) ?? ClipOpts() }
    @MainActor func save() { if let d = try? JSONEncoder().encode(self), let s = String(data: d, encoding: .utf8) { Store.shared.set("clipOpts", s) } }
    init() {}
    init(from dec: Decoder) throws {   // a missing or new field keeps its default
        let c = try dec.container(keyedBy: CodingKeys.self); var o = ClipOpts()
        func g<T: Decodable>(_ k: CodingKeys, _ d: inout T) { if let v = try? c.decode(T.self, forKey: k) { d = v } }
        g(.size, &o.size); g(.show, &o.show); g(.per, &o.per); g(.num, &o.num); g(.font, &o.font); g(.color, &o.color); g(.fs, &o.fs); g(.anim, &o.anim); g(.band, &o.band)
        g(.blur, &o.blur); g(.dark, &o.dark); g(.layout, &o.layout); g(.vscale, &o.vscale); g(.name, &o.name); g(.sh, &o.sh); g(.sur, &o.sur); g(.brand, &o.brand)
        g(.ipos, &o.ipos); g(.ifont, &o.ifont); g(.ifs, &o.ifs); g(.icolor, &o.icolor); g(.lh, &o.lh); g(.wmax, &o.wmax); g(.stroke, &o.stroke); g(.glow, &o.glow)
        g(.tx, &o.tx); g(.ty, &o.ty); g(.tfade, &o.tfade); g(.vfi, &o.vfi); g(.vfo, &o.vfo); g(.afi, &o.afi); g(.afo, &o.afo)
        g(.vx, &o.vx); g(.vy, &o.vy); g(.ix, &o.ix); g(.iy, &o.iy); g(.isplit, &o.isplit); g(.L, &o.L)
        self = o
    }
}

/// One of the details placed on its own: position (0…1, -1 = its default), size (% of the shared size), font and colour ("" = the shared ones).
struct ILayer: Codable, Equatable {
    var x = -1.0, y = -1.0, fs = 100, font = "", color = ""
    init(x: Double = -1, y: Double = -1, fs: Int = 100, font: String = "", color: String = "") { self.x = x; self.y = y; self.fs = fs; self.font = font; self.color = color }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        x = (try? c.decode(Double.self, forKey: .x)) ?? -1; y = (try? c.decode(Double.self, forKey: .y)) ?? -1
        fs = (try? c.decode(Int.self, forKey: .fs)) ?? 100; font = (try? c.decode(String.self, forKey: .font)) ?? ""; color = (try? c.decode(String.self, forKey: .color)) ?? ""
    }
    static let keys = ["sh", "sur", "brand"]
    static func defFs(_ k: String) -> Int { k == "sh" ? 125 : k == "sur" ? 95 : 80 }
    static func defY(_ k: String) -> Double { k == "sh" ? 0.84 : k == "sur" ? 0.9 : 0.95 }
    static func label(_ k: String) -> String { k == "sh" ? tr("اسم الشيخ") : k == "sur" ? tr("السورة") : tr("اسم الموقع") }
}

/// Where each layer was drawn last in the preview (0…1 of the frame), so a finger can pick it.
final class ClipBoxes: @unchecked Sendable {
    private var d: [String: CGRect] = [:]; private let l = NSLock()
    func set(_ k: String, _ r: CGRect?) { guard Thread.isMainThread else { return }; l.lock(); d[k] = r; l.unlock() }
    var all: [String: CGRect] { l.lock(); defer { l.unlock() }; return d }
}

/// One part of an ayah on screen: its words, when each word is recited, and when the part shows and hides.
final class ClipSeg { let n: Int, toks: [String], wordT: [Double], start: Double, end: Double, last: Bool; var show = 0.0, hide = 0.0
    init(_ n: Int, _ toks: [String], _ wordT: [Double], _ start: Double, _ end: Double, _ last: Bool) { self.n = n; self.toks = toks; self.wordT = wordT; self.start = start; self.end = end; self.last = last }
}
struct ClipInfo { let sheikh: String, surah: String, brand: String }

enum ClipEngine {
    static let sizes: [(key: String, w: Int, h: Int, name: String)] = [("story", 1080, 1920, "ريلز / حالة"), ("square", 1080, 1080, "منشور"), ("wide", 1920, 1080, "يوتيوب")]
    static let colors = ["#fff7e6", "#f1d9a0", "#ffffff", "#9fe3d9", "#111111"]
    static let maxLen = 120.0, first = 30.0
    static let ayahFonts: [(String, String)] = [("uthmani", "عثماني"), ("amiri", "أميري"), ("scheh", "شهرزاد"), ("naskh", "نسخ")]
    static let infoFonts: [(String, String)] = [("plex", "عصري"), ("bold", "عريض"), ("amiriB", "أميري"), ("ruqaa", "رقعة"), ("kufi", "كوفي"), ("tajawal", "حديث"), ("lateef", "لطيف")]

    static func sizeKey(_ o: ClipOpts, _ vw: Double, _ vh: Double) -> String {
        if o.size != "auto" { return sizes.contains { $0.key == o.size } ? o.size : "story" }
        return vw > vh * 1.15 ? "wide" : vh > vw * 1.15 ? "story" : "square"
    }
    static func frame(_ o: ClipOpts, _ vw: Double, _ vh: Double) -> CGSize { let s = sizes.first { $0.key == sizeKey(o, vw, vh) }!; return CGSize(width: s.w, height: s.h) }

    /// fonts uploaded from the dashboard: "c:family" → the registered font's PostScript name
    nonisolated(unsafe) static var custom: [String: String] = [:]

    static func font(_ key: String, _ size: CGFloat) -> UIFont {
        let name: String
        if key.hasPrefix("c:"), let n = custom[key], let f = UIFont(name: n, size: size) { return f }
        switch key {
        case "uthmani": name = "KFGQPCHAFSUthmanicScript-Regula"
        case "amiri": name = "AmiriQuran-Regular"
        case "scheh": name = "ScheherazadeNew-Regular"
        case "ruqaa": name = "ArefRuqaa-Bold"
        case "kufi": name = "ReemKufi"
        case "tajawal": name = "Tajawal-Bold"
        case "lateef": name = "Lateef-Regular"
        case "naskh": name = "Amiri-Regular"
        case "bold": name = "IBMPlexSansArabic-Bold"
        case "amiriB": name = "Amiri-Bold"
        default: name = "IBMPlexSansArabic-SemiBold"
        }
        return UIFont(name: name, size: size) ?? UIFont(name: "Amiri-Regular", size: size) ?? .systemFont(ofSize: size)
    }

    /// Tanzil Uthmani text → the encoding the KFGQPC HAFS font expects (text already in that encoding is left as it is).
    static func qpc(_ t0: String) -> String {
        let t = t0.replacingOccurrences(of: "\u{FEFF}", with: "")
        if t.range(of: "[\u{06E1}\u{08F0}-\u{08F2}]", options: .regularExpression) != nil { return t }
        var s = t.replacingOccurrences(of: "\\s*\u{06D9}", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+([\u{06D6}-\u{06DC}])", with: "$1", options: .regularExpression)
        s = String(s.unicodeScalars.map { u -> Character in
            switch u { case "\u{0652}": return "\u{06E1}"; case "\u{06DF}": return "\u{0652}"; case "\u{06EB}": return "\u{06EC}"; case "\u{06EA}": return "\u{065C}"; default: return Character(u) }
        })
        return s.replacingOccurrences(of: "\u{064B}\u{06ED}", with: "\u{08F0}").replacingOccurrences(of: "\u{064C}\u{06ED}", with: "\u{08F1}").replacingOccurrences(of: "\u{064D}\u{06E2}", with: "\u{08F2}")
    }

    private static func isMark(_ w: String) -> Bool { w.range(of: "[ء-يٱ-ۓ]", options: .regularExpression) == nil }
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        for w in text.replacingOccurrences(of: "\u{FEFF}", with: "").split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            if isMark(w), !out.isEmpty { out[out.count - 1] += " " + w } else { out.append(w) }
        }
        return out
    }
    private static func letters(_ w: String) -> Int { w.unicodeScalars.filter { (0x621...0x64A).contains($0.value) || (0x671...0x6D3).contains($0.value) }.count }
    /// A word's time from its share of the ayah's letters (so a skipped word cannot shift the parts); older [startMs, endMs] used as they are.
    static func wordStarts(_ toks: [String], _ wt: [[Int]]?, _ s: Double, _ e: Double) -> [Double] {
        if let wt, !wt.isEmpty, wt[0].count >= 2, wt.allSatisfy({ $0[0] > 1000 || Double($0[0]) >= s * 1000 - 50 }), Double(wt[0][0]) >= s * 1000 - 50, wt.count == toks.count {
            return wt.map { Double($0[0]) / 1000 }
        }
        let frac = wt.map { !$0.isEmpty && $0.allSatisfy { $0.count >= 2 && (0...1000).contains($0[0]) } } ?? false
        let L = toks.map(letters), tot = max(1, L.reduce(0, +))
        var acc = 0; let share = L.map { n -> Double in let f = Double(acc) / Double(tot); acc += n; return f }
        var pts: [(Double, Double)] = [(0, s * 1000)]
        if frac, let wt {
            for p in wt.map({ (min(1, max(0, Double($0[0]) / 1000)), Double($0[1])) }).sorted(by: { $0.0 < $1.0 }) {
                let last = pts[pts.count - 1]; if p.0 > last.0 && p.1 >= last.1 && p.1 <= e * 1000 { pts.append(p) }
            }
        }
        pts.append((1, max(pts[pts.count - 1].1, e * 1000)))
        func at(_ f: Double) -> Double {
            if f <= pts[0].0 { return pts[0].1 }
            for i in 1..<pts.count where f <= pts[i].0 { let (f0, t0) = pts[i - 1], (f1, t1) = pts[i]; return t0 + (t1 - t0) * (f1 > f0 ? (f - f0) / (f1 - f0) : 0) }
            return pts[pts.count - 1].1
        }
        return share.map { at($0) / 1000 }
    }
    /// [others]: the other parts heard (the next surahs, al-Fatiha of each rak'ah) with their ayah texts, shown like the main ones
    static func buildSegs(_ times: AyahTimes?, _ text: [Int: String], _ t0: Double, _ t1: Double, _ per0: Int, _ modes: [Int: String], others: [(AyahTimes.Part, [Int: String])] = []) -> [ClipSeg] {
        guard let times else { return [] }
        var segs: [ClipSeg] = []
        let per = max(2, per0)
        let all: [(ayahs: [[Int]], words: [[[Int]]], text: [Int: String], main: Bool)] = [(times.ayahs, times.words, text, true)] + others.map { ($0.0.ayahs, $0.0.words, $0.1, false) }
        for src in all { for (i, a) in src.ayahs.enumerated() {
            let n = a[0], s = Double(a[1]) / 1000, e = Double(a[2]) / 1000
            if e < t0 - 0.2 || s > t1 + 0.2 { continue }
            guard let tx = src.text[n] else { continue }
            let toks = tokens(tx); if toks.isEmpty { continue }
            let w = i < src.words.count && !src.words[i].isEmpty ? src.words[i] : nil
            let wordT = wordStarts(toks, w, s, e)
            // «كاملة / أجزاء» is chosen per ayah of the main surah; the other parts are shown whole
            if !src.main || (modes[n] ?? "whole") == "whole" || toks.count <= per { segs.append(ClipSeg(n, toks, wordT, s, e, true)) }
            else {
                // even parts (no lonely last word)
                let cnt = max(1, Int((Double(toks.count) / Double(per)).rounded())), size = Double(toks.count) / Double(cnt)
                for p in 0..<cnt {
                    let k = Int((Double(p) * size).rounded()), j = Int((Double(p + 1) * size).rounded())
                    segs.append(ClipSeg(n, Array(toks[k..<j]), Array(wordT[k..<j]), p == 0 ? s : wordT[k], j == toks.count ? e : wordT[j], j == toks.count))
                }
            }
        } }
        segs.sort { $0.start < $1.start }
        for (i, g) in segs.enumerated() {
            let nx = i + 1 < segs.count ? segs[i + 1] : nil
            g.show = g.start - 0.15
            g.hide = nx.map { min($0.start - 0.15, max(g.end + 1.2, $0.start - 0.15)) } ?? g.end + 1.2
        }
        return segs
    }

    /// where the video sits in the W×H frame
    static func geometry(_ o: ClipOpts, _ W: Double, _ H: Double, _ vw: Double, _ vh: Double) -> CGRect {
        var w: Double, h: Double
        if o.layout == "fill" { let s = max(W / vw, H / vh); w = vw * s; h = vh * s }
        else { w = W * Double(min(100, o.vscale)) / 100; h = w * vh / vw; if h > H * 0.92 { h = H * 0.92; w = h * vw / vh } }
        if o.vscale > 100 { let z = Double(o.vscale) / 100; w *= z; h *= z }
        // moved by the finger (or zoomed past the frame to hide a printed name or logo)
        return CGRect(x: (W - w) / 2 + o.vx * W, y: (H - h) / 2 + o.vy * H, width: w, height: h)
    }
    static func smooth(_ x0: Double) -> Double { let x = min(1, max(0, x0)); return x * x * x * (x * (x * 6 - 15) + 10) }
    /// A fade the ear hears as even (steady in decibels).
    static func fadeCurve(_ x: Double) -> Double { x <= 0 ? 0 : x >= 1 ? 1 : max(0, (pow(10, 2 * (x - 1)) - 0.01) / 0.99) }
    static func voiceSpan(_ segs: [ClipSeg], _ t0: Double, _ t1: Double) -> (Double, Double) {
        let vs = segs.filter { $0.start >= t0 - 0.05 && $0.start <= t0 + 2 }.map(\.start).min().map { max($0, t0) } ?? t0
        let ve = segs.filter { $0.end <= t1 + 0.05 && $0.end >= t1 - 2.5 }.map(\.end).max().map { min($0, t1) } ?? t1
        return (vs, ve)
    }
    static func gainAt(_ o: ClipOpts, _ t: Double, _ t0: Double, _ t1: Double, _ span: (Double, Double)) -> Double {
        var g = 1.0
        // the voice itself is never faded: the sound rises before the first word and falls after the last one
        // (the fall began before the last ayah ended, and its last words were lost)
        if o.afi > 0 { let len = max(0.05, min(o.afi, span.0 - t0)); g = min(g, fadeCurve((t - t0) / len)) }
        if o.afo > 0 { let st = max(span.1 + 0.1, t1 - o.afo); if t > st { g = min(g, t >= t1 ? 0 : fadeCurve((t1 - t) / max(0.05, t1 - st))) } }
        return min(1, max(0, g))
    }
    static let boxes = ClipBoxes()
    /// the names line's y (0…1), so a drag can grab it
    static func infoY(_ o: ClipOpts, _ W: Double, _ H: Double) -> Double {
        let fs = min(W, H) * 0.028 * Double(o.ifs) / 100
        if o.iy >= 0 { return o.iy }
        return o.ipos == "top" ? max(fs * 2.6, H * 0.055) / H : (H - max(fs * 2.6, H * 0.055)) / H
    }
    static func infoText(_ o: ClipOpts, _ i: ClipInfo) -> String {
        guard o.name, !o.isplit else { return "" }
        return [o.sh ? i.sheikh : "", o.sur ? i.surah : "", o.brand ? i.brand : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    static func color(_ hex: String, _ a: Double = 1) -> UIColor {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let n = Int(h, radix: 16) else { return UIColor(white: 1, alpha: a) }
        return UIColor(red: CGFloat(n >> 16) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: a)
    }
    private static func arDigits(_ n: Int) -> String { n.ar }

    /// Draws everything above the video at time t (source seconds), in a W×H frame with a top-left origin: the dimming around
    /// the video, the ayah part being recited, the names line and the fade from / to black. Same drawing for preview and export.
    static func drawOverlay(_ cg: CGContext, _ o: ClipOpts, W: Double, H: Double, vw: Double, vh: Double, t: Double, segs: [ClipSeg], info: ClipInfo, t0: Double?, t1: Double?) {
        let g = geometry(o, W, H, vw, vh)
        UIGraphicsPushContext(cg); defer { UIGraphicsPopContext() }
        let dark = Double(o.dark) / 100 * (o.layout == "fill" ? 0.9 : 1)
        cg.setFillColor(UIColor(white: 0, alpha: dark).cgColor)
        if o.layout == "fill" { cg.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
        else {
            let p = CGMutablePath(); p.addRect(CGRect(x: 0, y: 0, width: W, height: H)); p.addRect(g); cg.addPath(p); cg.fillPath(using: .evenOdd)
            // the video too (a little less than the background), so the ayahs read clearly when the video fills the frame
            cg.setFillColor(UIColor(white: 0, alpha: dark * 0.75).cgColor); cg.fill(g)
        }
        boxes.set("video", CGRect(x: g.minX / W, y: g.minY / H, width: g.width / W, height: g.height / H))
        if o.show, let s = segs.first(where: { t >= $0.show && t < $0.hide }) { drawAyah(cg, o, W, H, t, g, s) } else { boxes.set("ayah", nil) }
        /// one line of text centred at (cx, y), kept inside the frame; returns its box (0…1)
        func label(_ txt: String, _ fk: String, _ fs: Double, _ col: String, _ x0: Double, _ y: Double) -> CGRect {
            let sh = NSShadow(); sh.shadowBlurRadius = fs * 0.6; sh.shadowColor = UIColor(white: 0, alpha: 0.59); sh.shadowOffset = .zero
            let a = NSAttributedString(string: txt, attributes: [.font: font(fk, fs), .foregroundColor: color(col, 0.92), .shadow: sh])
            let sz = a.size(); let tw = min(sz.width, W * 0.94)
            let cx = x0 >= 0 ? min(max(tw / 2 + W * 0.02, W - tw / 2 - W * 0.02), max(tw / 2 + W * 0.02, x0 * W)) : W / 2
            let yy = min(max(fs, H - fs), max(fs, y))
            a.draw(in: CGRect(x: cx - tw / 2, y: yy - sz.height / 2, width: tw, height: sz.height))
            return CGRect(x: (cx - tw / 2) / W, y: (yy - fs) / H, width: tw / W, height: fs * 2 / H)
        }
        let line = infoText(o, info)
        if !line.isEmpty {
            let fs = min(W, H) * 0.028 * Double(o.ifs) / 100
            boxes.set("info", label(line, o.ifont, fs, o.icolor, o.ix, infoY(o, W, H) * H))
        } else { boxes.set("info", nil) }
        // the details as separate pieces: each in its own place, size, font and colour
        for k in ILayer.keys {
            let txt = k == "sh" ? (o.sh ? info.sheikh : "") : k == "sur" ? (o.sur ? info.surah : "") : (o.brand ? info.brand : "")
            guard o.name, o.isplit, !txt.isEmpty else { boxes.set("i_" + k, nil); continue }
            let L = o.lay(k)
            let fk = L.font.isEmpty || (L.font.hasPrefix("c:") && custom[L.font] == nil) ? o.ifont : L.font
            let base: Double = min(W, H) * 0.028 * Double(o.ifs) / 100
            let fs: Double = base * Double(L.fs) / 100
            let col: String = L.color.isEmpty ? o.icolor : L.color
            let yy: Double = (L.y >= 0 ? L.y : ILayer.defY(k)) * H
            boxes.set("i_" + k, label(txt, fk, fs, col, L.x, yy))
        }
        if let t0, let t1 {
            let bk = max(o.vfi > 0 ? 1 - smooth((t - t0) / o.vfi) : 0, o.vfo > 0 ? 1 - smooth((t1 - t) / o.vfo) : 0)
            if bk > 0.001 { cg.setFillColor(UIColor(white: 0, alpha: min(1, bk)).cgColor); cg.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
        }
    }

    nonisolated(unsafe) private static var widthCache: [String: Double] = [:]
    /// where the ayah text's centre is (0…1), for moving it by hand
    static func ayahCenter(_ o: ClipOpts, _ W: Double, _ H: Double, _ vw: Double, _ vh: Double) -> CGPoint {
        let g = geometry(o, W, H, vw, vh)
        let defTy = o.layout == "fill" || W > H * 1.15 ? 0.8 : min(0.86, (g.maxY + H) / 2 / H)
        return CGPoint(x: o.tx >= 0 ? o.tx : 0.5, y: o.ty >= 0 ? o.ty : defTy)
    }
    /// one part of an ayah; a part fades out while the next one fades in (never two texts on top of each other)
    private static func drawAyah(_ cg: CGContext, _ o: ClipOpts, _ W: Double, _ H: Double, _ t: Double, _ g: CGRect, _ seg: ClipSeg) {
        let fd = min(1.2, max(0.15, o.tfade)), len = seg.hide - seg.show
        let inK = smooth((t - seg.show) / min(fd, len * 0.4)), outK = smooth((seg.hide - t) / min(fd * 0.8, len * 0.35)), a = min(inK, outK)
        if a <= 0 { return }
        let scale = min(W, H) / 1080
        var fs = Double(o.fs) * scale * (sizeKey(o, W, H) == "wide" || W > H * 1.15 ? 0.9 : 1)
        var f = font(o.font, fs), nf = font("amiri", fs * 0.82)
        let glow = Double(o.glow) / 100
        let shadow = NSShadow(); shadow.shadowBlurRadius = fs * (0.1 + 0.6 * glow); shadow.shadowOffset = CGSize(width: 0, height: fs * 0.05)
        var toks = seg.toks; let withNum = o.num && seg.last; if withNum { toks.append("﴿\(seg.n.qar)﴾") }
        func attrs(_ col: UIColor, _ al: Double, _ font: UIFont) -> [NSAttributedString.Key: Any] {
            let s = NSShadow(); s.shadowBlurRadius = shadow.shadowBlurRadius; s.shadowOffset = shadow.shadowOffset; s.shadowColor = UIColor(white: 0, alpha: (90 + 130 * glow) / 255 * al)
            return [.font: font, .foregroundColor: col.withAlphaComponent(CGFloat(al)), .shadow: s]
        }
        let base = color(o.color)
        var space = NSAttributedString(string: " ", attributes: [.font: f]).size().width
        func numberParts() -> (open: NSAttributedString, digits: NSAttributedString, close: NSAttributedString) {
            let at: [NSAttributedString.Key: Any] = [.font: nf]
            return (NSAttributedString(string: "\u{FD3E}", attributes: at), NSAttributedString(string: seg.n.ar, attributes: at), NSAttributedString(string: "\u{FD3F}", attributes: at))
        }
        func width(_ i: Int) -> Double {
            let key = "\(o.font)|\(Int(fs * 10))|\(withNum && i == toks.count - 1 ? "#\(seg.n)" : toks[i])"
            if let w = widthCache[key] { return w }
            let w: Double
            if withNum && i == toks.count - 1 { let p = numberParts(); w = p.open.size().width * 2 + p.digits.size().width + fs * 0.12 }
            else { w = NSAttributedString(string: toks[i], attributes: [.font: f]).size().width }
            if widthCache.count > 4000 { widthCache.removeAll() }
            widthCache[key] = w; return w
        }
        let maxW = W * Double(o.wmax) / 100
        var lines: [[(tk: String, w: Double, i: Int)]] = []
        // a long ayah gets a smaller size so the whole of it fits in the frame (it ran off the top and the bottom)
        for _ in 0..<8 {
            lines = []; var cur: [(tk: String, w: Double, i: Int)] = []; var lw = 0.0
            for (i, tk) in toks.enumerated() { let tw = width(i); if !cur.isEmpty && lw + space + tw > maxW { lines.append(cur); cur = []; lw = 0 }; cur.append((tk, tw, i)); lw += (lw > 0 ? space : 0) + tw }
            if !cur.isEmpty { lines.append(cur) }
            if Double(lines.count) * fs * Double(o.lh) / 100 <= H * 0.8 || fs < 14 { break }
            fs *= 0.88; f = font(o.font, fs); nf = font("amiri", fs * 0.82); space = NSAttributedString(string: " ", attributes: [.font: f]).size().width
        }
        let widths = lines.map { l in l.reduce(0) { $0 + $1.w } + space * Double(l.count - 1) }
        let lh = fs * Double(o.lh) / 100, total = Double(lines.count) * lh, mw = widths.max() ?? 0
        let defTy = o.layout == "fill" || W > H * 1.15 ? 0.8 : min(0.86, (g.maxY + H) / 2 / H)
        let ty = (o.ty >= 0 ? o.ty : defTy) * H
        let cx = o.tx >= 0 ? min(W - mw / 2 - W * 0.02, max(mw / 2 + W * 0.02, o.tx * W)) : W / 2
        var y = min(H - total / 2 - H * 0.03, max(total / 2 + H * 0.03, ty)) - total / 2 + lh / 2
        let top = y - lh / 2
        boxes.set("ayah", CGRect(x: (cx - mw / 2) / W, y: top / H, width: mw / W, height: total / H))
        let dy = o.anim == "slide" ? (1 - inK) * fs * 0.8 : 0
        cg.saveGState()
        if o.anim == "zoom" && inK < 1 { let z = 0.86 + 0.14 * inK, c = CGPoint(x: cx, y: top + total / 2); cg.translateBy(x: c.x, y: c.y); cg.scaleBy(x: z, y: z); cg.translateBy(x: -c.x, y: -c.y) }
        if o.band {
            let bw = mw + fs * 1.4, bh = total + fs * 0.6
            cg.setFillColor(UIColor(white: 0, alpha: a * 0.55).cgColor)
            cg.addPath(UIBezierPath(roundedRect: CGRect(x: cx - bw / 2, y: top - fs * 0.3 + dy, width: bw, height: bh), cornerRadius: fs * 0.5).cgPath); cg.fillPath()
        }
        for (li, l) in lines.enumerated() {
            var x = cx + widths[li] / 2   // right to left
            for it in l {
                var al = a; var col = base
                if o.anim == "words", it.i < seg.wordT.count {
                    let said = t >= seg.wordT[it.i] - 0.05; al = a * (said ? 1 : 0.32)
                    if said && t < seg.wordT[it.i] + 0.45 { col = UIColor(red: 241 / 255, green: 217 / 255, blue: 160 / 255, alpha: 1) }
                }
                let isNum = withNum && it.i == toks.count - 1
                if isNum {
                    let p = numberParts(), at = attrs(col, al, nf)
                    let ow = p.open.size().width, dw = p.digits.size().width, h0 = p.digits.size().height
                    let yy = y + dy - h0 / 2, x0 = x - it.w
                    // left to right on screen: ﴾ (opens toward the number), the digits, ﴿
                    NSAttributedString(string: "\u{FD3E}", attributes: at).draw(at: CGPoint(x: x0, y: yy))
                    NSAttributedString(string: seg.n.ar, attributes: at).draw(at: CGPoint(x: x0 + ow + fs * 0.06, y: yy))
                    NSAttributedString(string: "\u{FD3F}", attributes: at).draw(at: CGPoint(x: x0 + ow + fs * 0.12 + dw, y: yy))
                } else {
                    let s = NSAttributedString(string: it.tk, attributes: attrs(col, al, f)); let h0 = s.size().height
                    if o.stroke {
                        let sc = o.color == "#111111" ? UIColor.white : UIColor.black
                        NSAttributedString(string: it.tk, attributes: [.font: f, .strokeColor: sc.withAlphaComponent(CGFloat(al * 0.9)), .strokeWidth: 16]).draw(at: CGPoint(x: x - it.w, y: y + dy - h0 / 2))
                    }
                    s.draw(at: CGPoint(x: x - it.w, y: y + dy - h0 / 2))
                }
                x -= it.w + space
            }
            y += lh
        }
        cg.restoreGState()
    }
}

// MARK: - export

/// Makes the MP4 on the phone: the part [t0, t1], at the chosen size, the soft blurred background, the sharp video and
/// the ayahs and names drawn on each frame; the sound rises and falls with the chosen fades.
/// Calls its closure once, however many times done() is called.
final class OnceDone { private var f: (() -> Void)?; private let l = NSLock(); init(_ f: @escaping () -> Void) { self.f = f }
    func done() { l.lock(); let g = f; f = nil; l.unlock(); g?() } }

final class ClipExporter {
    private var cancelled = false
    func cancel() { cancelled = true }

    func run(src: URL, o: ClipOpts, vw: Double, vh: Double, t0: Double, t1: Double, segs: [ClipSeg], info: ClipInfo,
             progress: @escaping (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: src)
        guard let vTrack = try await asset.loadTracks(withMediaType: .video).first else { throw NSError(domain: "clip", code: 1) }
        let aTrack = try await asset.loadTracks(withMediaType: .audio).first
        let nat = try await vTrack.load(.naturalSize), tf = try await vTrack.load(.preferredTransform)
        let rs = CGRect(origin: .zero, size: nat).applying(tf); let srcW = abs(rs.width), srcH = abs(rs.height)
        let size = ClipEngine.frame(o, vw > 0 ? vw : srcW, vh > 0 ? vh : srcH)
        let W = Int(size.width), H = Int(size.height)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("badr-clip-\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: out)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: t0, preferredTimescale: 600), end: CMTime(seconds: t1, preferredTimescale: 600))
        let vOut = AVAssetReaderTrackOutput(track: vTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        vOut.alwaysCopiesSampleData = false
        reader.add(vOut)
        var aOut: AVAssetReaderTrackOutput?
        if let aTrack {
            let ao = AVAssetReaderTrackOutput(track: aTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                                                                               AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2])
            reader.add(ao); aOut = ao
        }
        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
                                                                          AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: W * H * 4, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
        vIn.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
        writer.add(vIn)
        var aIn: AVAssetWriterInput?
        if aOut != nil {
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 160_000])
            ai.expectsMediaDataInRealTime = false; writer.add(ai); aIn = ai
        }
        guard reader.startReading() else { throw reader.error ?? NSError(domain: "clip", code: 2) }
        writer.startWriting(); writer.startSession(atSourceTime: .zero)

        let ci = CIContext(options: [.cacheIntermediates: false])
        let g = ClipEngine.geometry(o, Double(W), Double(H), vw > 0 ? vw : srcW, vh > 0 ? vh : srcH)
        let span = ClipEngine.voiceSpan(segs, t0, t1)
        let dur = t1 - t0
        let cs = CGColorSpaceCreateDeviceRGB()
        var lastRel = -1.0

        // video and sound are fed side by side (the writer interleaves them; feeding one alone would stall it)
        await withCheckedContinuation { (all: CheckedContinuation<Void, Never>) in
        let group = DispatchGroup()
        group.enter()
        do {
            let k = OnceDone { group.leave() }
            let q = DispatchQueue(label: "clip.video")
            vIn.requestMediaDataWhenReady(on: q) { [self] in
                while vIn.isReadyForMoreMediaData {
                    if cancelled { vIn.markAsFinished(); k.done(); return }
                    guard let sb = vOut.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(sb) else { vIn.markAsFinished(); k.done(); return }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
                    let t = pts, rel = pts - t0
                    // a frame before the part, or at a time already written, is skipped (two frames at one time break the file)
                    if rel < -0.001 || rel <= lastRel { continue }
                    lastRel = rel
                    autoreleasepool {
                        var img = CIImage(cvPixelBuffer: pb).transformed(by: tf)
                        img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
                        let full = CGRect(x: 0, y: 0, width: W, height: H)
                        // the soft background: the frame stretched over the whole canvas and blurred
                        let bg = img.transformed(by: CGAffineTransform(scaleX: CGFloat(W) / img.extent.width, y: CGFloat(H) / img.extent.height))
                            .clampedToExtent().applyingGaussianBlur(sigma: max(0.6, 2 + Double(o.blur) * 0.45) * Double(W) / 360).cropped(to: full)
                        // the sharp frame in its place (CoreImage's origin is at the bottom)
                        let fg = img.transformed(by: CGAffineTransform(scaleX: g.width / img.extent.width, y: g.height / img.extent.height))
                            .transformed(by: CGAffineTransform(translationX: g.minX, y: CGFloat(H) - g.maxY))
                        var comp = o.layout == "fill" ? fg.cropped(to: full) : fg.composited(over: bg).cropped(to: full)
                        // the overlay, drawn with the same code as the preview
                        let r = UIGraphicsImageRendererFormat(); r.scale = 1; r.opaque = false
                        let ov = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: r).image { c in
                            ClipEngine.drawOverlay(c.cgContext, o, W: Double(W), H: Double(H), vw: vw > 0 ? vw : srcW, vh: vh > 0 ? vh : srcH, t: t, segs: segs, info: info, t0: t0, t1: t1)
                        }
                        if let cgi = ov.cgImage { comp = CIImage(cgImage: cgi).composited(over: comp) }
                        var outPB: CVPixelBuffer?
                        if let pool = adaptor.pixelBufferPool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outPB) }
                        if let outPB {
                            ci.render(comp, to: outPB, bounds: full, colorSpace: cs)
                            adaptor.append(outPB, withPresentationTime: CMTime(seconds: max(0, rel), preferredTimescale: 6000))
                        }
                    }
                    progress(min(0.99, rel / max(0.1, dur)))
                }
            }
        }
        if let aOut, let aIn {
            group.enter()
            let k = OnceDone { group.leave() }
                aIn.requestMediaDataWhenReady(on: DispatchQueue(label: "clip.audio")) { [self] in
                    while aIn.isReadyForMoreMediaData {
                        if cancelled { aIn.markAsFinished(); k.done(); return }
                        guard let sb = aOut.copyNextSampleBuffer() else { aIn.markAsFinished(); k.done(); return }
                        let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
                        if pts < t0 - 0.001 { continue }
                        if let bb = CMSampleBufferGetDataBuffer(sb) {
                            var len = 0; var ptr: UnsafeMutablePointer<CChar>?
                            if CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr) == kCMBlockBufferNoErr, let ptr {
                                let n = len / 4   // 16-bit stereo frames
                                ptr.withMemoryRebound(to: Int16.self, capacity: n * 2) { s in
                                    for f in 0..<n {
                                        let t = pts + Double(f) / 44100, rel = t - t0
                                        let gain = ClipEngine.gainAt(o, t, t0, t1, span) * max(0, min(1, min(rel / 0.02, (dur - rel) / 0.02)))
                                        s[2 * f] = Int16(max(-32768, min(32767, Double(s[2 * f]) * gain)))
                                        s[2 * f + 1] = Int16(max(-32768, min(32767, Double(s[2 * f + 1]) * gain)))
                                    }
                                }
                            }
                        }
                        if let shifted = Self.shift(sb, by: -t0) { aIn.append(shifted) }
                    }
                }
        }
        group.notify(queue: .main) { all.resume() }
        }
        reader.cancelReading()
        if cancelled { writer.cancelWriting(); throw CancellationError() }
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? NSError(domain: "clip", code: 3) }
        progress(1)
        return out
    }
    private static func shift(_ sb: CMSampleBuffer, by s: Double) -> CMSampleBuffer? {
        var n: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sb, entryCount: 0, arrayToFill: nil, entriesNeededOut: &n)
        var info = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: n)
        CMSampleBufferGetSampleTimingInfoArray(sb, entryCount: n, arrayToFill: &info, entriesNeededOut: &n)
        for i in 0..<n { info[i].presentationTimeStamp = CMTimeAdd(info[i].presentationTimeStamp, CMTime(seconds: s, preferredTimescale: 44100)); info[i].decodeTimeStamp = .invalid }
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sb, sampleTimingEntryCount: n, sampleTimingArray: &info, sampleBufferOut: &out)
        return out
    }
}

// MARK: - preview

/// The preview: the video's blurred copy behind, the sharp video in its place and the overlay drawn on top every frame.
final class ClipPreviewView: UIView {
    let player: AVPlayer
    private let bgLayer = AVPlayerLayer(), fgLayer = AVPlayerLayer()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let overlay = OverlayView()
    private var link: CADisplayLink?
    var model: (() -> (o: ClipOpts, vw: Double, vh: Double, segs: [ClipSeg], info: ClipInfo, t0: Double, t1: Double, sel: String))?
    init(player: AVPlayer) {
        self.player = player
        super.init(frame: .zero)
        backgroundColor = .black; clipsToBounds = true
        bgLayer.player = player; bgLayer.videoGravity = .resizeAspectFill
        fgLayer.player = player; fgLayer.videoGravity = .resize
        layer.addSublayer(bgLayer); addSubview(blur); layer.addSublayer(fgLayer); addSubview(overlay)
        overlay.backgroundColor = .clear; overlay.isOpaque = false
        link = CADisplayLink(target: self, selector: #selector(tick)); link?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60); link?.add(to: .main, forMode: .common)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { link?.invalidate() }
    override func removeFromSuperview() { link?.invalidate(); link = nil; super.removeFromSuperview() }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        bgLayer.frame = bounds; blur.frame = bounds; overlay.frame = bounds
        if let m = model?() {
            let F = ClipEngine.frame(m.o, m.vw, m.vh), k = bounds.width / F.width
            let g = ClipEngine.geometry(m.o, F.width, F.height, m.vw, m.vh)
            fgLayer.frame = CGRect(x: g.minX * k, y: g.minY * k, width: g.width * k, height: g.height * k)
            blur.alpha = m.o.layout == "fill" ? 0 : min(1, 0.35 + Double(m.o.blur) / 100)
        }
        CATransaction.commit()
    }
    @objc private func tick() {
        guard let m = model?() else { return }
        let t = player.currentTime().seconds
        if player.rate > 0, t >= m.t1 { player.seek(to: CMTime(seconds: m.t0, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
        // the preview sounds as the saved clip will (its fades)
        if t.isFinite { player.volume = Float(ClipEngine.gainAt(m.o, t, m.t0, m.t1, ClipEngine.voiceSpan(m.segs, m.t0, m.t1))) }
        let paused = player.rate == 0
        overlay.draw = { cg, size in
            let F = ClipEngine.frame(m.o, m.vw, m.vh), k = size.width / F.width
            cg.scaleBy(x: k, y: k)
            ClipEngine.drawOverlay(cg, m.o, W: F.width, H: F.height, vw: m.vw, vh: m.vh, t: t.isFinite ? t : m.t0, segs: m.segs, info: m.info, t0: m.t0, t1: m.t1)
            // like a design app: the piece being moved has a dashed frame (while paused)
            if paused, !m.sel.isEmpty, let b = ClipEngine.boxes.all[m.sel] {
                let pad = 8 / k
                cg.setStrokeColor(UIColor(red: 241 / 255, green: 217 / 255, blue: 160 / 255, alpha: 1).cgColor); cg.setLineWidth(2 / k); cg.setLineDash(phase: 0, lengths: [12 / k, 9 / k])
                cg.stroke(CGRect(x: b.minX * F.width - pad, y: b.minY * F.height - pad, width: b.width * F.width + pad * 2, height: b.height * F.height + pad * 2))
            }
        }
        overlay.setNeedsDisplay()
    }
    final class OverlayView: UIView {
        var draw: ((CGContext, CGSize) -> Void)?
        override func draw(_ rect: CGRect) { if let c = UIGraphicsGetCurrentContext() { draw?(c, bounds.size) } }
    }
}
private struct ClipPreview: UIViewRepresentable {
    let player: AVPlayer
    let model: () -> (o: ClipOpts, vw: Double, vh: Double, segs: [ClipSeg], info: ClipInfo, t0: Double, t1: Double, sel: String)
    func makeUIView(context: Context) -> ClipPreviewView { let v = ClipPreviewView(player: player); v.model = model; return v }
    func updateUIView(_ v: ClipPreviewView, context: Context) { v.model = model; v.setNeedsLayout() }
}

// MARK: - the screen

/// «اصنع مقطعًا»: a share-ready clip from a video recitation, made on the phone; the recited ayahs appear by themselves
/// from the recitation's analysis, over the video with a soft blurred background.
struct ClipView: View {
    /// the fonts uploaded from the dashboard, for the ayahs or the names (as on the site and Android)
    private func customFonts(_ use: String) -> [(String, String)] {
        (repo.data?.site.j["maker"]["fonts"].array ?? []).compactMap { f -> (String, String)? in
            let fam = f["family"].str, u = f["use"].str.isEmpty ? "ayah" : f["use"].str
            guard !fam.isEmpty, !f["url"].str.isEmpty, u == use || u == "both" else { return nil }
            return ("c:" + fam, f["name"].str.isEmpty ? fam : f["name"].str)
        }
    }
    /// downloads and registers the custom fonts in use, then redraws
    private func loadCustomFonts() async {
        for k in [o.font, o.ifont] + o.L.values.map(\.font) where k.hasPrefix("c:") && ClipEngine.custom[k] == nil {
            let fam = String(k.dropFirst(2))
            guard let f = (repo.data?.site.j["maker"]["fonts"].array ?? []).first(where: { $0["family"].str == fam }), let u = Repo.media(f["url"].str) else { continue }
            if let n = await registerFont(u, key: fam) { ClipEngine.custom[k] = n; fontRev += 1 } else { ui.say(tr("تعذّر تحميل الخط")) }
        }
    }
    let trackId: String
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var o = ClipOpts.load()
    @State private var fontRev = 0
    @State private var player = AVPlayer()
    @State private var times: AyahTimes?
    @State private var texts: [Int: String] = [:]
    @State private var surahNo = 0
    @State private var loading = true
    @State private var dur = 30.0
    @State private var t0 = 0.0
    @State private var t1 = 30.0
    @State private var tab = "part"
    @State private var playing = false
    @State private var modes: [Int: String] = [:]
    @State private var names: [String: String] = [:]
    @State private var exporting: Double?
    @State private var exporter: ClipExporter?
    @State private var done: URL?
    /// the ayah parts, made again only when something they depend on changes (they were made on every redraw)
    @State private var segsC: [ClipSeg] = []
    @State private var dragFrom: CGPoint?
    @State private var pinchFrom: Int?
    /// the piece the finger holds: "ayah", "info", "i_sh" / "i_sur" / "i_brand", "video"
    @State private var sel = ""
    @State private var dragKey: String?
    @State private var pinchKey: String?
    /// the details piece edited in «البيانات» (when each one has its own place)
    @State private var ied = "sh"
    /// the other parts of the recording (the next surahs, al-Fatiha) with their texts
    @State private var others: [(AyahTimes.Part, [Int: String])] = []
    @State private var saveTask: Task<Void, Never>?

    private var t: Track? { repo.track(trackId).flatMap { $0.isVideo ? $0 : nil } }
    private var vw: Double { Double(t?.video?.w ?? 0) > 0 ? Double(t!.video!.w) : 16 }
    private var vh: Double { Double(t?.video?.h ?? 0) > 0 ? Double(t!.video!.h) : 9 }
    /// the source: the copy saved on the phone, else a rendition up to 720p (light to play and to process)
    private var src: URL? {
        guard let t, let v = t.video else { return nil }
        if let l = VideoFiles.local(t.id) { return l }
        let q = v.q.filter { (1...720).contains($0.h) }.max { $0.h < $1.h } ?? v.q.min { $0.h < $1.h } ?? v.q[0]
        return Repo.media(q.url)
    }
    private var segs: [ClipSeg] { segsC }
    private var segsKey: String { "\(times?.ayahs.count ?? 0)|\(texts.count)|\(others.count)|\(t0)|\(t1)|\(o.per)|\(o.font)|\(modes)" }
    private func makeSegs() -> [ClipSeg] {
        let q = o.font == "uthmani"
        return ClipEngine.buildSegs(times, q ? texts.mapValues(ClipEngine.qpc) : texts, t0, t1, o.per, modes, others: q ? others.map { ($0.0, $0.1.mapValues(ClipEngine.qpc)) } : others)
    }
    private var info: ClipInfo {
        let r = repo.reciter(t?.reciterId)?.shown ?? ""
        let s = (1...114).contains(surahNo) ? tr("سورة {0}", Quran.surahs[surahNo - 1]) : (t?.surah ?? "").isEmpty ? "" : ((t?.surah ?? "").hasPrefix("سورة") ? t!.surah : tr("سورة {0}", t!.surah))
        let b = repo.data?.site.title ?? tr("بدر التلاوات")
        func n(_ k: String, _ d: String) -> String { let v = (names[k] ?? "").trimmingCharacters(in: .whitespaces); return v.isEmpty ? d : v }
        return ClipInfo(sheikh: n("sh", r), surah: n("sur", s), brand: n("brand", b))
    }

    var body: some View {
        Group {
            if let t, let src { body(t, src) } else { Empty(text: tr("هذه التلاوة غير متاحة."), icon: "scissors") }
        }
        .navigationTitle(tr("اصنع مقطعًا")).navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, L.dir)
        .task(id: fontKey) { await loadCustomFonts() }
    }

    /// the fonts in use (custom ones are downloaded when it changes)
    private var fontKey: String {
        let pieces: [String] = o.L.values.map { $0.font }.sorted()
        return ([o.font, o.ifont] + pieces).joined(separator: "|")
    }
    /// a change shows at once; it is kept a moment later (saving on every step of a slider made it stutter)
    private func set(_ f: (inout ClipOpts) -> Void) {
        var n = o; f(&n); o = n
        saveTask?.cancel(); saveTask = Task { try? await Task.sleep(nanoseconds: 400_000_000); if !Task.isCancelled { n.save() } }
    }

    @ViewBuilder private func preview(_ FR: CGSize, _ oNow: ClipOpts, _ w: Double, _ h: Double, _ segsNow: [ClipSeg], _ infoNow: ClipInfo, _ a: Double, _ b: Double, _ selNow: String) -> some View {
                ClipPreview(player: player) { (oNow, w, h, segsNow, infoNow, a, b, selNow) }
                    .aspectRatio(FR.width / FR.height, contentMode: .fit)
                    .frame(maxHeight: 460).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(c.line))
                    .overlay { if loading { ProgressView().tint(c.gold) } }
                    // like a design app (as on the site and Android): touch a piece — the ayahs, the names, each detail, or the
                    // video — and drag it anywhere (it snaps to the centre); pinch with two fingers to make it bigger or smaller.
                    // A tap plays / pauses.
                    .overlay { GeometryReader { gp in Color.clear.contentShape(Rectangle())
                        .onTapGesture { togglePlay() }
                        .gesture(dragGesture(gp.size, FR))
                        .modifier(Pinch(begin: { p in pinchBegin(p, gp.size, FR) }, change: { m in pinchChange(m) }, end: { pinchKey = nil; pinchFrom = nil }))
                    } }
    }

    @ViewBuilder private func body(_ t: Track, _ src: URL) -> some View {
        let FR = ClipEngine.frame(o, vw, vh)
        let segsNow = segs, infoNow = info, oNow = o, a = t0, b = t1, w = vw, h = vh, selNow = sel
        ScrollView {
            VStack(spacing: 14) {
                preview(FR, oNow, w, h, segsNow, infoNow, a, b, selNow)
                if !sel.isEmpty {
                    HStack(spacing: 8) {
                        Text(tr("المحدَّد: {0}", selName)).font(F.plex(12.5)).foregroundStyle(c.muted)
                        Spacer()
                        Button(tr("إرجاعه لمكانه")) { resetSel() }.font(F.plex(12.5, .semibold)).foregroundStyle(c.gold)
                    }
                }
                HStack(spacing: 10) {
                    Button { togglePlay() } label: { Ico(name: playing ? "pause.fill" : "play.fill", size: 20).foregroundStyle(c.onGold).frame(width: 44, height: 44).background(Circle().fill(c.gold)) }
                        .accessibilityLabel(playing ? tr("إيقاف مؤقت") : tr("تشغيل"))
                    Text(tr("{0} – {1} · {2} ث", fmt(t0), fmt(t1), Int(t1 - t0).ar)).font(F.plex(13).monospacedDigit()).foregroundStyle(c.muted)
                    Spacer()
                    if let p = exporting {
                        HStack(spacing: 8) { ProgressView(value: p).tint(c.gold).frame(width: 90); Text(tr("{0}٪", Int(p * 100).ar)).font(F.plex(13)).foregroundStyle(c.text)
                            Button { exporter?.cancel() } label: { Ico(name: "xmark.circle.fill", size: 20).foregroundStyle(c.muted) }.accessibilityLabel(tr("إلغاء")) }
                    } else { GoldButton(title: tr("حفظ المقطع"), icon: "square.and.arrow.down") { export(src) } }
                }
                if let done {
                    HStack(spacing: 8) {
                        GoldButton(title: tr("مشاركة"), icon: "square.and.arrow.up") { shareFile(done) }
                        GhostButton(title: tr("حفظ في الصور"), icon: "photo") { saveToPhotos(done) }
                    }
                }
                Picker("", selection: $tab) { Text(tr("المقطع")).tag("part"); Text(tr("الآيات")).tag("ayah"); Text(tr("الشكل")).tag("look"); Text(tr("البيانات")).tag("info"); Text(tr("الحركة")).tag("motion") }.pickerStyle(.segmented)
                Group {
                    switch tab {
                    case "ayah": ayahTab()
                    case "look": lookTab()
                    case "info": infoTab()
                    case "motion": motionTab()
                    default: partTab()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(16).padding(.bottom, 80)
        }
        .task { await load(t, src) }
        .onChange(of: segsKey) { _ in segsC = makeSegs() }
        .onDisappear { player.pause(); exporter?.cancel(); o.save() }
    }

    private func fmt(_ s: Double) -> String { let x = Int(max(0, s)); return String(format: "%d:%02d", x / 60, x % 60) }

    // MARK: moving the pieces by hand
    private func dragGesture(_ sz: CGSize, _ FR: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3).onChanged { d in dragChange(d, sz, FR) }.onEnded { _ in dragKey = nil; dragFrom = nil }
    }
    private func dragChange(_ d: DragGesture.Value, _ sz: CGSize, _ FR: CGSize) {
        let gw: Double = max(1, sz.width), gh: Double = max(1, sz.height)
        if dragKey == nil {
            let k = hit(CGPoint(x: d.startLocation.x / gw, y: d.startLocation.y / gh), FR)
            dragKey = k; dragFrom = place(k, FR); pick(k)
        }
        guard let k = dragKey, let from = dragFrom else { return }
        move(k, from, d.translation.width / gw, d.translation.height / gh)
    }
    private func pinchBegin(_ p: CGPoint?, _ sz: CGSize, _ FR: CGSize) {
        var k: String
        if let dk = dragKey { k = dk }
        else if let p { k = hit(CGPoint(x: p.x / max(1, sz.width), y: p.y / max(1, sz.height)), FR) }
        else { k = sel.isEmpty ? (o.show ? "ayah" : "video") : sel }
        pinchKey = k; pinchFrom = size(k); pick(k)
    }
    private func pinchChange(_ m: Double) { if let k = pinchKey, let base = pinchFrom { scale(k, base, m) } }
    private func pick(_ k: String) { sel = k; if k.hasPrefix("i_") { ied = String(k.dropFirst(2)) } }
    private var selName: String { sel == "ayah" ? tr("الآيات") : sel == "info" ? tr("البيانات") : sel == "video" ? tr("الفيديو") : sel.hasPrefix("i_") ? ILayer.label(String(sel.dropFirst(2))) : "" }
    /// the piece under the finger: a detail, the names line, the ayahs, else the video
    private func hit(_ q: CGPoint, _ FR: CGSize) -> String {
        let B = ClipEngine.boxes.all
        func inB(_ k: String, _ m: Double) -> Bool { guard let b = B[k] else { return false }; return q.x >= b.minX - m && q.x <= b.maxX + m && q.y >= b.minY - m && q.y <= b.maxY + m }
        if o.isplit && o.name, let k = ILayer.keys.first(where: { inB("i_" + $0, 0.025) }) { return "i_" + k }
        if !o.isplit && o.name && inB("info", 0.04) { return "info" }
        if o.show && inB("ayah", 0.03) { return "ayah" }
        if inB("video", 0) { return "video" }
        return o.show ? "ayah" : "video"
    }
    /// where a piece is now (0…1; the video: its shift)
    private func place(_ k: String, _ FR: CGSize) -> CGPoint {
        switch k {
        case "ayah": return ClipEngine.ayahCenter(o, FR.width, FR.height, vw, vh)
        case "info": return CGPoint(x: o.ix >= 0 ? o.ix : 0.5, y: ClipEngine.infoY(o, FR.width, FR.height))
        case "video": return CGPoint(x: o.vx, y: o.vy)
        default:
            let lk = String(k.dropFirst(2)), L = o.lay(lk)
            let mid: Double = ClipEngine.boxes.all[k].map { Double($0.midY) } ?? ILayer.defY(lk)
            return CGPoint(x: L.x >= 0 ? L.x : 0.5, y: L.y >= 0 ? L.y : mid)
        }
    }
    private func move(_ k: String, _ from: CGPoint, _ dx: Double, _ dy: Double) {
        func snap(_ v: Double, _ c: Double, _ m: Double) -> Double { abs(v - c) < m ? c : v }
        let x = snap(min(0.96, max(0.04, from.x + dx)), 0.5, 0.02), y = snap(min(0.96, max(0.04, from.y + dy)), 0.5, 0.02)
        switch k {
        case "ayah": set { $0.tx = x == 0.5 ? -1 : x; $0.ty = y }
        case "info": set { $0.ix = x; $0.iy = y }
        case "video": set { $0.vx = snap(min(0.6, max(-0.6, from.x + dx)), 0, 0.012); $0.vy = snap(min(0.6, max(-0.6, from.y + dy)), 0, 0.012) }
        default: let lk = String(k.dropFirst(2)); set { var L = $0.lay(lk); L.x = x; L.y = y; $0.L[lk] = L }
        }
    }
    private func size(_ k: String) -> Int {
        switch k { case "ayah": return o.fs; case "info": return o.ifs; case "video": return o.vscale; default: return o.lay(String(k.dropFirst(2))).fs }
    }
    private func scale(_ k: String, _ base: Int, _ m: Double) {
        let v = Double(base) * m
        switch k {
        case "ayah": set { $0.fs = Int(min(160, max(24, v))) }
        case "info": set { $0.ifs = Int(min(260, max(50, v))) }
        case "video": set { $0.vscale = Int(min(300, max($0.layout == "fill" ? 100 : 40, v))) }
        default: let lk = String(k.dropFirst(2)); set { var L = $0.lay(lk); L.fs = Int(min(260, max(40, v))); $0.L[lk] = L }
        }
    }
    private func resetSel() {
        switch sel {
        case "ayah": set { $0.tx = -1; $0.ty = -1 }
        case "info": set { $0.ix = -1; $0.iy = -1; $0.ipos = "bot" }
        case "video": set { $0.vx = 0; $0.vy = 0; $0.vscale = 100 }
        case "": break
        default: let lk = String(sel.dropFirst(2)); set { var L = $0.lay(lk); L.x = -1; L.y = -1; L.fs = ILayer.defFs(lk); $0.L[lk] = L }
        }
    }
    private func togglePlay() {
        if playing { player.pause(); playing = false; return }
        AudioPlayer.shared.pause(); VideoEngine.shared.pause()
        let now = player.currentTime().seconds
        if !(now >= t0 && now < t1) { player.seek(to: CMTime(seconds: t0, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback); try? AVAudioSession.sharedInstance().setActive(true)
        player.play(); playing = true
    }
    private func load(_ t: Track, _ src: URL) async {
        names = (try? JSONDecoder().decode([String: [String: String]].self, from: Data(Store.shared.str("clipNames").utf8)))?[t.id] ?? [:]
        player.replaceCurrentItem(with: AVPlayerItem(url: src))
        if t.durationSec > 0 { dur = Double(t.durationSec) }
        let tm = await repo.trackTimes(t.id)
        let s = (1...114).contains(tm?.surah ?? 0) ? tm!.surah : ((1...114).contains(t.surahNumber) ? t.surahNumber : 0)
        surahNo = s
        if let tm, s > 0, let txt = await repo.surahText(s) {
            times = tm
            var m: [Int: String] = [:]; for a in tm.ayahs where a[0] >= 1 && a[0] <= txt.count { m[a[0]] = ayahClean(s, a[0], txt[a[0] - 1]) }
            texts = m
            var oth: [(AyahTimes.Part, [Int: String])] = []
            for p in tm.parts { if let tx = await repo.surahText(p.surah) {
                var mm: [Int: String] = [:]; for a in p.ayahs where a[0] >= 1 && a[0] <= tx.count { mm[a[0]] = ayahClean(p.surah, a[0], tx[a[0] - 1]) }
                oth.append((p, mm))
            } }
            others = oth
            // start at the first recited ayah and end at the last ayah that fits in 30 seconds
            let s0 = Double(tm.ayahs[0][1]) / 1000; var e = Double(tm.ayahs[0][2]) / 1000
            for a in tm.ayahs where Double(a[2]) / 1000 - s0 <= ClipEngine.first { e = Double(a[2]) / 1000 }
            // ends a little after the last ayah (its last word is never cut, and the sound falls after it)
            t0 = max(0, s0 - 0.25); t1 = e + 0.35 + max(0.6, o.afo)
            if t1 - t0 > ClipEngine.maxLen { t1 = t0 + ClipEngine.maxLen }
        } else { t1 = min(dur, ClipEngine.first) }
        if let d = try? await AVURLAsset(url: src).load(.duration).seconds, d.isFinite, d > 0 { dur = d }
        t1 = min(t1, dur)
        segsC = makeSegs()
        await player.seek(to: CMTime(seconds: t0, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        loading = false
    }
    private func saveNames() {
        guard let t else { return }
        var all = (try? JSONDecoder().decode([String: [String: String]].self, from: Data(Store.shared.str("clipNames").utf8))) ?? [:]
        all[t.id] = names
        if let d = try? JSONEncoder().encode(all), let s = String(data: d, encoding: .utf8) { Store.shared.set("clipNames", s) }
    }

    // the chosen part: where it starts and how long it is (up to two minutes)
    private func partTab() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("اختر حتى دقيقتين — تظهر الآيات تلقائيًا مع التلاوة")).font(F.plex(13)).foregroundStyle(c.muted)
            row(tr("البداية · {0}", fmt(t0))) { Slider(value: Binding(get: { t0 }, set: { v in let l = t1 - t0; t0 = v; t1 = min(dur, v + l); player.seek(to: CMTime(seconds: v, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }), in: 0...max(1, dur - 3)) }
            row(tr("المدة · {0} ثانية", Int(t1 - t0).ar)) { Slider(value: Binding(get: { t1 - t0 }, set: { t1 = min(dur, t0 + $0) }), in: 3...min(ClipEngine.maxLen, max(4, dur - t0))) }
            if let times {
                let inPart = times.ayahs.filter { Double($0[2]) / 1000 > t0 && Double($0[1]) / 1000 < t1 }
                if !inPart.isEmpty {
                    Text(tr("الآيات في المقطع")).font(F.plex(14, .bold)).foregroundStyle(c.text)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(times.ayahs.indices, id: \.self) { i in
                                let a = times.ayahs[i]
                                Pill(title: tr("الآية {0}", a[0].ar), on: inPart.contains { $0[0] == a[0] }) {
                                    t0 = max(0, Double(a[1]) / 1000 - 0.25); t1 = min(dur, max(t0 + 3, min(t0 + ClipEngine.maxLen, Double(a[2]) / 1000 + 0.35 + max(0.6, o.afo))))
                                    player.seek(to: CMTime(seconds: t0, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                                }
                            }
                        }
                    }
                }
            } else if !loading { Text(tr("لم تُحلَّل هذه التلاوة بعد، فلن تظهر الآيات تلقائيًا.")).font(F.plex(13)).foregroundStyle(c.muted) }
            Text(tr("المقاس")).font(F.plex(14, .bold)).foregroundStyle(c.text)
            HStack(spacing: 6) {
                Pill(title: tr("ملاءمة الفيديو"), on: o.size == "auto") { set { $0.size = "auto" } }
                ForEach(ClipEngine.sizes, id: \.key) { s in Pill(title: s.name, on: o.size == s.key) { set { $0.size = s.key } } }
            }
        }
    }
    private func ayahTab() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(tr("إظهار الآيات على الفيديو"), isOn: Binding(get: { o.show }, set: { v in set { $0.show = v } })).tint(c.gold).font(F.plex(14))
            Toggle(tr("رقم الآية ﴿ ﴾"), isOn: Binding(get: { o.num }, set: { v in set { $0.num = v } })).tint(c.gold).font(F.plex(14))
            Text(tr("الخط")).font(F.plex(14, .bold)).foregroundStyle(c.text)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(ClipEngine.ayahFonts.map { ($0.0, tr($0.1)) } + customFonts("ayah"), id: \.0) { f in Pill(title: f.1, on: o.font == f.0) { set { $0.font = f.0 } } } } }
            Text(tr("اللون")).font(F.plex(14, .bold)).foregroundStyle(c.text)
            colors(o.color) { v in set { $0.color = v } }
            row(tr("الحجم")) { Slider(value: Binding(get: { Double(o.fs) }, set: { v in set { $0.fs = Int(v) } }), in: 36...110) }
            row(tr("كلمات في الجزء الواحد · {0}", o.per.ar)) { Stepper("", value: Binding(get: { o.per }, set: { v in set { $0.per = v } }), in: 2...12).labelsHidden() }
            if let times {
                Text(tr("طريقة عرض كل آية")).font(F.plex(14, .bold)).foregroundStyle(c.text)
                let inPart = times.ayahs.filter { Double($0[2]) / 1000 > t0 && Double($0[1]) / 1000 < t1 }
                ForEach(inPart.indices, id: \.self) { i in
                    let n = inPart[i][0]
                    HStack { Text(tr("الآية {0}", n.ar)).font(F.plex(13)).foregroundStyle(c.text); Spacer()
                        Pill(title: tr("كاملة"), on: (modes[n] ?? "whole") == "whole") { modes[n] = "whole" }
                        Pill(title: tr("على أجزاء"), on: modes[n] == "split") { modes[n] = "split" } }
                }
            }
            row(tr("موضع النص")) { Slider(value: Binding(get: { o.ty < 0 ? 0.8 : o.ty }, set: { v in set { $0.ty = v } }), in: 0.1...0.92) }
            Text(tr("اسحب الآيات بإصبعك على المعاينة لتحريكها، وقرّب أو باعد بإصبعين لتكبيرها")).font(F.plex(12)).foregroundStyle(c.muted)
            Button(tr("الموضع التلقائي")) { set { $0.ty = -1; $0.tx = -1 } }.font(F.plex(13)).foregroundStyle(c.gold)
        }
    }
    private func lookTab() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) { Pill(title: tr("الفيديو في المنتصف"), on: o.layout != "fill") { set { $0.layout = "center" } }; Pill(title: tr("ملء الإطار"), on: o.layout == "fill") { set { $0.layout = "fill" } } }
            if o.layout != "fill" {
                row(tr("تمويه الخلفية")) { Slider(value: Binding(get: { Double(o.blur) }, set: { v in set { $0.blur = Int(v) } }), in: 0...100) }
            }
            row(tr("حجم الفيديو · {0}٪", o.vscale.ar)) { Slider(value: Binding(get: { Double(o.vscale) }, set: { v in set { $0.vscale = Int(v) } }), in: (o.layout == "fill" ? 100 : 40)...300) }
            HStack {
                Text(tr("اسحب الفيديو بإصبعك على المعاينة لتحريكه لأعلى وأسفل، وكبّره أو صغّره بإصبعين")).font(F.plex(12)).foregroundStyle(c.muted)
                Spacer(minLength: 6)
                if o.vx != 0 || o.vy != 0 || o.vscale != 100 { Button(tr("إرجاع الفيديو")) { set { $0.vx = 0; $0.vy = 0; $0.vscale = 100 } }.font(F.plex(12.5, .semibold)).foregroundStyle(c.gold) }
            }
            row(tr("تعتيم")) { Slider(value: Binding(get: { Double(o.dark) }, set: { v in set { $0.dark = Int(v) } }), in: 0...80) }
            Toggle(tr("شريط خلف الآية"), isOn: Binding(get: { o.band }, set: { v in set { $0.band = v } })).tint(c.gold).font(F.plex(14))
            Toggle(tr("إطار حول الحروف"), isOn: Binding(get: { o.stroke }, set: { v in set { $0.stroke = v } })).tint(c.gold).font(F.plex(14))
            row(tr("التوهج")) { Slider(value: Binding(get: { Double(o.glow) }, set: { v in set { $0.glow = Int(v) } }), in: 0...100) }
            row(tr("تباعد الأسطر")) { Slider(value: Binding(get: { Double(o.lh) }, set: { v in set { $0.lh = Int(v) } }), in: 130...240) }
            row(tr("عرض النص")) { Slider(value: Binding(get: { Double(o.wmax) }, set: { v in set { $0.wmax = Int(v) } }), in: 50...96) }
        }
    }
    /// «كل واحدة في مكانها»: the piece chosen, its size, font and colour
    @ViewBuilder private func layerEditor() -> some View {
        VStack(alignment: .leading, spacing: 12) {
                    Text(tr("اسحب كل واحدة بإصبعك على المعاينة إلى المكان الذي تريده، وكبّرها أو صغّرها بإصبعين")).font(F.plex(12)).foregroundStyle(c.muted)
                    HStack(spacing: 6) { ForEach(ILayer.keys, id: \.self) { k in Pill(title: ILayer.label(k), on: ied == k) { ied = k; sel = "i_" + k } } }
                    let L = o.lay(ied)
                    row(tr("حجم {0} · {1}٪", ILayer.label(ied), L.fs.ar)) { Slider(value: Binding(get: { Double(L.fs) }, set: { v in let k = ied; set { var x = $0.lay(k); x.fs = Int(v); $0.L[k] = x } }), in: 40...260) }
                    Text(tr("خط {0}", ILayer.label(ied))).font(F.plex(14, .bold)).foregroundStyle(c.text)
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) {
                        Pill(title: tr("مثل الباقي"), on: L.font.isEmpty) { let k = ied; set { var x = $0.lay(k); x.font = ""; $0.L[k] = x } }
                        ForEach(ClipEngine.infoFonts.map { ($0.0, tr($0.1)) } + customFonts("info"), id: \.0) { f in Pill(title: f.1, on: L.font == f.0) { let k = ied; set { var x = $0.lay(k); x.font = f.0; $0.L[k] = x } } }
                    } }
                    colors(L.color.isEmpty ? o.icolor : L.color) { v in let k = ied; set { var x = $0.lay(k); x.color = v; $0.L[k] = x } }
                    Button(tr("إرجاع {0} لمكانه", ILayer.label(ied))) { let k = ied; set { var x = $0.lay(k); x.x = -1; x.y = -1; x.fs = ILayer.defFs(k); $0.L[k] = x } }.font(F.plex(13)).foregroundStyle(c.gold)
                    Text(tr("الخط واللون والحجم المشترك للجميع")).font(F.plex(14, .bold)).foregroundStyle(c.text).padding(.top, 6)
        }
    }
    @ViewBuilder private func infoPlace() -> some View {
        VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) { Pill(title: tr("أسفل"), on: o.ipos != "top" && o.iy < 0) { set { $0.ipos = "bot"; $0.iy = -1; $0.ix = -1 } }; Pill(title: tr("أعلى"), on: o.ipos == "top" && o.iy < 0) { set { $0.ipos = "top"; $0.iy = -1; $0.ix = -1 } } }
                    Text(tr("أو اسحب البيانات بإصبعك على المعاينة إلى أي مكان")).font(F.plex(12)).foregroundStyle(c.muted)
        }
    }
    private func infoTab() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(tr("إظهار البيانات"), isOn: Binding(get: { o.name }, set: { v in set { $0.name = v } })).tint(c.gold).font(F.plex(14))
            if o.name {
                nameField("sh", tr("اسم الشيخ"), on: o.sh) { v in set { $0.sh = v } }
                nameField("sur", tr("السورة"), on: o.sur) { v in set { $0.sur = v } }
                nameField("brand", tr("اسم الموقع"), on: o.brand) { v in set { $0.brand = v } }
                // together in one line, or each one in its own place (as on the site and Android)
                Text(tr("طريقة العرض")).font(F.plex(14, .bold)).foregroundStyle(c.text)
                HStack(spacing: 6) {
                    Pill(title: tr("معًا في سطر واحد"), on: !o.isplit) { set { $0.isplit = false }; if sel.hasPrefix("i_") { sel = "" } }
                    Pill(title: tr("كل واحدة في مكانها"), on: o.isplit) { set { $0.isplit = true }; if sel == "info" { sel = "" } }
                }
                if o.isplit { layerEditor() } else { infoPlace() }
                Text(tr("الخط")).font(F.plex(14, .bold)).foregroundStyle(c.text)
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(ClipEngine.infoFonts.map { ($0.0, tr($0.1)) } + customFonts("info"), id: \.0) { f in Pill(title: f.1, on: o.ifont == f.0) { set { $0.ifont = f.0 } } } } }
                colors(o.icolor) { v in set { $0.icolor = v } }
                row(tr("الحجم")) { Slider(value: Binding(get: { Double(o.ifs) }, set: { v in set { $0.ifs = Int(v) } }), in: 60...180) }
            }
        }
    }
    private func motionTab() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("ظهور الآيات")).font(F.plex(14, .bold)).foregroundStyle(c.text)
            HStack(spacing: 6) { ForEach([("fade", tr("تلاشٍ")), ("words", tr("كلمة بكلمة")), ("slide", tr("انزلاق")), ("zoom", tr("تكبير"))], id: \.0) { a in Pill(title: a.1, on: o.anim == a.0) { set { $0.anim = a.0 } } } }
            row(tr("نعومة تبدّل الآيات · {0} ث", String(format: "%.1f", o.tfade))) { Slider(value: Binding(get: { o.tfade }, set: { v in set { $0.tfade = v } }), in: 0.15...1.2) }
            row(tr("ظهور الصورة من السواد · {0} ث", String(format: "%.1f", o.vfi))) { Slider(value: Binding(get: { o.vfi }, set: { v in set { $0.vfi = v } }), in: 0...3) }
            row(tr("اختفاء الصورة إلى السواد · {0} ث", String(format: "%.1f", o.vfo))) { Slider(value: Binding(get: { o.vfo }, set: { v in set { $0.vfo = v } }), in: 0...3) }
            row(tr("ارتفاع الصوت في البداية · {0} ث", String(format: "%.1f", o.afi))) { Slider(value: Binding(get: { o.afi }, set: { v in set { $0.afi = v } }), in: 0...4) }
            row(tr("انخفاض الصوت في النهاية · {0} ث", String(format: "%.1f", o.afo))) { Slider(value: Binding(get: { o.afo }, set: { v in set { $0.afo = v } }), in: 0...4) }
        }
    }
    private func nameField(_ k: String, _ label: String, on: Bool, _ toggle: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { on }, set: toggle)).labelsHidden().tint(c.gold)
            TextField(label, text: Binding(get: { names[k] ?? "" }, set: { names[k] = $0; saveNames() }), prompt: Text(k == "sh" ? info.sheikh : k == "sur" ? info.surah : info.brand))
                .font(F.plex(14)).padding(10).background(RoundedRectangle(cornerRadius: 12).fill(c.surface.opacity(0.7))).overlay(RoundedRectangle(cornerRadius: 12).stroke(c.line))
        }
    }
    private func colors(_ cur: String, _ pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 10) { ForEach(ClipEngine.colors, id: \.self) { h in Circle().fill(Color(ClipEngine.color(h))).frame(width: 30, height: 30).overlay(Circle().stroke(cur == h ? c.gold : c.line, lineWidth: cur == h ? 3 : 1)).onTapGesture { pick(h) } } }
    }
    private func row<V: View>(_ label: String, @ViewBuilder _ v: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(label).font(F.plex(13)).foregroundStyle(c.muted); v().tint(c.gold) }
    }

    private func export(_ src: URL) {
        player.pause(); playing = false; done = nil
        let ex = ClipExporter(); exporter = ex; exporting = 0
        let oo = o, a = t0, b = t1, s = segs, inf = info, w = vw, h = vh
        Task {
            do {
                let url = try await ex.run(src: src, o: oo, vw: w, vh: h, t0: a, t1: b, segs: s, info: inf) { p in DispatchQueue.main.async { exporting = p } }
                exporting = nil; exporter = nil; done = url
                ui.say(tr("المقطع جاهز"))
                Repo.shared.event("clip", ["id": trackId])
            } catch {
                exporting = nil; exporter = nil
                if !(error is CancellationError) { ui.say(tr("تعذّر حفظ المقطع. حاول مرة أخرى.")) }
            }
        }
    }
    private func shareFile(_ u: URL) {
        let av = UIActivityViewController(activityItems: [u], applicationActivities: nil)
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController?.topMost.present(av, animated: true)
    }
    private func saveToPhotos(_ u: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { st in
            guard st == .authorized || st == .limited else { DispatchQueue.main.async { ui.say(tr("اسمح للتطبيق بحفظ الصور من الإعدادات")) }; return }
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: u) }) { ok, _ in DispatchQueue.main.async { ui.say(ok ? tr("حُفظ المقطع في الصور") : tr("تعذّر الحفظ في الصور")) } }
        }
    }
}


/// Two fingers resize the touched piece: on iOS 17 the pinch knows where it started (so it picks the piece under the fingers),
/// on iOS 16 it resizes the piece chosen last.
private struct Pinch: ViewModifier {
    let begin: (CGPoint?) -> Void, change: (Double) -> Void, end: () -> Void
    @State private var on = false
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.simultaneousGesture(MagnifyGesture().onChanged { v in if !on { on = true; begin(v.startLocation) }; change(Double(v.magnification)) }.onEnded { _ in on = false; end() })
        } else {
            content.simultaneousGesture(MagnificationGesture().onChanged { m in if !on { on = true; begin(nil) }; change(Double(m)) }.onEnded { _ in on = false; end() })
        }
    }
}
