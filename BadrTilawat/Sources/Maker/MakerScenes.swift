import UIKit

/* A port of the site's maker (assets/js/maker.js) drawing code — the same as the Android app's maker — to CoreGraphics.
   Coordinates: top-left origin (a UIKit image context). */

struct Rnd { private var s: UInt64
    init(_ seed: Int) { s = UInt64(seed == 0 ? 1 : seed) & 0xffffffff }
    mutating func next() -> CGFloat { s = (s &* 1664525 &+ 1013904223) & 0xffffffff; return CGFloat(Double(s) / 4294967296.0) }
}
struct Th { let text: UIColor, accent: UIColor, soft: UIColor, shadow: UIColor? }
func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: Double) -> UIColor { UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(min(1, max(0, a)))) }
func hex(_ s: String) -> UIColor { ClipEngine.color(s) }

let MAKER_TEMPLATES: [(String, String)] = [("emerald", tr("زمردي ذهبي")), ("night", tr("ليل كحلي")), ("parchment", tr("رقّ قديم")), ("black", tr("أسود بسيط")), ("dawn", tr("فجر")), ("kaaba", tr("الكعبة المشرفة")),
    ("nabawi", tr("المسجد النبوي")), ("ramadan", tr("رمضان")), ("eid", tr("عيد مبارك")), ("sky", tr("سماء وغيوم (متحرك)")), ("sea", tr("بحر عند الغروب (متحرك)")),
    ("stars", tr("ليل ونجوم (متحرك)")), ("gray", tr("رمادي هادئ")), ("mist", tr("رمادي فاتح")), ("babyblue", tr("سماء زرقاء")), ("nightblue", tr("ليل أزرق")),
    ("olive", tr("ورق زيتوني")), ("geo", tr("زخرفة هندسية")), ("video", tr("فيديو متحرك")), ("photo", tr("صورة خلفية"))]
/** light designs: dark text, and dark dust / progress bar on them */
let MAKER_LIGHT: Set<String> = ["parchment", "mist", "babyblue"]
let MAKER_ANIMATED: Set<String> = ["sky", "sea", "stars", "video"]
let MAKER_SCENIC: Set<String> = ["dawn", "kaaba", "nabawi"]

func makerTheme(_ tpl: String) -> Th {
    switch tpl {
    case "night": return Th(text: hex("#eef7f7"), accent: hex("#6fd0c7"), soft: rgba(111, 208, 199, 0.8), shadow: rgba(0, 0, 0, 0.5))
    case "parchment": return Th(text: hex("#3a2914"), accent: hex("#8a6a2e"), soft: rgba(110, 80, 30, 0.8), shadow: nil)
    case "black": return Th(text: hex("#ffffff"), accent: hex("#d4b26a"), soft: rgba(255, 255, 255, 0.6), shadow: nil)
    case "dawn": return Th(text: hex("#fff8ee"), accent: hex("#ffd59a"), soft: rgba(255, 240, 220, 0.85), shadow: rgba(30, 10, 30, 0.55))
    case "photo": return Th(text: hex("#ffffff"), accent: hex("#f0d293"), soft: rgba(255, 255, 255, 0.85), shadow: rgba(0, 0, 0, 0.7))
    case "kaaba": return Th(text: hex("#fbf4e4"), accent: hex("#e8c77e"), soft: rgba(251, 244, 228, 0.85), shadow: rgba(0, 0, 0, 0.6))
    case "nabawi": return Th(text: hex("#f8f6ee"), accent: hex("#9fe0b8"), soft: rgba(248, 246, 238, 0.85), shadow: rgba(0, 10, 5, 0.6))
    case "ramadan": return Th(text: hex("#fff4dc"), accent: hex("#f2c46b"), soft: rgba(255, 240, 210, 0.85), shadow: rgba(20, 0, 30, 0.6))
    case "sky": return Th(text: hex("#ffffff"), accent: hex("#ffe2a8"), soft: rgba(255, 255, 255, 0.9), shadow: rgba(10, 30, 60, 0.55))
    case "sea": return Th(text: hex("#fff8ee"), accent: hex("#ffd28a"), soft: rgba(255, 244, 230, 0.9), shadow: rgba(30, 10, 20, 0.6))
    case "stars": return Th(text: hex("#f4f1ff"), accent: hex("#c9b8ff"), soft: rgba(230, 225, 255, 0.85), shadow: rgba(0, 0, 10, 0.7))
    case "video": return Th(text: hex("#ffffff"), accent: hex("#f0d293"), soft: rgba(255, 255, 255, 0.9), shadow: rgba(0, 0, 0, 0.75))
    case "eid": return Th(text: hex("#fffaf0"), accent: hex("#ffd88a"), soft: rgba(255, 248, 232, 0.88), shadow: rgba(0, 30, 40, 0.55))
    case "gray": return Th(text: hex("#f2f1ee"), accent: hex("#c9ced6"), soft: rgba(226, 229, 234, 0.82), shadow: rgba(0, 0, 0, 0.45))
    case "mist": return Th(text: hex("#25282c"), accent: hex("#6b7380"), soft: rgba(40, 44, 50, 0.78), shadow: nil)
    case "babyblue": return Th(text: hex("#14324f"), accent: hex("#2f7dbb"), soft: rgba(20, 50, 79, 0.8), shadow: nil)
    case "nightblue": return Th(text: hex("#eaf4fb"), accent: hex("#8fcaf2"), soft: rgba(205, 230, 248, 0.86), shadow: rgba(0, 8, 20, 0.55))
    case "olive": return Th(text: hex("#f1ead8"), accent: hex("#d4b26a"), soft: rgba(241, 234, 216, 0.82), shadow: rgba(0, 0, 0, 0.45))
    case "geo": return Th(text: hex("#f3ead6"), accent: hex("#d9b56f"), soft: rgba(217, 181, 111, 0.8), shadow: rgba(0, 0, 0, 0.5))
    default: return Th(text: hex("#f3ead6"), accent: hex("#d9b56f"), soft: rgba(217, 181, 111, 0.75), shadow: rgba(0, 0, 0, 0.45))
    }
}

