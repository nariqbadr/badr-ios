import UIKit
import AVFoundation

/// Everything the person picks in the maker.
struct MakerOpts: Equatable {
    var surah = 67, from = 1, to = 2, tpl = "emerald", size = "story", anim = "fade", reciter = "yasser"
    var particles = true, zoom = true, rays = false, bokeh = false, rain = false, vignette = false, bar = true, meta = true, rname = true, mark = true
    var amb = "", ambVol = 35, fontScale = 100, font = "amiri", tafsir = ""
    /// the reciter's name: own wording (empty = «بصوت الشيخ …»), font and size (%)
    var rtext = "", rfont = "plex", rsize = 100
    /// the site's name under the design: own wording (empty = the dashboard's text), font and size (%)
    var mtext = "", mfont = "plex", msize = 100
    var videos: [String] = [], vidMode = "time", every = 8, transLen: CGFloat = 1.4, trans = "fade"
    /// the start and the end (seconds, 0 = none): the picture from / to black, the sound in / out
    var vfi: CGFloat = 0.6, vfo: CGFloat = 0.8, afi: CGFloat = 1, afo: CGFloat = 1.5
}
let MAKER_SIZES: [String: (Int, Int)] = ["story": (1080, 1920), "square": (1080, 1080), "post": (1080, 1350), "wide": (1920, 1080)]
let MAKER_MAX_AYAHS = 20
/// The site's maker reciters (everyayah folders).
let MAKER_FOLDERS: [(String, [String])] = [
    ("yasser", ["Yasser_Ad-Dussary_128kbps"]), ("maher", ["MaherAlMuaiqly128kbps", "Maher_AlMuaiqly_64kbps"]), ("ali", ["Ali_Jaber_64kbps"]),
    ("qatami", ["Nasser_Alqatami_128kbps"]), ("shuraym", ["Saood_ash-Shuraym_128kbps"]), ("sudais", ["Abdurrahmaan_As-Sudais_192kbps"]),
    ("alafasy", ["Alafasy_128kbps", "Alafasy_64kbps"]), ("ayyoub", ["Muhammad_Ayyoub_128kbps", "Muhammad_Ayyoub_64kbps"]),
    ("minshawi", ["Minshawy_Murattal_128kbps"]), ("husary", ["Husary_128kbps", "Husary_64kbps"]), ("basit", ["Abdul_Basit_Murattal_192kbps"])]
let MAKER_NAMES: [String: String] = ["yasser": "الشيخ ياسر الدوسري", "maher": "الشيخ ماهر المعيقلي", "ali": "الشيخ علي جابر", "qatami": "الشيخ ناصر القطامي",
    "shuraym": "الشيخ سعود الشريم", "sudais": "الشيخ عبدالرحمن السديس", "alafasy": "الشيخ مشاري العفاسي", "ayyoub": "الشيخ محمد أيوب",
    "minshawi": "الشيخ محمد صديق المنشاوي", "husary": "الشيخ محمود خليل الحصري", "basit": "الشيخ عبدالباسط عبدالصمد"]

struct MAyah { let n: Int; let text: String }
final class MSeg { let a: MAyah; let start: CGFloat; let dur: CGFloat; var words: [CGFloat]?
    init(_ a: MAyah, _ start: CGFloat, _ dur: CGFloat) { self.a = a; self.start = start; self.dur = dur } }
final class MTimeline { let segs: [MSeg]; let total: CGFloat; var pcm: [Float]?; let rate: Int
    init(_ segs: [MSeg], _ total: CGFloat, _ pcm: [Float]?, _ rate: Int) { self.segs = segs; self.total = total; self.pcm = pcm; self.rate = rate } }
struct MLayer { let items: [MAyah]; let seg: MSeg?; let p: CGFloat; let alpha: CGFloat; let enter: CGFloat; let drift: CGFloat }
struct MFrame { let layers: [MLayer]; let t: CGFloat; let segIndex: Int; let segStart: CGFloat; let total: CGFloat; var isStatic = false }
struct MakerError: LocalizedError { let msg: String; var errorDescription: String? { msg } }

private let LETTER = try! NSRegularExpression(pattern: "[\\u0621-\\u063A\\u0641-\\u064A\\u0671]")
private func letters(_ s: String) -> Int { LETTER.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s)) }
private func words(_ s: String) -> [String] { s.split(whereSeparator: { $0.isWhitespace }).map(String.init) }

/// Everything the drawing needs that does not change from frame to frame.
final class MakerContext: @unchecked Sendable {
    var quranFontName = "AmiriQuran-Regular"
    var watermark = ""
    var reciterLabel = ""
    var tafsir: [Int: String] = [:]
    var videoFrames = MakerVideoFrames()
    func quranFont(_ s: CGFloat) -> UIFont { UIFont(name: quranFontName, size: s) ?? ClipEngine.font("amiri", s) }
    func nameFont(_ k: String, _ s: CGFloat) -> UIFont {
        switch k { case "amiri": return ClipEngine.font("amiriB", s); case "ruqaa", "kufi", "tajawal", "lateef": return ClipEngine.font(k, s); default: return ClipEngine.font("bold", s) }
    }
    private struct Lay { let fs: CGFloat; let lines: [[String]]; let lh: CGFloat; let boxW: CGFloat }
    private var layCache: [String: Lay] = [:]
    private let lock = NSLock()
    func clearLayout() { lock.lock(); layCache.removeAll(); lock.unlock() }

    private func width(_ s: String, _ f: UIFont) -> CGFloat { NSAttributedString(string: s, attributes: [.font: f]).size().width }
    private func wrap(_ f: UIFont, _ text: String, _ maxW: CGFloat) -> [[String]] {
        var lines: [[String]] = [], cur: [String] = []
        for w in words(text) { let test = (cur + [w]).joined(separator: " "); if !cur.isEmpty && width(test, f) > maxW { lines.append(cur); cur = [w] } else { cur.append(w) } }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }
    private func layout(_ text: String, _ W: CGFloat, _ H: CGFloat, _ u: CGFloat, _ o: MakerOpts) -> Lay {
        let withT = !o.tafsir.isEmpty, scenic = MAKER_SCENIC.contains(o.tpl)
        let key = "\(text)|\(W)|\(H)|\(o.fontScale)|\(o.font)|\(withT)|\(scenic)"
        lock.lock(); if let l = layCache[key] { lock.unlock(); return l }; lock.unlock()
        let boxW = W * (W > H ? 0.72 : 0.78), maxH = H * (H > W ? 0.52 : 0.5) * (withT ? 0.66 : 1) * (scenic ? 0.82 : 1)
        let base: CGFloat = W > H ? 64 : H > W * 1.5 ? 80 : 70
        var fs = (base * u * CGFloat(o.fontScale) / 100 * (text.count < 60 ? 1.25 : text.count > 260 ? 0.8 : 1)).rounded()
        var lines: [[String]] = [], lh: CGFloat = 0
        for _ in 0..<40 { lines = wrap(quranFont(fs), text, boxW); lh = fs * 2.05; if CGFloat(lines.count) * lh <= maxH || fs < 26 * u { break }; fs = (fs * 0.93).rounded() }
        let l = Lay(fs: fs, lines: lines, lh: lh, boxW: boxW)
        lock.lock(); if layCache.count > 200 { layCache.removeAll() }; layCache[key] = l; lock.unlock()
        return l
    }

    /// right-to-left text: its left edge at x, baseline at y
    private func rtl(_ s: String, _ x: CGFloat, _ y: CGFloat, _ a: [NSAttributedString.Key: Any]) {
        let f = a[.font] as! UIFont
        NSAttributedString(string: "\u{200F}" + s, attributes: a).draw(at: CGPoint(x: x, y: y - f.ascender))
    }
    /// centred at cx, y = the middle of the line
    private func rtlCenter(_ s: String, _ cx: CGFloat, _ y: CGFloat, _ a: [NSAttributedString.Key: Any]) {
        let f = a[.font] as! UIFont
        let w = NSAttributedString(string: "\u{200F}" + s, attributes: a).size().width
        rtl(s, cx - w / 2, y + (f.ascender + f.descender) / 2, a)
    }
    private func attrs(_ f: UIFont, _ col: UIColor, _ alpha: CGFloat, shadow: (CGFloat, CGFloat, UIColor)? = nil) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: col.withAlphaComponent(col.cgColor.alpha * max(0, min(1, alpha)))]
        if let (blur, dy, sc) = shadow { let s = NSShadow(); s.shadowBlurRadius = blur; s.shadowOffset = CGSize(width: 0, height: dy); s.shadowColor = sc.withAlphaComponent(sc.cgColor.alpha * max(0, min(1, alpha))); a[.shadow] = s }
        return a
    }

    private func drawText(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, _ f: MFrame, _ layer: MLayer, _ th: Th, _ o: MakerOpts, _ u: CGFloat) {
        let text = layer.items.map { "\($0.text) ﴿\($0.n.ar)﴾" }.joined(separator: " ")
        let L = layout(text, W, H, u, o)
        let tafsirText = o.tafsir.isEmpty ? "" : layer.items.compactMap { tafsir[$0.n] }.joined(separator: " • ")
        let scenic = MAKER_SCENIC.contains(o.tpl)
        let blockH = CGFloat(L.lines.count) * L.lh
        let cy = H * (scenic ? (H > W ? 0.42 : 0.4) : 0.5) + (o.meta ? 20 * u : 0) - (tafsirText.isEmpty ? 0 : H * 0.06)
        let y0 = cy - blockH / 2 + L.lh / 2
        let alpha = f.isStatic ? 1 : layer.alpha
        let qf = quranFont(L.fs)
        if o.tpl == "night" {
            let ef = quranFont(L.fs * 2.3)
            let ea = attrs(ef, hex("#9fd8d2"), 0.18 * alpha, shadow: (14 * u, 0, hex("#9fd8d2")))
            for (i, l) in wrap(ef, text, W * 1.4).prefix(4).enumerated() { rtlCenter(l.joined(separator: " "), W / 2, H * 0.18 + CGFloat(i) * L.fs * 3.4 + (H > W ? 0 : -H * 0.1), ea) }
            let pad = 54 * u, r = CGRect(x: (W - L.boxW) / 2 - pad, y: cy - blockH / 2 - pad, width: L.boxW + 2 * pad, height: blockH + 2 * pad)
            fillPath(c, rr(r, 40 * u), rgba(14, 38, 50, 0.72 * Double(alpha)))
            strokePath(c, rr(r, 40 * u), rgba(111, 208, 199, 0.28 * Double(alpha)), 2 * u)
        }
        let enter = f.isStatic ? 1 : layer.enter
        let anim = f.isStatic ? "none" : o.anim
        let dy: CGFloat = f.isStatic ? 0 : anim == "drop" ? -(1 - enter) * 44 * u : layer.drift * (anim == "rise" ? 46 : 22) * u
        let seg = layer.seg, local = seg != nil ? f.t - seg!.start : 9
        let reveal = f.isStatic ? 1 : min(1, max(0, local / min(2.4, max(0.9, (seg?.dur ?? 3) * 0.45))))
        func lineP(_ li: Int) -> CGFloat { let k = min(1, max(0, reveal * CGFloat(L.lines.count) * 1.15 - CGFloat(li))); return k * k * (3 - 2 * k) }
        let total = L.lines.reduce(0) { $0 + $1.count }
        var shown = total, hl = -1
        if anim == "words" {
            if let wt = layer.seg?.words, !wt.isEmpty { var k = 0; while k < wt.count && wt[k] <= f.t { k += 1 }; shown = k >= wt.count ? total : max(0, k); hl = min(k, wt.count) - 1 }
            else { shown = Int(ceil(min(1, layer.p) * CGFloat(total))); hl = shown - 1 }
            let flat = L.lines.flatMap { $0 }; while hl > 0 && letters(hl < flat.count ? flat[hl] : "") == 0 { hl -= 1 }
        }
        c.saveGState()
        if anim == "scale" && enter < 1 { let z = 0.9 + 0.1 * enter; c.translateBy(x: W / 2, y: cy); c.scaleBy(x: z, y: z); c.translateBy(x: -W / 2, y: -cy) }
        if anim == "pop" && enter < 1 { let z = 1.12 - 0.12 * enter; c.translateBy(x: W / 2, y: cy); c.scaleBy(x: z, y: z); c.translateBy(x: -W / 2, y: -cy) }
        var shadow: (CGFloat, CGFloat, UIColor)? = th.shadow.map { (14 * u, 3 * u, $0) }
        if anim == "glow" { shadow = ((16 + 14 * pow(sin(f.t * 2.2), 2)) * u, 0, th.accent) }
        if anim == "blur" && enter < 1 { shadow = (max(0.5, (1 - enter) * 14 * u), 0, th.text) }
        let blurA: CGFloat = anim == "blur" && enter < 1 ? 0.35 + 0.65 * enter : 1
        var wi = 0
        for (li, l) in L.lines.enumerated() {
            let y = y0 + CGFloat(li) * L.lh + dy
            switch anim {
            case "words":
                let full = l.joined(separator: " "), fw = width(full, qf), sp = width(" ", qf); var x = W / 2 + fw / 2
                for w in l {
                    let ww = width(w, qf), vis = wi < shown, isLast = wi == hl && letters(w) > 0
                    let a = attrs(qf, isLast ? th.accent : th.text, alpha * (vis ? 1 : 0.16), shadow: shadow)
                    let ff = qf
                    NSAttributedString(string: "\u{200F}" + w, attributes: a).draw(at: CGPoint(x: x - ww, y: y + (ff.ascender + ff.descender) / 2 - ff.ascender))
                    x -= ww + sp; wi += 1
                }
            case "shine":
                let full = l.joined(separator: " "), wFull = width(full, qf)
                rtlCenter(full, W / 2, y, attrs(qf, th.text, alpha, shadow: shadow))
                // the gold glint passing over the line
                let sx = W / 2 + wFull / 2 - ((f.t * 0.35 + CGFloat(li) * 0.12).truncatingRemainder(dividingBy: 1.4)) * (wFull + 300 * u)
                c.saveGState(); c.clip(to: CGRect(x: sx - 140 * u, y: y - L.lh / 2, width: 280 * u, height: L.lh))
                rtlCenter(full, W / 2, y, attrs(qf, hex("#fff6d8"), alpha * 0.85))
                c.restoreGState()
            case "lines":
                let k = lineP(li)
                rtlCenter(l.joined(separator: " "), W / 2, y + (1 - k) * 24 * u, attrs(qf, th.text, alpha * k, shadow: shadow.map { ($0.0, $0.1, $0.2.withAlphaComponent($0.2.cgColor.alpha * k)) }))
            case "wipe":
                let k = lineP(li)
                if k > 0 {
                    let full = l.joined(separator: " "), wFull = width(full, qf), xr = W / 2 + wFull / 2, edge = 70 * u, x0 = xr - (wFull + edge) * k
                    c.saveGState(); c.clip(to: CGRect(x: x0 + edge, y: y - L.lh, width: W, height: L.lh * 1.6)); rtlCenter(full, W / 2, y, attrs(qf, th.text, alpha, shadow: shadow)); c.restoreGState()
                    if k < 1 { for s2 in 0..<4 { c.saveGState(); c.clip(to: CGRect(x: x0 + edge * CGFloat(s2) / 4, y: y - L.lh, width: edge / 4 + 1, height: L.lh * 1.6)); rtlCenter(full, W / 2, y, attrs(qf, th.text, alpha * CGFloat(s2 + 1) / 5)); c.restoreGState() } }
                }
            default:
                rtlCenter(l.joined(separator: " "), W / 2, y, attrs(qf, th.text, alpha * blurA, shadow: shadow))
            }
        }
        if !tafsirText.isEmpty {
            let en = o.tafsir.hasPrefix("en."), tfs = ((W > H ? 26 : 30) * u * (en ? 0.95 : 1)).rounded()
            let tf = en ? UIFont(name: "Georgia-Italic", size: tfs) ?? .italicSystemFont(ofSize: tfs) : ClipEngine.font("plex", tfs)
            var tl = wrap(tf, tafsirText, L.boxW * 0.96); let maxL = H > W ? 6 : 4
            if tl.count > maxL { tl = Array(tl.prefix(maxL)); tl[maxL - 1].append("…") }
            let ty = y0 + CGFloat(L.lines.count) * L.lh + 26 * u + dy
            c.setStrokeColor(th.accent.withAlphaComponent(0.5 * alpha).cgColor); c.setLineWidth(1.5 * u); c.move(to: CGPoint(x: W / 2 - 50 * u, y: ty - 14 * u)); c.addLine(to: CGPoint(x: W / 2 + 50 * u, y: ty - 14 * u)); c.strokePath()
            for (i, l) in tl.enumerated() {
                let s = l.joined(separator: " "), a = attrs(tf, th.soft, alpha * 0.92), w = NSAttributedString(string: s, attributes: a).size().width
                let yy = ty + 22 * u + CGFloat(i) * tfs * 1.75
                (en ? NSAttributedString(string: s, attributes: a) : NSAttributedString(string: "\u{200F}" + s, attributes: a)).draw(at: CGPoint(x: W / 2 - w / 2, y: yy - tf.ascender / 2 - tf.ascender / 2))
            }
        }
        c.restoreGState()
    }

    private var particles: [[CGFloat]] = []
    private var partW: CGFloat = 0

    /// One frame of the design (W×H, top-left origin).
    func drawFrame(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, _ f: MFrame, _ o: MakerOpts) {
        let tpl = o.tpl, th = makerTheme(tpl), u = min(W, H) / 1080
        let t = f.isStatic ? 3 : f.t
        UIGraphicsPushContext(c); defer { UIGraphicsPopContext() }
        c.saveGState()
        if o.zoom && !f.isStatic { let z = 1 + 0.07 * f.total; c.translateBy(x: W / 2, y: H / 2); c.scaleBy(x: z, y: z); c.translateBy(x: -W / 2, y: -H / 2) }
        if tpl == "video" { videoBg(c, W, H, f, o, u) }
        else { MakerBackgrounds.get(tpl, Int(W), Int(H)).draw(in: CGRect(x: 0, y: 0, width: W, height: H)); if MAKER_ANIMATED.contains(tpl) { MakerAnimated.scene(c, W, H, tpl, t, u) } }
        c.restoreGState()
        MakerAnimated.effects(c, W, H, t, u, tpl, .init(rays: o.rays, bokeh: o.bokeh, rain: o.rain, vignette: o.vignette))
        if o.particles {
            if particles.isEmpty || partW != W { var R = Rnd(42); particles = (0..<70).map { _ in [R.next() * W, R.next() * H, (R.next() * 2.4 + 0.6) * min(W, H) / 1080, R.next() * 0.6 + 0.2, R.next() * 6.28] }; partW = W }
            for p in particles {
                let y = ((p[1] - f.t * 22 * p[3] * u).truncatingRemainder(dividingBy: H) + H).truncatingRemainder(dividingBy: H), x = p[0] + sin(f.t * 0.6 + p[4]) * 14 * u
                let a = 0.25 + 0.35 * pow(Double(sin(f.t * 1.4 + p[4])), 2)
                let col: UIColor
                switch tpl { case "parchment": col = rgba(138, 106, 46, a * 0.6); case "mist": col = rgba(90, 98, 110, a * 0.55); case "babyblue": col = rgba(255, 255, 255, a); case "night": col = rgba(180, 240, 235, a)
                case "nightblue": col = rgba(190, 225, 250, a); case "gray": col = rgba(225, 228, 234, a * 0.8); default: col = rgba(240, 210, 150, a) }
                c.setFillColor(col.cgColor); c.fillEllipse(in: CGRect(x: x - p[2], y: y - p[2], width: 2 * p[2], height: 2 * p[2]))
            }
        }
        for l in f.layers where l.alpha > 0.003 || f.isStatic { drawText(c, W, H, f, l, th, o, u) }
        // meta: surah & ayah, reciter, watermark
        let ga: CGFloat = f.isStatic ? 1 : min(1, f.t / 0.8)
        let top = H * (H > W ? 0.2 : 0.13)
        if o.meta, let items = f.layers.last?.items, let first = items.first, let last = items.last {
            rtlCenter("سورة \(Quran.surahs[o.surah - 1])", W / 2, top, attrs(ClipEngine.font("amiriB", 44 * u), th.accent, ga))
            let sf = ClipEngine.font("plex", 28 * u)
            if !f.isStatic { for L in f.layers { rtlCenter("الآية \(L.items.first!.n.ar)", W / 2, top + 54 * u, attrs(sf, th.soft, ga * L.alpha)) } }
            else { rtlCenter(first.n != last.n ? "الآيات \(first.n.ar)–\(last.n.ar)" : "الآية \(first.n.ar)", W / 2, top + 54 * u, attrs(sf, th.soft, 1)) }
            c.setStrokeColor(th.accent.withAlphaComponent(ga * 0.6).cgColor); c.setLineWidth(1.5 * u); c.move(to: CGPoint(x: W / 2 - 70 * u, y: top + 92 * u)); c.addLine(to: CGPoint(x: W / 2 + 70 * u, y: top + 92 * u)); c.strokePath()
        }
        let bottom: CGFloat = MAKER_SCENIC.contains(tpl) ? H - (H > W ? 560 : 470) * u : (tpl == "ramadan" || tpl == "eid") ? H - (H > W ? 190 : 120) * u - (tpl == "eid" ? 200 * u : 40 * u) : H - (H > W ? 190 : 120) * u
        if o.rname && !reciterLabel.isEmpty {
            let nf = nameFont(o.rfont, 30 * u * CGFloat(o.rsize) / 100 * (o.rfont == "lateef" ? 1.25 : 1))
            let txt = o.rtext.trimmingCharacters(in: .whitespaces).isEmpty ? (reciterLabel.range(of: "^(الشيخ|الإمام|القارئ)\\s", options: .regularExpression) != nil ? "بصوت \(reciterLabel)" : "بصوت الشيخ \(reciterLabel)") : o.rtext
            rtlCenter(txt, W / 2, bottom, attrs(nf, th.soft, ga))
        }
        let wm = o.mtext.trimmingCharacters(in: .whitespaces).isEmpty ? watermark : o.mtext
        if o.mark && !wm.isEmpty {
            let wf = o.mfont == "plex" ? ClipEngine.font("plex", 24 * u * CGFloat(o.msize) / 100) : nameFont(o.mfont, 24 * u * CGFloat(o.msize) / 100 * (o.mfont == "lateef" ? 1.25 : 1))
            rtlCenter(wm, W / 2, bottom + 52 * u * max(1, CGFloat(o.rsize) / 100 * 0.9), attrs(wf, th.soft, ga * 0.8))
        }
        if o.bar && !f.isStatic {
            let bw = W * 0.5, bx = (W - bw) / 2, by = H - (H > W ? 96 : 60) * u
            fillPath(c, rr(CGRect(x: bx, y: by, width: bw, height: 6 * u), 3 * u), MAKER_LIGHT.contains(tpl) ? rgba(30, 40, 55, 0.16) : rgba(255, 255, 255, 0.18))
            fillPath(c, rr(CGRect(x: bx + bw * (1 - f.total), y: by, width: bw * f.total, height: 6 * u), 3 * u), th.accent)
        }
    }

    /* ---------------- video backgrounds (playlist with transitions) */
    private func drawItem(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, _ item: String, _ t: CGFloat, _ u: CGFloat, _ alpha: CGFloat) {
        c.saveGState(); c.setAlpha(alpha); c.beginTransparencyLayer(auxiliaryInfo: nil)
        if item.hasPrefix("scene:") { let sc = String(item.dropFirst(6)); MakerBackgrounds.get(sc, Int(W), Int(H)).draw(in: CGRect(x: 0, y: 0, width: W, height: H)); MakerAnimated.scene(c, W, H, sc, t, u) }
        else if let b = videoFrames.frame(item, t, W, H) {
            let s = max(W / b.size.width, H / b.size.height), vw = b.size.width * s, vh = b.size.height * s
            b.draw(in: CGRect(x: (W - vw) / 2, y: (H - vh) / 2, width: vw, height: vh))
        } else { c.setFillColor(hex("#0b0f10").cgColor); c.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
        c.endTransparencyLayer(); c.restoreGState()
    }
    private func videoBg(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, _ f: MFrame, _ o: MakerOpts, _ u: CGFloat) {
        c.setFillColor(hex("#0b0f10").cgColor); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let items = o.videos, n = items.count, t = f.t
        if n == 0 { drawCenteredText("اختر خلفيات الفيديو", W / 2, H * 0.82, ClipEngine.font("bold", 34 * u), rgba(255, 255, 255, 0.08)) }
        else {
            let X = max(0.3, o.transLen); var idx = 0, prev = -1; var k: CGFloat = 1
            if f.isStatic || o.vidMode == "none" || n == 1 { idx = 0 }
            else if o.vidMode == "ayah" { let si = f.segIndex; idx = si % n; if si > 0 { prev = (si - 1) % n; k = min(1, (t - f.segStart + X / 2) / X) } }
            else { let N = CGFloat(max(2, o.every)); let slot = Int(floor(t / N)); idx = slot % n; if slot > 0 { prev = (slot - 1) % n; k = min(1, (t - CGFloat(slot) * N) / X) } }
            if prev >= 0 && prev != idx && k < 1 { transition(c, W, H, items[prev], items[idx], max(0, k), t, u, o.trans) } else { drawItem(c, W, H, items[idx], t, u, 1) }
        }
        fillLin(c, W, H, 0, 0, 0, H, [(0, rgba(0, 0, 0, 0.5)), (0.5, rgba(0, 0, 0, 0.32)), (1, rgba(0, 0, 0, 0.65))])
    }
    private func transition(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, _ from: String, _ to: String, _ k: CGFloat, _ t: CGFloat, _ u: CGFloat, _ type: String) {
        let e = k * k * (3 - 2 * k)
        switch type {
        case "black", "white":
            let col: UIColor = type == "black" ? .black : .white
            if k < 0.5 { drawItem(c, W, H, from, t, u, 1); c.setFillColor(col.withAlphaComponent(min(1, k * 2)).cgColor) } else { drawItem(c, W, H, to, t, u, 1); c.setFillColor(col.withAlphaComponent(min(1, (1 - k) * 2)).cgColor) }
            c.fill(CGRect(x: 0, y: 0, width: W, height: H))
        case "slide":
            c.saveGState(); c.translateBy(x: W * e, y: 0); drawItem(c, W, H, from, t, u, 1); c.restoreGState()
            c.saveGState(); c.translateBy(x: -W * (1 - e), y: 0); drawItem(c, W, H, to, t, u, 1); c.restoreGState()
        case "zoom":
            c.saveGState(); let z1 = 1 + 0.35 * e; c.translateBy(x: W / 2, y: H / 2); c.scaleBy(x: z1, y: z1); c.translateBy(x: -W / 2, y: -H / 2); drawItem(c, W, H, from, t, u, 1); c.restoreGState()
            c.saveGState(); let z2 = 1.25 - 0.25 * e; c.translateBy(x: W / 2, y: H / 2); c.scaleBy(x: z2, y: z2); c.translateBy(x: -W / 2, y: -H / 2); drawItem(c, W, H, to, t, u, e); c.restoreGState()
        case "circle":
            drawItem(c, W, H, from, t, u, 1); c.saveGState(); let r = hypot(W, H) / 2 * e; c.addEllipse(in: CGRect(x: W / 2 - r, y: H / 2 - r, width: 2 * r, height: 2 * r)); c.clip(); drawItem(c, W, H, to, t, u, 1); c.restoreGState()
        case "wipe":
            drawItem(c, W, H, from, t, u, 1); c.saveGState(); c.clip(to: CGRect(x: W * (1 - e), y: 0, width: W * e, height: H)); drawItem(c, W, H, to, t, u, 1); c.restoreGState()
            c.setFillColor(rgba(255, 236, 190, 0.5 * Double(sin(.pi * e))).cgColor); c.fill(CGRect(x: W * (1 - e) - 3 * u, y: 0, width: 6 * u, height: H))
        default: drawItem(c, W, H, from, t, u, 1); drawItem(c, W, H, to, t, u, e)
        }
    }
}