/* ---------------------------------------------------------------- small helpers */
private let cs = CGColorSpaceCreateDeviceRGB()
func gradient(_ stops: [(CGFloat, UIColor)]) -> CGGradient { CGGradient(colorsSpace: cs, colors: stops.map { $0.1.cgColor } as CFArray, locations: stops.map { $0.0 })! }
/// fills the whole W×H with a linear gradient from (x0,y0) to (x1,y1)
func fillLin(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, _ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ stops: [(CGFloat, UIColor)], rect: CGRect? = nil) {
    c.saveGState(); c.clip(to: rect ?? CGRect(x: 0, y: 0, width: W, height: H))
    c.drawLinearGradient(gradient(stops), start: CGPoint(x: x0, y: y0), end: CGPoint(x: x1, y: y1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}
/// fills the whole W×H with a radial gradient around (x,y) of radius r (the last colour beyond it)
func fillRad(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ stops: [(CGFloat, UIColor)], clipCircle: Bool = false) {
    c.saveGState()
    if clipCircle { c.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)); c.clip() } else { c.clip(to: CGRect(x: 0, y: 0, width: W, height: H)) }
    c.drawRadialGradient(gradient(stops), startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: max(r, 0.01), options: [.drawsAfterEndLocation])
    c.restoreGState()
}
func star8Path(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for k in 0...1 { let o = Double(k) * .pi / 4
        p.move(to: CGPoint(x: cx + r * CGFloat(cos(o)), y: cy + r * CGFloat(sin(o))))
        for i in 1...4 { p.addLine(to: CGPoint(x: cx + r * CGFloat(cos(o + Double(i) * .pi / 2)), y: cy + r * CGFloat(sin(o + Double(i) * .pi / 2)))) }
    }
    return p
}
func archPath(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    let p = CGMutablePath(); let sh = h * 0.3
    p.move(to: CGPoint(x: x, y: y + h)); p.addLine(to: CGPoint(x: x, y: y + sh))
    p.addCurve(to: CGPoint(x: x + w / 2, y: y), control1: CGPoint(x: x, y: y + sh * 0.45), control2: CGPoint(x: x + w * 0.2, y: y + sh * 0.18))
    p.addCurve(to: CGPoint(x: x + w, y: y + sh), control1: CGPoint(x: x + w * 0.8, y: y + sh * 0.18), control2: CGPoint(x: x + w, y: y + sh * 0.45))
    p.addLine(to: CGPoint(x: x + w, y: y + h))
    return p
}
func strokePath(_ c: CGContext, _ p: CGPath, _ col: UIColor, _ w: CGFloat) { c.saveGState(); c.addPath(p); c.setStrokeColor(col.cgColor); c.setLineWidth(w); c.setLineCap(.round); c.setLineJoin(.round); c.strokePath(); c.restoreGState() }
func fillPath(_ c: CGContext, _ p: CGPath, _ col: UIColor) { c.saveGState(); c.addPath(p); c.setFillColor(col.cgColor); c.fillPath(); c.restoreGState() }
func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }
func rectP(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect { CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0) }
func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath { let p = CGMutablePath(); p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) }); p.closeSubpath(); return p }
/// text centred at cx with its baseline at y (right to left, numbers kept in order)
func drawCenteredText(_ s: String, _ cx: CGFloat, _ y: CGFloat, _ font: UIFont, _ color: UIColor) {
    let a = NSAttributedString(string: "\u{200F}" + s, attributes: [.font: font, .foregroundColor: color])
    let w = a.size().width
    a.draw(at: CGPoint(x: cx - w / 2, y: y - font.ascender))
}