enum MakerEngine {
    static let rate = 44100
    private static func smooth(_ x: CGFloat) -> CGFloat { let k = min(1, max(0, x)); return k * k * (3 - 2 * k) }
    private static func fadeCurve(_ x: CGFloat) -> CGFloat { x <= 0 ? 0 : x >= 1 ? 1 : max(0, CGFloat((pow(10, 2 * Double(x - 1)) - 0.01) / 0.99)) }
    /// how dark the picture is at time t: from black at the start, to black at the end
    static func blackAt(_ total: CGFloat, _ t: CGFloat, _ o: MakerOpts) -> CGFloat {
        max(o.vfi > 0 ? 1 - smooth(t / o.vfi) : 0, o.vfo > 0 ? 1 - smooth((total - t) / o.vfo) : 0)
    }
    static func fadeBlack(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, _ total: CGFloat, _ t: CGFloat, _ o: MakerOpts) {
        let k = blackAt(total, t, o); if k <= 0.002 { return }
        c.setFillColor(UIColor(white: 0, alpha: min(1, k)).cgColor); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    }
    /// The sound's level, measured on the voice: it rises into the first words and falls after the last ones.
    static func applyAudioFades(_ tl: MTimeline, _ o: MakerOpts) {
        guard var pcm = tl.pcm, o.afi > 0 || o.afo > 0 else { return }
        let vs = tl.segs.first?.start ?? 0, ve = min(tl.total, tl.segs.map { $0.start + $0.dur }.max() ?? tl.total)
        for i in pcm.indices {
            let t = CGFloat(i) / CGFloat(tl.rate); var g: CGFloat = 1
            if o.afi > 0 { g = min(g, fadeCurve(t / (vs + o.afi))) }
            if o.afo > 0 { g = min(g, t >= ve + 0.15 ? 0 : fadeCurve((ve + 0.15 - t) / (o.afo + 0.15))) }
            if g < 1 { pcm[i] *= Float(max(0, g)) }
        }
        tl.pcm = pcm
    }
    /// Current ayah with a clean hand-over (old fades out before the new is heard).
    static func frameAt(_ tl: MTimeline, _ t: CGFloat) -> MFrame {
        let segs = tl.segs, OUT: CGFloat = 0.45, IN: CGFloat = 0.45, PRE: CGFloat = 0.05
        func ease(_ k: CGFloat) -> CGFloat { k * k * (3 - 2 * k) }
        var i = 0; for k in segs.indices where t >= segs[k].start - PRE { i = k }
        if i + 1 < segs.count && t >= segs[i + 1].start - PRE - OUT {
            let nx = segs[i + 1], k = min(1, max(0, (t - (nx.start - PRE - OUT)) / OUT)), cur = segs[i], e = ease(k)
            return MFrame(layers: [MLayer(items: [cur.a], seg: cur, p: 1, alpha: 1 - e, enter: 1, drift: -e)], t: t, segIndex: i, segStart: cur.start, total: min(1, t / tl.total))
        }
        let cur = segs[i], local = t - cur.start
        let kIn = i == 0 ? min(1, max(0, (t + 0.1) / 0.9)) : min(1, max(0, (local + PRE) / IN))
        let eIn = ease(kIn)
        let outK = i == segs.count - 1 ? ease(min(1, max(0, (tl.total - t) / 1.1))) : 1
        return MFrame(layers: [MLayer(items: [cur.a], seg: cur, p: min(1, max(0, local / cur.dur)), alpha: eIn * outK, enter: eIn, drift: 1 - eIn)], t: t, segIndex: i, segStart: cur.start, total: min(1, t / tl.total))
    }
    static func staticFrame(_ ayahs: [MAyah]) -> MFrame { MFrame(layers: [MLayer(items: ayahs, seg: nil, p: 1, alpha: 1, enter: 1, drift: 0)], t: 2, segIndex: 0, segStart: 0, total: 0, isStatic: true) }

    // MARK: audio
    private static var cacheDir: URL { let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("maker"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }
    static func download(_ url: URL, _ name: String) async throws -> URL {
        let f = cacheDir.appendingPathComponent(name)
        if let s = (try? FileManager.default.attributesOfItem(atPath: f.path))?[.size] as? Int, s > 1000 { return f }
        let (tmp, r) = try await URLSession.shared.download(from: url)
        guard let h = r as? HTTPURLResponse, h.statusCode == 200 else { throw MakerError(msg: "تعذّر تحميل الصوت") }
        if (h.value(forHTTPHeaderField: "Content-Type") ?? "").contains("json") { throw MakerError(msg: "هذه السورة لم تُجهَّز بعد بصوت هذا القارئ") }
        try? FileManager.default.removeItem(at: f); try FileManager.default.moveItem(at: tmp, to: f)
        return f
    }
    /// [from, to] seconds of an audio file as mono float PCM at 44.1 kHz.
    static func decode(_ f: URL, _ from: Double = 0, _ to: Double = .greatestFiniteMagnitude) throws -> [Float] {
        let file = try AVAudioFile(forReading: f)
        let sr = file.processingFormat.sampleRate
        let start = AVAudioFramePosition(max(0, from) * sr)
        let end = to == .greatestFiniteMagnitude ? file.length : min(file.length, AVAudioFramePosition(to * sr))
        guard end > start else { return [] }
        file.framePosition = start
        let n = AVAudioFrameCount(end - start)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: n) else { return [] }
        try file.read(into: inBuf, frameCount: n)
        let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(rate), channels: 1, interleaved: false)!
        guard let conv = AVAudioConverter(from: file.processingFormat, to: outFmt) else { return [] }
        let cap = AVAudioFrameCount(Double(inBuf.frameLength) * Double(rate) / sr) + 4096
        guard let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap) else { return [] }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, st in if fed { st.pointee = .endOfStream; return nil }; fed = true; st.pointee = .haveData; return inBuf }
        if let err { throw err }
        guard let ch = out.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
    }

    /// Builds the timeline: per-ayah start/duration and the mixed audio (recitation + optional nature sound).
    static func buildTimeline(_ o: MakerOpts, _ ayahs: [MAyah], status: @escaping @MainActor (String) -> Void) async throws -> MTimeline {
        let lead: CGFloat = 0.6, gap: CGFloat = 0.12, tail: CGFloat = 1.6, R = CGFloat(rate)
        let rv = o.reciter
        let first = ayahs.first!.n, last = ayahs.last!.n
        if rv.hasPrefix("tk:") || rv.hasPrefix("tkr:") {
            let rid = String(rv.split(separator: ":", maxSplits: 1)[1])
            let repo = await Repo.shared
            let readable = await repo.data?.readableTracks ?? [:]
            var tid: String?
            for (k, v) in readable where v.count >= 3 && v[0] == o.surah && first >= v[1] && last <= v[2] { if await repo.track(k)?.reciterId == rid { tid = k; break } }
            guard let tid else { throw MakerError(msg: "\(await repo.reciter(rid)?.name ?? "") غير متاح لهذه الآيات — اختر آيات من تلاواته") }
            await status("جارٍ تحميل التلاوة من الآية \(first.ar) إلى \(last.ar)…")
            guard let tm = await repo.trackTimes(tid) else { throw MakerError(msg: "تعذّر تحميل توقيت التلاوة") }
            guard let A = tm.ayahs.first(where: { $0[0] == first }), let B = tm.ayahs.first(where: { $0[0] == last }) else { throw MakerError(msg: "هذه التلاوة لا تحتوي على الآيات المختارة") }
            let audio = tm.url.isEmpty ? await repo.track(tid)?.audio ?? "" : tm.url
            guard let u = await Repo.media(audio) else { throw MakerError(msg: "تعذّر تحميل الصوت") }
            let file = try await download(u, "t-\(tid.replacingOccurrences(of: "/", with: "_")).audio")
            await status("جارٍ تجهيز الصوت…")
            let t0 = max(0, A[1] - 300), t1 = B[2] + 300
            let clip = try decode(file, Double(t0) / 1000, Double(t1) / 1000)
            let segs: [MSeg] = ayahs.enumerated().map { i, a in
                let at = tm.ayahs.first { $0[0] == a.n }!, st = CGFloat(at[1] - t0) / 1000
                let en = i + 1 < ayahs.count ? CGFloat(tm.ayahs.first { $0[0] == ayahs[i + 1].n }![1] - t0) / 1000 : min(CGFloat(clip.count) / R, CGFloat(at[2] - t0) / 1000)
                let sg = MSeg(a, lead + max(0, st), max(0.5, en - max(0, st)))
                if let ix = tm.ayahs.firstIndex(where: { $0[0] == a.n }), ix < tm.words.count, !tm.words[ix].isEmpty { sg.words = aiWords(a.text, tm.words[ix]) { lead + CGFloat($0 - t0) / 1000 } }
                return sg
            }
            var pcm = [Float](repeating: 0, count: Int((lead + CGFloat(clip.count) / R + 0.8) * R)); let off = Int(lead * R)
            for i in 0..<min(clip.count, pcm.count - off) { pcm[off + i] = clip[i] }
            for s in segs where s.words == nil { wordTimes(s, pcm, s.start, s.dur, s.start) }
            return MTimeline(segs, lead + CGFloat(clip.count) / R + 0.8, mixAmb(pcm, o), rate)
        } else if rv.hasPrefix("sr:") {
            await status(ayahs.count > 1 ? "جارٍ تحميل التلاوة من الآية \(first.ar) إلى \(last.ar)…" : "جارٍ تحميل صوت الآية \(first.ar)…")
            guard let tm = await Repo.shared.ayahTimes(rv, o.surah), tm.ayahs.count >= last else { throw MakerError(msg: "هذه السورة لم تُجهَّز بعد بصوت هذا القارئ — اختر قارئًا آخر أو سورة أخرى") }
            let ajax = await Repo.ajax, enc = await Repo.enc(rv)
            guard let u = URL(string: ajax + "?action=bz&do=ayah_audio&r=\(enc)&k=\(Quran.key(o.surah, first))" + (last > first ? "&to=\(last)" : "")) else { throw MakerError(msg: "تعذّر تحميل الصوت") }
            let file = try await download(u, "sr-\(rv.dropFirst(3))-\(o.surah)-\(first)-\(last).mp3")
            let clip = try decode(file)
            let st0 = tm.ayahs[first - 1][1], t0 = st0 - st0 % max(1, tm.per)
            let segs: [MSeg] = ayahs.enumerated().map { i, a in
                let st = CGFloat(tm.ayahs[a.n - 1][1] - t0) / 1000
                let en = i + 1 < ayahs.count ? CGFloat(tm.ayahs[ayahs[i + 1].n - 1][1] - t0) / 1000 : min(CGFloat(clip.count) / R, CGFloat(tm.ayahs[a.n - 1][2] - t0) / 1000)
                let sg = MSeg(a, lead + max(0, st), max(0.5, en - max(0, st)))
                if a.n - 1 < tm.words.count, !tm.words[a.n - 1].isEmpty { sg.words = aiWords(a.text, tm.words[a.n - 1]) { lead + CGFloat($0 - t0) / 1000 } }
                return sg
            }
            var pcm = [Float](repeating: 0, count: Int((lead + CGFloat(clip.count) / R + 0.8) * R)); let off = Int(lead * R)
            for i in 0..<min(clip.count, pcm.count - off) { pcm[off + i] = clip[i] }
            for s in segs where s.words == nil { wordTimes(s, pcm, s.start, s.dur, s.start) }
            return MTimeline(segs, lead + CGFloat(clip.count) / R + 0.8, mixAmb(pcm, o), rate)
        } else {
            let folders = MAKER_FOLDERS.first { $0.0 == rv }?.1
            var segs: [MSeg] = [], t = lead, parts: [(CGFloat, [Float])] = []
            for (i, a) in ayahs.enumerated() {
                try Task.checkCancellation()
                var d: CGFloat
                if let folders {
                    await status("جارٍ تحميل صوت الآية \(a.n.ar) (\((i + 1).ar) من \(ayahs.count.ar))…")
                    let key = Quran.key(o.surah, a.n)
                    var f: URL?
                    for fo in folders { f = try? await download(URL(string: "https://everyayah.com/data/\(fo)/\(key).mp3")!, "\(fo)-\(key).mp3"); if f != nil { break } }
                    guard let f else { throw MakerError(msg: "تعذّر تحميل صوت التلاوة لهذا القارئ — جرّب قارئًا آخر أو «بدون صوت»") }
                    let clip = try decode(f); parts.append((t, clip)); d = CGFloat(clip.count) / R
                } else { d = max(4, CGFloat(words(a.text).count) * 0.62) }
                segs.append(MSeg(a, t, d)); t += d + gap
            }
            let total = t - gap + tail
            var pcm: [Float]?
            if folders != nil {
                var out = [Float](repeating: 0, count: Int(total * R) + rate)
                for (at, c) in parts { let o0 = Int(at * R); for i in 0..<min(c.count, out.count - o0) { out[o0 + i] = c[i] } }
                pcm = out
                for s in segs { wordTimes(s, out, s.start, s.dur, s.start) }
            }
            return MTimeline(segs, total, pcm.map { mixAmb($0, o) } ?? (o.amb.isEmpty ? nil : mixAmb([Float](repeating: 0, count: Int(total * R)), o)), rate)
        }
    }

    private static func aiWords(_ text: String, _ wt: [[Int]], _ toTl: (Int) -> CGFloat) -> [CGFloat] {
        let toks = words(text)
        let total = max(1, toks.reduce(0) { $0 + letters($1) }); var acc = 0; var prev: CGFloat?
        return toks.map { t in
            let f = Double(acc) / Double(total) * 1000; acc += letters(t)
            if letters(t) == 0, let prev { return prev }
            var k = 0; while k + 1 < wt.count && Double(wt[k + 1][0]) <= f + 8 { k += 1 }
            var ms = Double(wt[k][1])
            if k + 1 < wt.count && f > Double(wt[k][0]) { ms = Double(wt[k][1]) + Double(wt[k + 1][1] - wt[k][1]) * min(1, (f - Double(wt[k][0])) / Double(max(1, wt[k + 1][0] - wt[k][0]))) }
            let v = toTl(Int(ms)) - 0.06; prev = v; return v
        }
    }
    /// Word starts measured from the audio itself (speech on/off + pauses).
    private static func wordTimes(_ seg: MSeg, _ d: [Float], _ b0: CGFloat, _ dur: CGFloat, _ t0: CGFloat) {
        let ws = words(seg.a.text); if ws.isEmpty { return }
        let sr = rate, hop = Int(Double(sr) * 0.02), i0 = max(0, Int(b0 * CGFloat(sr))), i1 = min(d.count, Int((b0 + dur) * CGFloat(sr)))
        var L: [Double] = []; var i = i0
        while i + hop <= i1 { var s = 0.0; var j = i; while j < i + hop { s += Double(d[j] * d[j]); j += 2 }; L.append(10 * log10(s / Double(hop / 2) + 1e-12)); i += hop }
        if L.count < 10 { return }
        let sm: [Double] = L.indices.map { k in var a = 0.0, c = 0; for j in max(0, k - 2)...min(L.count - 1, k + 2) { a += L[j]; c += 1 }; return a / Double(c) }
        let sorted = sm.sorted(), floor0 = sorted[Int(Double(sorted.count) * 0.05)], loud = sorted[Int(Double(sorted.count) * 0.8)]
        let thr = floor0 + 0.3 * (loud - floor0)
        var on = 0; while on < sm.count && sm[on] < thr { on += 1 }
        var off = sm.count - 1; while off > on && sm[off] < thr { off -= 1 }
        if off - on < 10 { return }
        let pth = floor0 + 0.18 * (loud - floor0); var pauses: [(Int, Int)] = []
        var k = on + 5; while k < off - 5 { if sm[k] >= pth { k += 1; continue }; var j = k; while j < off && sm[j] < pth { j += 1 }; if j - k >= 8 { pauses.append((k, j)) }; k = j }
        let wts = ws.map { max(1.5, Double($0.replacingOccurrences(of: "[\\u0610-\\u061A\\u064B-\\u065F\\u0670\\u06D6-\\u06ED\\u0640]", with: "", options: .regularExpression).count)) }
        var cum = [0.0]; for w in wts { cum.append(cum.last! + w) }; let total = cum.last!
        var anchors = [(0, on)]; var lastK = 0
        let pausesLen = pauses.reduce(0) { $0 + $1.1 - $1.0 }
        for (a, b) in pauses {
            let prevPause = pauses.filter { $0.1 <= a }.reduce(0) { $0 + $1.1 - $1.0 }
            let frac = Double(a - on - prevPause) / Double(max(1, off - on - pausesLen))
            var best = -1; var bd = 1e9; if lastK + 1 < ws.count { for q in (lastK + 1)..<ws.count { let dd = abs(cum[q] / total - frac); if dd < bd { bd = dd; best = q } } }
            if best > 0 && bd < 0.18 { anchors.append((best, b)); lastK = best }
        }
        anchors.append((ws.count, off))
        var st = [Double](repeating: 0, count: ws.count)
        for a in 0..<(anchors.count - 1) { let (k0, f0) = anchors[a], (k1, f1) = anchors[a + 1], span = cum[k1] - cum[k0]
            if k0 < k1 { for q in k0..<k1 { st[q] = Double(f0) + Double(f1 - f0) * (span > 0 ? (cum[q] - cum[k0]) / span : 0) } } }
        seg.words = st.map { CGFloat(Double(t0 - b0) + $0 * 0.02 + Double(b0) - 0.12) }
    }

    /// Nature sound under the recitation (rain, wind, waves, stream, night), generated like the site's Web Audio graph.
    private static func mixAmb(_ pcm0: [Float], _ o: MakerOpts) -> [Float] {
        if o.amb.isEmpty { return pcm0 }
        var pcm = pcm0
        let g = Ambience.render(o.amb, pcm.count, rate), vol = Float(o.ambVol) / 100
        for i in pcm.indices { let fade = min(1, Float(i) / (2.5 * Float(rate))); pcm[i] += g[i] * vol * fade }
        return pcm
    }
}