/* ---------------------------------------------------------------- static backgrounds */
enum MakerBackgrounds {
    nonisolated(unsafe) static var cache: [String: UIImage] = [:]
    nonisolated(unsafe) static var photo: UIImage?
    static let lock = NSLock()
    static func clear() { lock.lock(); cache.removeAll(); lock.unlock() }
    static func get(_ tpl: String, _ W: Int, _ H: Int) -> UIImage {
        let key = "\(tpl)|\(W)x\(H)|\(photo.map { "\(ObjectIdentifier($0).hashValue)" } ?? "")"
        lock.lock(); if let b = cache[key] { lock.unlock(); return b }; lock.unlock()
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: f).image { r in draw(r.cgContext, tpl, CGFloat(W), CGFloat(H)) }
        lock.lock(); if cache.count > 12 { cache.removeAll() }; cache[key] = img; lock.unlock()
        return img
    }
    private static func lattice(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, step: CGFloat, r: CGFloat, col: UIColor, w: CGFloat, stagger: Bool = true, circle: CGFloat = 0) {
        var y: CGFloat = 0, row = 0
        while y < H + step { var x: CGFloat = 0
            while x < W + step { let cx = x + (stagger && row % 2 == 1 ? step / 2 : 0); strokePath(c, star8Path(cx, y, r), col, w); if circle > 0 { strokePath(c, CGPath(ellipseIn: CGRect(x: cx - circle, y: y - circle, width: 2 * circle, height: 2 * circle), transform: nil), col, w) }; x += step }
            y += step; row += 1 }
    }
    private static func draw(_ c: CGContext, _ tpl: String, _ W: CGFloat, _ H: CGFloat) {
        let u = min(W, H) / 1080; var R = Rnd(7)
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ col: UIColor) { c.setFillColor(col.cgColor); c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ col: UIColor) { c.setFillColor(col.cgColor); c.fill(CGRect(x: x, y: y, width: w, height: h)) }
        switch tpl {
        case "emerald":
            fillLin(c, W, H, 0, 0, 0, H, [(0, hex("#0a1815")), (0.5, hex("#10261f")), (1, hex("#081311"))])
            fillRad(c, W, H, W / 2, H * 0.45, max(W, H) * 0.6, [(0, rgba(201, 164, 92, 0.16)), (1, rgba(201, 164, 92, 0))])
            lattice(c, W, H, step: 150 * u, r: 46 * u, col: rgba(201, 164, 92, 0.08), w: 1.5 * u)
            strokePath(c, rr(rectP(44 * u, 44 * u, W - 44 * u, H - 44 * u), 26 * u), rgba(217, 181, 111, 0.75), 3 * u)
            strokePath(c, rr(rectP(64 * u, 64 * u, W - 64 * u, H - 64 * u), 18 * u), rgba(217, 181, 111, 0.35), 1.5 * u)
            let aw = W * 0.78, ah = H * (H > W ? 0.7 : 0.78)
            strokePath(c, archPath((W - aw) / 2, (H - ah) / 2 - 10 * u, aw, ah), rgba(217, 181, 111, 0.42), 2 * u)
        case "night":
            fillLin(c, W, H, 0, 0, W, H, [(0, hex("#050f16")), (0.6, hex("#0b1f2b")), (1, hex("#06121a"))])
            for _ in 0..<140 { let a = 0.15 + Double(R.next()) * 0.5; dot(R.next() * W, R.next() * H * 0.9, (R.next() * 1.6 + 0.4) * u, rgba(255, 255, 255, a)) }
            fillRad(c, W, H, W * 0.5, H * 0.5, W * 0.8, [(0, rgba(94, 194, 187, 0.12)), (1, rgba(94, 194, 187, 0))])
        case "parchment":
            box(0, 0, W, H, hex("#efe3c8"))
            for _ in 0..<2600 { let col = rgba(120, 85, 35, Double(R.next()) * 0.05); let x = R.next() * W, y = R.next() * H; box(x, y, (R.next() * 3 + 1) * u, (R.next() * 3 + 1) * u, col) }
            fillRad(c, W, H, W / 2, H / 2, max(W, H) * 0.75, [(0, rgba(90, 60, 20, 0)), (0.4, rgba(90, 60, 20, 0)), (1, rgba(90, 60, 20, 0.35))])
            strokePath(c, CGPath(rect: rectP(50 * u, 50 * u, W - 50 * u, H - 50 * u), transform: nil), hex("#8a6a2e"), 4 * u)
            strokePath(c, CGPath(rect: rectP(66 * u, 66 * u, W - 66 * u, H - 66 * u), transform: nil), hex("#8a6a2e"), 1.5 * u)
            for (x, y) in [(66, 66), (W / u - 66, 66), (66, H / u - 66), (W / u - 66, H / u - 66)] as [(CGFloat, CGFloat)] { strokePath(c, star8Path(x * u, y * u, 30 * u), hex("#8a6a2e"), 2 * u) }
        case "gray", "mist", "olive":
            let c0 = tpl == "gray" ? ["#2c2e32", "#1f2124", "#151618"] : tpl == "mist" ? ["#f1f2f4", "#e4e7ea", "#d9dde2"] : ["#2a3423", "#1f281a", "#161d12"]
            let grain = tpl == "mist" ? (60, 66, 75) : tpl == "gray" ? (255, 255, 255) : (255, 248, 220)
            let ac = tpl == "mist" ? (107, 115, 128) : tpl == "gray" ? (201, 206, 214) : (212, 178, 106)
            func A(_ a: Double) -> UIColor { rgba(ac.0, ac.1, ac.2, a) }
            fillLin(c, W, H, 0, 0, 0, H, [(0, hex(c0[0])), (0.55, hex(c0[1])), (1, hex(c0[2]))])
            for _ in 0..<5200 { let col = rgba(grain.0, grain.1, grain.2, Double(R.next()) * (tpl == "mist" ? 0.05 : 0.045)); let x = R.next() * W, y = R.next() * H; box(x, y, (R.next() * 2.4 + 0.6) * u, (R.next() * 2.4 + 0.6) * u, col) }
            fillRad(c, W, H, W / 2, H * 0.46, max(W, H) * 0.62, [(0, tpl == "mist" ? rgba(255, 255, 255, 0.55) : A(0.14)), (1, rgba(0, 0, 0, 0))])
            fillRad(c, W, H, W / 2, H / 2, max(W, H) * 0.78, [(0, rgba(0, 0, 0, 0)), (0.45, rgba(0, 0, 0, 0)), (1, tpl == "mist" ? rgba(60, 66, 75, 0.16) : rgba(0, 0, 0, 0.42))])
            lattice(c, W, H, step: 150 * u, r: 46 * u, col: A(tpl == "mist" ? 0.14 : 0.1), w: 1.5 * u)
            let mid = tpl == "mist" ? rgba(236, 238, 241, 0.85) : tpl == "olive" ? rgba(31, 40, 26, 0.8) : rgba(31, 33, 36, 0.8)
            fillRad(c, W, H, W / 2, H * 0.47, max(W, H) * 0.45, [(0, mid), (1, rgba(0, 0, 0, 0))])
            let aw = W * 0.78, ah = H * (H > W ? 0.7 : 0.78)
            strokePath(c, archPath((W - aw) / 2, (H - ah) / 2 - 10 * u, aw, ah), A(0.45), 2 * u)
            strokePath(c, rr(rectP(50 * u, 50 * u, W - 50 * u, H - 50 * u), 22 * u), A(0.7), 2.5 * u)
            strokePath(c, rr(rectP(68 * u, 68 * u, W - 68 * u, H - 68 * u), 16 * u), A(0.32), 1.2 * u)
            for (x, y) in [(68, 68), (W / u - 68, 68), (68, H / u - 68), (W / u - 68, H / u - 68)] as [(CGFloat, CGFloat)] { strokePath(c, star8Path(x * u, y * u, 24 * u), A(0.6), 1.6 * u) }
        case "babyblue":
            fillLin(c, W, H, 0, 0, 0, H, [(0, hex("#bcdcf5")), (0.5, hex("#dcecfa")), (1, hex("#f2f8fd"))])
            for cl in [[0.18, 0.12, 0.62, 0.1], [0.78, 0.24, 0.5, 0.08], [0.3, 0.78, 0.7, 0.11], [0.85, 0.9, 0.55, 0.09]] as [[CGFloat]] {
                let cx = cl[0] * W, cy = cl[1] * H, rw = cl[2] * W, rh = cl[3] * H
                c.saveGState(); c.translateBy(x: cx, y: cy); c.scaleBy(x: 1, y: rh / rw * 2.2); c.translateBy(x: -cx, y: -cy)
                fillRad(c, W, H, cx, cy, rw / 2, [(0, rgba(255, 255, 255, 0.95)), (0.55, rgba(255, 255, 255, 0.45)), (1, rgba(255, 255, 255, 0))], clipCircle: true)
                c.restoreGState()
            }
            fillRad(c, W, H, W / 2, H * 0.46, max(W, H) * 0.5, [(0, rgba(255, 255, 255, 0.55)), (1, rgba(255, 255, 255, 0))])
            strokePath(c, rr(rectP(50 * u, 50 * u, W - 50 * u, H - 50 * u), 28 * u), rgba(47, 125, 187, 0.55), 2.5 * u)
            strokePath(c, rr(rectP(68 * u, 68 * u, W - 68 * u, H - 68 * u), 20 * u), rgba(47, 125, 187, 0.22), 1.2 * u)
        case "nightblue":
            fillLin(c, W, H, 0, 0, 0, H, [(0, hex("#163352")), (0.55, hex("#0e2032")), (1, hex("#0a1828"))])
            for _ in 0..<120 { let a = 0.12 + Double(R.next()) * 0.45; dot(R.next() * W, R.next() * H * 0.85, (R.next() * 1.5 + 0.4) * u, rgba(220, 238, 255, a)) }
            fillRad(c, W, H, W * 0.2, -H * 0.05, max(W, H) * 0.7, [(0, rgba(143, 202, 242, 0.22)), (1, rgba(143, 202, 242, 0))])
            fillRad(c, W, H, W * 0.9, H * 1.02, max(W, H) * 0.6, [(0, rgba(143, 202, 242, 0.14)), (1, rgba(143, 202, 242, 0))])
            c.saveGState(); c.setShadow(offset: .zero, blur: 24 * u, color: rgba(143, 202, 242, 0.7).cgColor)
            let moon = CGMutablePath(); moon.addEllipse(in: CGRect(x: W * 0.8 - 34 * u, y: H * 0.1 - 34 * u, width: 68 * u, height: 68 * u)); moon.addEllipse(in: CGRect(x: W * 0.8 + 12 * u - 30 * u, y: H * 0.1 - 8 * u - 30 * u, width: 60 * u, height: 60 * u))
            c.addPath(moon); c.setFillColor(rgba(222, 238, 252, 0.85).cgColor); c.fillPath(using: .evenOdd); c.restoreGState()
            let aw = W * 0.78, ah = H * (H > W ? 0.7 : 0.78)
            strokePath(c, archPath((W - aw) / 2, (H - ah) / 2 - 10 * u, aw, ah), rgba(143, 202, 242, 0.35), 2 * u)
        case "geo":
            fillLin(c, W, H, 0, 0, 0, H, [(0, hex("#0f1b18")), (0.5, hex("#0c1613")), (1, hex("#09110f"))])
            lattice(c, W, H, step: 96 * u, r: 30 * u, col: rgba(217, 181, 111, 0.32), w: 1.4 * u, stagger: false, circle: 7 * u)
            fillRad(c, W, H, W / 2, H * 0.47, max(W, H) * 0.55, [(0, rgba(12, 22, 19, 1)), (0.55, rgba(12, 22, 19, 0.92)), (1, rgba(12, 22, 19, 0))])
            strokePath(c, rr(rectP(46 * u, 46 * u, W - 46 * u, H - 46 * u), 24 * u), rgba(217, 181, 111, 0.7), 2.5 * u)
        case "black": box(0, 0, W, H, .black)
        case "dawn":
            fillLin(c, W, H, 0, 0, 0, H, [(0, hex("#141631")), (0.45, hex("#523a6e")), (0.75, hex("#c97a6a")), (1, hex("#f2b77a"))])
            fillRad(c, W, H, W / 2, H * 0.92, W * 0.7, [(0, rgba(255, 214, 150, 0.75)), (1, rgba(255, 214, 150, 0))])
            for _ in 0..<60 { let a = Double(R.next()) * 0.6; dot(R.next() * W, R.next() * H * 0.4, R.next() * 1.5 * u + 0.3, rgba(255, 255, 255, a)) }
            let s = hex("#120c1c"), base = H - 30 * u, cx = W / 2
            box(0, base - 40 * u, W, 80 * u, s)
            c.setFillColor(s.cgColor); c.addEllipse(in: CGRect(x: cx - 170 * u, y: base - 190 * u, width: 340 * u, height: 300 * u)); c.fillPath()
            box(cx - 4 * u, base - 240 * u, 8 * u, 60 * u, s); dot(cx, base - 246 * u, 10 * u, s)
            for d in [-1.0, 1.0] as [CGFloat] { let mx = cx + d * 320 * u
                box(mx - 18 * u, base - 330 * u, 36 * u, 330 * u, s)
                fillPath(c, poly([(mx - 24 * u, base - 330 * u), (mx, base - 400 * u), (mx + 24 * u, base - 330 * u)]), s)
                box(mx - 26 * u, base - 250 * u, 52 * u, 10 * u, s) }
            for d in [-1.0, 1.0] as [CGFloat] { c.setFillColor(s.cgColor); c.addEllipse(in: CGRect(x: cx + d * 190 * u - 70 * u, y: base - 110 * u, width: 140 * u, height: 140 * u)); c.fillPath() }
        case "kaaba": kaaba(c, W, H, u, &R)
        case "nabawi": nabawi(c, W, H, u, &R)
        case "ramadan": ramadan(c, W, H, u, &R)
        case "eid":
            fillLin(c, W, H, 0, 0, 0, H, [(0, hex("#06323a")), (0.6, hex("#0b4b52")), (1, hex("#1d6a5c"))])
            lattice(c, W, H, step: 170 * u, r: 54 * u, col: rgba(255, 216, 138, 0.13), w: 2 * u)
            let cols = [hex("#ffd88a"), hex("#f6a96b"), hex("#ffffff"), hex("#9fe0d0")]
            for i in 0..<160 { c.saveGState(); c.translateBy(x: R.next() * W, y: R.next() * H); c.rotate(by: R.next() * 6.28); c.setFillColor(cols[i % 4].withAlphaComponent(0.25 + R.next() * 0.45).cgColor); c.fill(CGRect(x: -4 * u, y: -1.5 * u, width: 8 * u, height: 3 * u)); c.restoreGState() }
            strokePath(c, rr(rectP(50 * u, 50 * u, W - 50 * u, H - 50 * u), 30 * u), rgba(255, 216, 138, 0.8), 3 * u)
            UIGraphicsPushContext(c)
            drawCenteredText(tr("عيدكم مبارك"), W / 2, H - (H > W ? 290 : 190) * u, ClipEngine.font("amiriB", 46 * u), hex("#ffd88a"))
            drawCenteredText(tr("تقبّل الله منا ومنكم صالح الأعمال"), W / 2, H - (H > W ? 240 : 145) * u, ClipEngine.font("plex", 26 * u), rgba(255, 248, 232, 0.85))
            UIGraphicsPopContext()
        case "sky": fillLin(c, W, H, 0, 0, 0, H, [(0, hex("#2c6fb3")), (0.55, hex("#7fb3de")), (1, hex("#f2d9b8"))])
        case "sea":
            fillLin(c, W, H, 0, 0, 0, H * 0.62, [(0, hex("#2a1846")), (0.45, hex("#a8436a")), (0.8, hex("#f08a4b")), (1, hex("#ffc982"))])
            fillLin(c, W, H, 0, H * 0.62, 0, H, [(0, hex("#5a2c4c")), (1, hex("#120c24"))], rect: CGRect(x: 0, y: H * 0.62, width: W, height: H * 0.38))
        case "stars":
            fillLin(c, W, H, 0, 0, 0, H, [(0, hex("#05061a")), (0.6, hex("#121638")), (1, hex("#2a1f3d"))])
            c.saveGState(); c.translateBy(x: W / 2, y: H * 0.4); c.rotate(by: -0.5)
            c.saveGState(); c.clip(to: CGRect(x: -W * 1.2, y: -160 * u, width: W * 2.4, height: 320 * u))
            c.drawLinearGradient(gradient([(0, rgba(160, 140, 255, 0)), (0.5, rgba(190, 170, 255, 0.16)), (1, rgba(160, 140, 255, 0))]), start: CGPoint(x: 0, y: -160 * u), end: CGPoint(x: 0, y: 160 * u), options: [])
            c.restoreGState(); c.restoreGState()
            let p = CGMutablePath(); p.move(to: CGPoint(x: 0, y: H)); p.addLine(to: CGPoint(x: 0, y: H * 0.86)); var x: CGFloat = 0
            while x <= W { p.addQuadCurve(to: CGPoint(x: x + W / 8, y: H * (0.84 + R.next() * 0.04)), control: CGPoint(x: x + W / 16, y: H * (0.8 + R.next() * 0.06))); x += W / 8 }
            p.addLine(to: CGPoint(x: W, y: H)); p.closeSubpath(); fillPath(c, p, hex("#0a0a16"))
        case "video": box(0, 0, W, H, hex("#0b0f10"))
        case "photo":
            box(0, 0, W, H, hex("#111111"))
            if let img = photo {
                let s = max(W / img.size.width, H / img.size.height), iw = img.size.width * s, ih = img.size.height * s
                UIGraphicsPushContext(c); img.draw(in: CGRect(x: (W - iw) / 2, y: (H - ih) / 2, width: iw, height: ih)); UIGraphicsPopContext()
            }
            fillLin(c, W, H, 0, 0, 0, H, [(0, rgba(0, 0, 0, 0.55)), (0.5, rgba(0, 0, 0, 0.4)), (1, rgba(0, 0, 0, 0.7))])
        default: box(0, 0, W, H, .black)
        }
    }

    private static func kaaba(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, _ u: CGFloat, _ R: inout Rnd) {
        fillLin(c, W, H, 0, 0, 0, H, [(0, hex("#05070d")), (0.55, hex("#0d1a2a")), (1, hex("#2a2a2a"))])
        for _ in 0..<120 { let a = Double(R.next()) * 0.55; let x = R.next() * W, y = R.next() * H * 0.45, r = (R.next() * 1.4 + 0.3) * u; c.setFillColor(rgba(255, 255, 255, a).cgColor); c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
        let base = H * (H > W ? 0.92 : 0.95), cx = W / 2, s = (H > W ? 1.15 : 0.8) * u
        let ah = 150 * s, ay = base - 340 * s
        var x = -40 * s
        while x < W + 80 * s {
            let p = CGMutablePath(); p.move(to: CGPoint(x: x, y: ay + ah)); p.addLine(to: CGPoint(x: x, y: ay + 50 * s)); p.addQuadCurve(to: CGPoint(x: x + 80 * s, y: ay + 50 * s), control: CGPoint(x: x + 40 * s, y: ay))
            p.addLine(to: CGPoint(x: x + 80 * s, y: ay + ah)); p.addLine(to: CGPoint(x: x + 70 * s, y: ay + ah)); p.addLine(to: CGPoint(x: x + 70 * s, y: ay + 56 * s))
            p.addQuadCurve(to: CGPoint(x: x + 10 * s, y: ay + 56 * s), control: CGPoint(x: x + 40 * s, y: ay + 18 * s)); p.addLine(to: CGPoint(x: x + 10 * s, y: ay + ah)); p.closeSubpath()
            fillPath(c, p, rgba(225, 215, 190, 0.16)); x += 80 * s
        }
        for d in [-1.0, 1.0] as [CGFloat] { let mx = cx + d * 430 * s
            c.setFillColor(rgba(225, 215, 190, 0.22).cgColor); c.fill(rectP(mx - 9 * s, base - 720 * s, mx + 9 * s, base - 200 * s))
            fillPath(c, poly([(mx - 12 * s, base - 720 * s), (mx, base - 790 * s), (mx + 12 * s, base - 720 * s)]), rgba(225, 215, 190, 0.22)) }
        fillLin(c, W, H, 0, ay + ah, 0, H, [(0, hex("#cfc9bb")), (1, hex("#8f8a7f"))], rect: rectP(0, ay + ah, W, H))
        fillRad(c, W, H, cx, base - 160 * s, 420 * s, [(0, rgba(255, 230, 170, 0.35)), (1, rgba(255, 230, 170, 0))])
        let fw = 230 * s, sw = 120 * s, kh = 260 * s, kx = cx - (fw + sw) / 2, ky = base - kh - 40 * s
        c.setFillColor(hex("#0b0b0c").cgColor); c.fill(rectP(kx, ky, kx + fw, ky + kh))
        fillPath(c, poly([(kx + fw, ky), (kx + fw + sw, ky - 26 * s), (kx + fw + sw, ky + kh - 26 * s), (kx + fw, ky + kh)]), hex("#060607"))
        fillPath(c, poly([(kx, ky), (kx + sw, ky - 26 * s), (kx + fw + sw, ky - 26 * s), (kx + fw, ky)]), hex("#121214"))
        let by = ky + kh * 0.2, bh = 24 * s
        let gold = [(CGFloat(0), hex("#9c7a35")), (0.5, hex("#f3d78e")), (1, hex("#8a6a2e"))]
        func goldFill(_ p: CGPath) { c.saveGState(); c.addPath(p); c.clip(); c.drawLinearGradient(gradient(gold), start: CGPoint(x: kx, y: 0), end: CGPoint(x: kx + fw + sw, y: 0), options: []); c.restoreGState() }
        goldFill(CGPath(rect: rectP(kx, by, kx + fw, by + bh), transform: nil))
        goldFill(poly([(kx + fw, by), (kx + fw + sw, by - 26 * s), (kx + fw + sw, by - 26 * s + bh), (kx + fw, by + bh)]))
        var lx = kx + 8 * s
        c.setStrokeColor(rgba(60, 40, 10, 0.6).cgColor); c.setLineWidth(1 * s)
        while lx < kx + fw { c.move(to: CGPoint(x: lx, y: by + 5 * s)); c.addLine(to: CGPoint(x: lx + 6 * s, y: by + bh - 5 * s)); c.strokePath(); lx += 16 * s }
        goldFill(CGPath(rect: rectP(kx + fw * 0.62, ky + kh * 0.42, kx + fw * 0.84, ky + kh * 0.88), transform: nil))
        c.setFillColor(rgba(255, 255, 255, 0.05).cgColor); c.fill(rectP(kx, ky, kx + fw * 0.08, ky + kh))
    }

    private static func nabawi(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, _ u: CGFloat, _ R: inout Rnd) {
        fillLin(c, W, H, 0, 0, 0, H, [(0, hex("#0c1b2b")), (0.6, hex("#2b4d5c")), (1, hex("#d9a36a"))])
        for _ in 0..<70 { let a = Double(R.next()) * 0.5; let x = R.next() * W, y = R.next() * H * 0.4, r = (R.next() * 1.3 + 0.3) * u; c.setFillColor(rgba(255, 255, 255, a).cgColor); c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
        let base = H - 30 * u, cx = W / 2, s = (H > W ? 1.1 : 0.8) * u, sil = hex("#14231f")
        c.setFillColor(sil.cgColor); c.fill(rectP(0, base - 110 * s, W, H))
        var x: CGFloat = 0
        while x < W { let p = CGMutablePath(); p.move(to: CGPoint(x: x, y: base - 110 * s)); p.addQuadCurve(to: CGPoint(x: x + 70 * s, y: base - 110 * s), control: CGPoint(x: x + 35 * s, y: base - 150 * s)); p.closeSubpath(); fillPath(c, p, sil); x += 70 * s }
        let dx = cx - 120 * s
        c.setFillColor(sil.cgColor); c.fill(rectP(dx - 95 * s, base - 230 * s, dx + 95 * s, base - 105 * s))
        let dome = CGMutablePath(); dome.move(to: CGPoint(x: dx - 105 * s, y: base - 225 * s))
        dome.addCurve(to: CGPoint(x: dx, y: base - 430 * s), control1: CGPoint(x: dx - 105 * s, y: base - 380 * s), control2: CGPoint(x: dx - 10 * s, y: base - 400 * s))
        dome.addCurve(to: CGPoint(x: dx + 105 * s, y: base - 225 * s), control1: CGPoint(x: dx + 10 * s, y: base - 400 * s), control2: CGPoint(x: dx + 105 * s, y: base - 380 * s)); dome.closeSubpath()
        c.saveGState(); c.addPath(dome); c.clip(); c.drawLinearGradient(gradient([(0, hex("#0f5a36")), (0.45, hex("#2fa66a")), (1, hex("#0c4a2d"))]), start: CGPoint(x: dx - 110 * s, y: 0), end: CGPoint(x: dx + 110 * s, y: 0), options: []); c.restoreGState()
        let g = hex("#e8c77e")
        c.setFillColor(g.cgColor); c.fill(rectP(dx - 2 * s, base - 470 * s, dx + 2 * s, base - 428 * s)); c.fillEllipse(in: CGRect(x: dx - 7 * s, y: base - 483 * s, width: 14 * s, height: 14 * s))
        for (mx, h) in [(cx + 140 * s, CGFloat(560)), (cx + 330 * s, 500), (cx - 380 * s, 520)] {
            let w = hex("#e9e1cf"); c.setFillColor(w.cgColor)
            c.fill(rectP(mx - 14 * s, base - h * s, mx + 14 * s, base - 100 * s))
            for k in [0.35, 0.6] as [CGFloat] { let yy = base - h * s + (h * s - 100 * s) * k; c.fill(rectP(mx - 24 * s, yy, mx + 24 * s, yy + 12 * s)) }
            fillPath(c, poly([(mx - 16 * s, base - h * s), (mx, base - (h + 80) * s), (mx + 16 * s, base - h * s)]), w)
            c.setFillColor(g.cgColor); c.fill(rectP(mx - 1.5 * s, base - (h + 104) * s, mx + 1.5 * s, base - (h + 78) * s))
        }
        fillRad(c, W, H, dx, base - 300 * s, 360 * s, [(0, rgba(120, 220, 160, 0.18)), (1, rgba(120, 220, 160, 0))])
    }

    private static func ramadan(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, _ u: CGFloat, _ R: inout Rnd) {
        fillLin(c, W, H, 0, 0, W, H, [(0, hex("#120a2a")), (0.6, hex("#2a1748")), (1, hex("#0d0a1f"))])
        for _ in 0..<160 { let a = Double(R.next()) * 0.6; let x = R.next() * W, y = R.next() * H, r = (R.next() * 1.6 + 0.3) * u; c.setFillColor(rgba(255, 236, 200, a).cgColor); c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
        let mx = W * 0.78, my = H * (H > W ? 0.1 : 0.16), mr = 70 * u
        c.saveGState(); c.setShadow(offset: .zero, blur: 40 * u, color: rgba(242, 196, 107, 0.7).cgColor); c.beginTransparencyLayer(auxiliaryInfo: nil)
        c.setFillColor(hex("#f2c46b").cgColor); c.fillEllipse(in: CGRect(x: mx - mr, y: my - mr, width: 2 * mr, height: 2 * mr))
        c.setBlendMode(.clear); let r2 = mr * 0.9; c.fillEllipse(in: CGRect(x: mx + mr * 0.42 - r2, y: my - mr * 0.18 - r2, width: 2 * r2, height: 2 * r2))
        c.endTransparencyLayer(); c.restoreGState()
        for (fx, fl, sc) in [(0.14, 0.2, 1.0), (0.28, 0.12, 0.75), (0.86, 0.26, 0.85)] as [(CGFloat, CGFloat, CGFloat)] {
            let x = W * fx, len = H * fl, z = sc * u
            c.setStrokeColor(rgba(242, 196, 107, 0.6).cgColor); c.setLineWidth(2 * u); c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: len)); c.strokePath()
            c.saveGState(); c.translateBy(x: x, y: len)
            c.saveGState(); c.clip(to: CGRect(x: -150 * z, y: -80 * z, width: 300 * z, height: 300 * z))
            c.drawRadialGradient(gradient([(0, rgba(255, 200, 110, 0.55)), (1, rgba(255, 200, 110, 0))]), startCenter: CGPoint(x: 0, y: 70 * z), startRadius: 0, endCenter: CGPoint(x: 0, y: 70 * z), endRadius: 150 * z, options: [])
            c.restoreGState()
            let b = hex("#c8963e")
            fillPath(c, poly([(-18 * z, 0), (18 * z, 0), (34 * z, 26 * z), (-34 * z, 26 * z)]), b)
            fillPath(c, poly([(-34 * z, 26 * z), (34 * z, 26 * z), (28 * z, 112 * z), (-28 * z, 112 * z)]), rgba(255, 214, 140, 0.92))
            c.setStrokeColor(hex("#9c6f28").cgColor); c.setLineWidth(3 * z)
            for d in [-12.0, 12.0] as [CGFloat] { c.move(to: CGPoint(x: d * z, y: 26 * z)); c.addLine(to: CGPoint(x: d * 0.8 * z, y: 112 * z)); c.strokePath() }
            fillPath(c, poly([(-28 * z, 112 * z), (28 * z, 112 * z), (12 * z, 136 * z), (-12 * z, 136 * z)]), b)
            c.restoreGState()
        }
        UIGraphicsPushContext(c)
        drawCenteredText(tr("رمضان كريم"), W / 2, H - (H > W ? 110 : 70) * u, ClipEngine.font("amiriB", 34 * u), rgba(242, 196, 107, 0.9))
        UIGraphicsPopContext()
    }
}