/// Offline versions of the site's ambient generators.
enum Ambience {
    private final class BQ {
        let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double; var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        init(_ type: String, _ f: Double, _ q: Double, _ sr: Int) {
            let w = 2 * Double.pi * f / Double(sr), al = sin(w) / (2 * q), c = cos(w), a0 = 1 + al
            switch type { case "bp": b0 = al / a0; b1 = 0; b2 = -al / a0
            case "hp": b0 = (1 + c) / 2 / a0; b1 = -(1 + c) / a0; b2 = (1 + c) / 2 / a0
            default: b0 = (1 - c) / 2 / a0; b1 = (1 - c) / a0; b2 = (1 - c) / 2 / a0 }
            a1 = -2 * c / a0; a2 = (1 - al) / a0
        }
        func f(_ x: Double) -> Double { let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2; x2 = x1; x1 = x; y2 = y1; y1 = y; return y }
    }
    static func render(_ kind: String, _ n: Int, _ sr: Int) -> [Float] {
        var out = [Float](repeating: 0, count: n)
        var g = SystemRandomNumberGenerator()
        var brown = 0.0, p0 = 0.0, p1 = 0.0, p2 = 0.0, one = 0.0
        let hp = BQ("hp", 600, 0.7, sr), lp7 = BQ("lp", 7000, 0.7, sr), bp = BQ("bp", 3200, 0.8, sr), lp650 = BQ("lp", 650, 0.7, sr), bp2 = BQ("bp", 2200, 0.6, sr), lp300 = BQ("lp", 300, 0.7, sr)
        for i in 0..<n {
            let t = Double(i) / Double(sr), w = Double.random(in: -1...1, using: &g)
            brown = (brown + 0.02 * w) / 1.02
            p0 = 0.99765 * p0 + w * 0.099046; p1 = 0.963 * p1 + w * 0.2965164; p2 = 0.57 * p2 + w * 1.0526913; let pink = (p0 + p1 + p2 + w * 0.1848) * 0.11
            switch kind {
            case "rain": out[i] = Float(lp7.f(hp.f(pink)) + bp.f(w * 0.5) * (0.25 + 0.12 * sin(2 * .pi * 7 * t)))
            case "wind": let fc = 450 + 260 * sin(2 * .pi * 0.08 * t), a = exp(-2 * .pi * fc / Double(sr)); one = (1 - a) * brown * 3.5 + a * one; out[i] = Float(one * (0.9 + 0.35 * sin(2 * .pi * 0.13 * t)) * 2.2)
            case "waves": out[i] = Float(lp650.f(brown * 3.5) * max(0, 0.6 + 0.55 * sin(2 * .pi * 0.1 * t)))
            case "stream": out[i] = Float(bp2.f(w * 0.5) * (0.5 + 0.15 * sin(2 * .pi * 0.4 * t)) * 1.6)
            case "night": out[i] = Float(lp300.f(brown * 3.5) * 0.35 + (sin(2 * .pi * 18 * t) > 0 ? 0.02 : -0.02) * sin(2 * .pi * 4400 * t) * (0.5 + 0.5 * sin(2 * .pi * 0.25 * t)))
            default: break
            }
        }
        return out
    }
}

/// Frames of background videos (downloaded once).
final class MakerVideoFrames {
    var files: [String: URL] = [:]
    private var gens: [String: AVAssetImageGenerator] = [:]
    private var durs: [String: Double] = [:]
    private var last: [String: (Double, UIImage)] = [:]
    func frame(_ url: String, _ t: CGFloat, _ W: CGFloat, _ H: CGFloat) -> UIImage? {
        guard let f = files[url] else { return nil }
        let g: AVAssetImageGenerator
        if let x = gens[url] { g = x } else {
            let a = AVURLAsset(url: f); g = AVAssetImageGenerator(asset: a); g.appliesPreferredTrackTransform = true
            g.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30); g.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
            g.maximumSize = CGSize(width: W / 2, height: H / 2); gens[url] = g
            durs[url] = max(1, CMTimeGetSeconds(a.duration))
        }
        let d = durs[url] ?? 1, s = Double(t).truncatingRemainder(dividingBy: d)
        if let (at, img) = last[url], abs(at - s) < 0.033 { return img }
        guard let cg = try? g.copyCGImage(at: CMTime(seconds: s, preferredTimescale: 600), actualTime: nil) else { return last[url]?.1 }
        let img = UIImage(cgImage: cg); last[url] = (s, img); return img
    }
    func release() { gens.removeAll(); last.removeAll() }
}