/* ---------------------------------------------------------------- animated scenes & effects */
enum MakerAnimated {
    nonisolated(unsafe) private static var cloud: UIImage?
    nonisolated(unsafe) private static var cloudU: CGFloat = 0
    private static func cloudSprite(_ u: CGFloat) -> UIImage {
        if let cloud, cloudU == u { return cloud }
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = false
        var R = Rnd(11)
        let img = UIGraphicsImageRenderer(size: CGSize(width: max(1, 700 * u), height: max(1, 300 * u)), format: f).image { r in
            let c = r.cgContext
            for _ in 0..<26 { let cx = (120 + R.next() * 460) * u, cy = (120 + R.next() * 90) * u, rad = (50 + R.next() * 70) * u
                fillRad(c, 700 * u, 300 * u, cx, cy, rad, [(0, rgba(255, 255, 255, 0.55)), (1, rgba(255, 255, 255, 0))], clipCircle: true) }
        }
        cloud = img; cloudU = u; return img
    }
    static func scene(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, _ tpl: String, _ t: CGFloat, _ u: CGFloat) {
        switch tpl {
        case "sky":
            fillRad(c, W, H, W * 0.78, H * 0.16, 380 * u, [(0, rgba(255, 248, 220, 0.95)), (0.12, rgba(255, 240, 200, 0.6)), (1, rgba(255, 240, 200, 0))])
            let sp = cloudSprite(u); var R = Rnd(5)
            UIGraphicsPushContext(c)
            for _ in 0..<9 {
                let sc = 0.6 + R.next() * 0.9, sw = sp.size.width * sc, y = H * (0.05 + R.next() * 0.75), sp0 = (8 + R.next() * 18) * u
                let x = (R.next() * (W + sw) + t * sp0).truncatingRemainder(dividingBy: W + sw) - sw
                sp.draw(in: CGRect(x: x, y: y, width: sw, height: sp.size.height * sc), blendMode: .normal, alpha: 0.55 + R.next() * 0.4)
            }
            UIGraphicsPopContext()
        case "sea":
            let hz = H * 0.62, sx = W * 0.5, sy = hz - 40 * u
            c.saveGState(); c.clip(to: CGRect(x: 0, y: 0, width: W, height: hz))
            c.drawRadialGradient(gradient([(0, rgba(255, 220, 150, 0.75)), (1, rgba(255, 200, 120, 0))]), startCenter: CGPoint(x: sx, y: sy), startRadius: 0, endCenter: CGPoint(x: sx, y: sy), endRadius: 520 * u, options: [])
            c.setFillColor(hex("#ffe7b0").cgColor); c.addArc(center: CGPoint(x: sx, y: sy), radius: 90 * u, startAngle: .pi, endAngle: 0, clockwise: false); c.closePath(); c.fillPath()
            c.restoreGState()
            for i in 0..<70 {
                let k = CGFloat(i) / 70, y = hz + pow(k, 1.6) * (H - hz), amp = (2 + k * 10) * u, wl = (0.004 + (1 - k) * 0.01) / u
                let p = CGMutablePath(); var x: CGFloat = 0
                while x <= W { let yy = y + sin(x * wl + t * (1.2 + k) + CGFloat(i)) * amp; if x == 0 { p.move(to: CGPoint(x: x, y: yy)) } else { p.addLine(to: CGPoint(x: x, y: yy)) }; x += 24 * u }
                strokePath(c, p, rgba(255, Int(190 - k * 80), Int(140 - k * 60), 0.10 + Double(1 - k) * 0.22), (1 + k * 3) * u)
            }
            var R = Rnd(3)
            for i in 0..<90 {
                let y = hz + R.next() * (H - hz) * 0.7, w = (20 + R.next() * 80) * u * (1 - (y - hz) / (H - hz) * 0.3)
                let a = (0.15 + 0.5 * pow(sin(Double(t) * 2 + Double(i)), 2)) * Double(1 - (y - hz) / (H - hz)); let rr0 = R.next()
                let xx = sx - w / 2 + sin(t + CGFloat(i)) * 60 * u * rr0
                c.setFillColor(rgba(255, 225, 170, a).cgColor); c.fill(CGRect(x: xx, y: y, width: w, height: 3 * u))
            }
        case "stars":
            var R = Rnd(21)
            for _ in 0..<260 {
                let x = R.next() * W, y = R.next() * H * 0.85, r = (R.next() * 1.8 + 0.3) * u, ph = R.next() * 6.28, sp = 0.6 + R.next() * 2.2
                c.setFillColor(rgba(255, 255, 255, 0.25 + 0.75 * Double(abs(sin(t * sp + ph)))).cgColor); c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
            let cyc: CGFloat = 6, k = t.truncatingRemainder(dividingBy: cyc) / 1.1
            if k < 1 {
                let x0 = W * (0.15 + 0.5 * (floor(t / cyc) * 0.37).truncatingRemainder(dividingBy: 1)), y0 = H * 0.12, x = x0 + k * 420 * u, y = y0 + k * 240 * u
                c.saveGState(); c.setLineWidth(2.5 * u); c.setLineCap(.round)
                c.move(to: CGPoint(x: x - 160 * u, y: y - 92 * u)); c.addLine(to: CGPoint(x: x, y: y)); c.replacePathWithStrokedPath(); c.clip()
                c.drawLinearGradient(gradient([(0, rgba(255, 255, 255, 0)), (1, rgba(255, 255, 255, 0.9 * Double(1 - k)))]), start: CGPoint(x: x - 160 * u, y: y - 92 * u), end: CGPoint(x: x, y: y), options: [])
                c.restoreGState()
            }
        default: break
        }
    }
    struct Fx { let rays: Bool, bokeh: Bool, rain: Bool, vignette: Bool }
    static func effects(_ c: CGContext, _ W: CGFloat, _ H: CGFloat, _ t: CGFloat, _ u: CGFloat, _ tpl: String, _ fx: Fx) {
        if fx.rays {
            c.saveGState(); c.setBlendMode(.plusLighter); c.translateBy(x: W * 0.5, y: -H * 0.08)
            for i in 0..<7 {
                let a = -0.55 + CGFloat(i) * 0.18 + sin(t * 0.25 + CGFloat(i)) * 0.05
                c.saveGState(); c.rotate(by: a)
                c.addPath(poly([(-18 * u, 0), (18 * u, 0), (120 * u, H * 1.1), (-120 * u, H * 1.1)])); c.clip()
                c.drawLinearGradient(gradient([(0, rgba(255, 236, 190, 0.10 + 0.06 * Double(sin(t * 0.8 + CGFloat(i) * 1.7)))), (1, rgba(255, 236, 190, 0))]), start: .zero, end: CGPoint(x: 0, y: H * 1.1), options: [])
                c.restoreGState()
            }
            c.restoreGState()
        }
        if fx.bokeh {
            var R = Rnd(77); let col = tpl == "night" || tpl == "stars" ? (170, 220, 255) : (255, 214, 150)
            c.saveGState(); c.setBlendMode(.plusLighter)
            for i in 0..<22 {
                let r = (30 + R.next() * 90) * u, x = R.next() * W + sin(t * 0.2 + CGFloat(i)) * 60 * u, sp = 6 + R.next() * 14
                let m = H + 2 * r, y = ((R.next() * H - t * sp * u).truncatingRemainder(dividingBy: m) + m).truncatingRemainder(dividingBy: m) - r
                fillRad(c, W, H, x, y, r, [(0, rgba(col.0, col.1, col.2, 0.14)), (0.7, rgba(col.0, col.1, col.2, 0.07)), (1, rgba(col.0, col.1, col.2, 0))], clipCircle: true)
            }
            c.restoreGState()
        }
        if fx.rain {
            var R = Rnd(9)
            c.setStrokeColor(rgba(210, 225, 255, 0.28).cgColor); c.setLineWidth(1.6 * u); c.setLineCap(.round)
            for _ in 0..<180 {
                let v = (900 + R.next() * 600) * u, x = R.next() * W * 1.2 - W * 0.1, y = (R.next() * H + t * v).truncatingRemainder(dividingBy: H + 60 * u) - 30 * u, len = (22 + R.next() * 26) * u
                c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x - len * 0.18, y: y + len)); c.strokePath()
            }
        }
        if fx.vignette {
            let R0 = max(W, H) * 0.75
            fillRad(c, W, H, W / 2, H / 2, R0, [(0, rgba(0, 0, 0, 0)), ((min(W, H) * 0.35) / R0, rgba(0, 0, 0, 0)), (1, rgba(0, 0, 0, 0.55))])
        }
    }
}