// MARK: - export

enum MakerExport {
    /// Renders the whole timeline to an MP4 (H.264 + AAC): the sound goes to an AAC file first, then the picture, then both are joined.
    static func video(_ ctx: MakerContext, _ tl: MTimeline, _ o: MakerOpts, progress: @escaping (Double) -> Void) async throws -> URL {
        let (W, H) = MAKER_SIZES[o.size] ?? (1080, 1920)
        let tmp = FileManager.default.temporaryDirectory
        let vURL = tmp.appendingPathComponent("maker-v.mp4"), aURL = tmp.appendingPathComponent("maker-a.m4a"), out = tmp.appendingPathComponent("بدر-التلاوات-\(Int(Date().timeIntervalSince1970)).mp4")
        for u in [vURL, aURL, out] { try? FileManager.default.removeItem(at: u) }
        let fps = 30, frames = Int(ceil(tl.total * CGFloat(fps)))
        // picture
        let w = try AVAssetWriter(outputURL: vURL, fileType: .mp4)
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
                                                                          AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: W * H * 5, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
        vIn.expectsMediaDataInRealTime = false
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
        w.add(vIn); w.startWriting(); w.startSession(atSourceTime: .zero)
        for i in 0..<frames {
            try Task.checkCancellation()
            while !vIn.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            guard let pool = ad.pixelBufferPool else { throw MakerError(msg: "تعذّر إنشاء الفيديو") }
            var pb: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let pb else { throw MakerError(msg: "تعذّر إنشاء الفيديو") }
            CVPixelBufferLockBaseAddress(pb, [])
            let t = CGFloat(i) / CGFloat(fps)
            autoreleasepool {
                if let cg = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: W, height: H, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                    cg.translateBy(x: 0, y: CGFloat(H)); cg.scaleBy(x: 1, y: -1)   // top-left origin, as the drawing expects
                    ctx.drawFrame(cg, CGFloat(W), CGFloat(H), MakerEngine.frameAt(tl, t), o)
                    MakerEngine.fadeBlack(cg, CGFloat(W), CGFloat(H), tl.total, t, o)
                }
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            ad.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
            progress(Double(i) / Double(frames) * 0.92)
        }
        vIn.markAsFinished(); await w.finishWriting()
        guard w.status == .completed else { throw w.error ?? MakerError(msg: "تعذّر إنشاء الفيديو") }
        guard let pcm = tl.pcm, !pcm.isEmpty else { try FileManager.default.moveItem(at: vURL, to: out); progress(1); return out }
        // sound → AAC
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(tl.rate), channels: 1, interleaved: false)!
        let af = try AVAudioFile(forWriting: aURL, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: tl.rate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000], commonFormat: .pcmFormatFloat32, interleaved: false)
        var p = 0
        while p < pcm.count {
            let n = min(32768, pcm.count - p)
            let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!; b.frameLength = AVAudioFrameCount(n)
            for i in 0..<n { b.floatChannelData![0][i] = max(-1, min(1, pcm[p + i])) }
            try af.write(from: b); p += n
        }
        _ = af   // closes on release
        progress(0.95)
        // join
        let comp = AVMutableComposition()
        let va = AVURLAsset(url: vURL), aa = AVURLAsset(url: aURL)
        if let vt = try await va.loadTracks(withMediaType: .video).first, let ct = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try ct.insertTimeRange(CMTimeRange(start: .zero, duration: try await va.load(.duration)), of: vt, at: .zero)
        }
        if let at = try await aa.loadTracks(withMediaType: .audio).first, let ct = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let d = min(try await aa.load(.duration), try await va.load(.duration))
            try ct.insertTimeRange(CMTimeRange(start: .zero, duration: d), of: at, at: .zero)
        }
        guard let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else { throw MakerError(msg: "تعذّر إنشاء الفيديو") }
        ex.outputURL = out; ex.outputFileType = .mp4
        await ex.export()
        guard ex.status == .completed else { throw ex.error ?? MakerError(msg: "تعذّر إنشاء الفيديو") }
        progress(1)
        return out
    }
}

/// Ayah timings of a whole-surah reciter (sr:), per ayah [start, end] (ms), words, and the cut boundary.
struct SurahTimes { let ayahs: [[Int]]; let words: [[[Int]]]; let per: Int }
extension Repo {
    func ayahTimes(_ r: String, _ s: Int) async -> SurahTimes? {
        guard let u = URL(string: Repo.ajax + "?action=bz&do=ayah_times&r=\(Repo.enc(r))&s=\(s)"), let (d, _) = try? await session.data(from: u) else { return nil }
        let j = J(data: d)
        guard j["ok"].bool() else { return nil }
        // [start, end] per ayah in order → [ayah, start, end]
        let ay = j["ayahs"].array.enumerated().compactMap { i, e -> [Int]? in let a = e.array.map { Int($0.double ?? 0) }; return a.count >= 2 ? [i + 1, a[0], a[1]] : nil }
        let w = j["words"].array.map { $0.array.map { $0.array.map { Int($0.double ?? 0) } }.filter { $0.count >= 2 } }
        return ay.isEmpty ? nil : SurahTimes(ayahs: ay, words: w, per: max(1, Int(j["per"].double ?? 1)))
    }
}
