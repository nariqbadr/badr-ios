import Foundation
import CoreText
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let ayah = try! String(contentsOfFile: args[1], encoding: .utf8)
func has(_ f: CTFont, _ u: UnicodeScalar) -> Bool {
    var ch = Array(String(u).utf16); var g = [CGGlyph](repeating: 0, count: ch.count)
    return CTFontGetGlyphsForCharacters(f, &ch, &g, ch.count) && g.allSatisfy { $0 != 0 }
}
func plain(_ t: String, _ f: CTFont) -> String {
    let map: [UInt32: UInt32] = [0x06E1: 0x0652, 0x08F0: 0x064B, 0x08F1: 0x064C, 0x08F2: 0x064D, 0x0671: 0x0627, 0x06E5: 0, 0x06E6: 0]
    var out = String.UnicodeScalarView()
    for u in t.unicodeScalars {
        if u.value == 0x20 || has(f, u) { out.append(u); continue }
        if let m = map[u.value], m != 0, let mu = UnicodeScalar(m), has(f, mu) { out.append(mu); continue }
        let v = u.value
        if (0x0610...0x061A).contains(v) || (0x064B...0x065F).contains(v) || v == 0x0670 || (0x06D6...0x06ED).contains(v) || (0x08D3...0x08FF).contains(v) { continue }
        out.append(u)
    }
    return String(out).split(whereSeparator: { $0 == " " }).joined(separator: " ")
}
func tokens(_ t: String) -> [String] {
    var out: [String] = []
    for w in t.split(separator: " ").map(String.init) {
        let mark = w.unicodeScalars.allSatisfy { (0x06D6...0x06ED).contains($0.value) }
        if mark, !out.isEmpty { out[out.count - 1] += " " + w } else { out.append(w) }
    }
    return out
}
func line(_ s: String, _ f: CTFont) -> CTLine {
    CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: f, kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1)]))
}
let W = 1080, H = 1700
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(red: 0.1, green: 0.12, blue: 0.15, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
var yTop = 40.0
for p in args.dropFirst(2) {
    guard let prov = CGDataProvider(url: URL(fileURLWithPath: p) as CFURL), let cg = CGFont(prov) else { print("no font", p); continue }
    let fs = 44.0
    let f = CTFontCreateWithGraphicsFont(cg, fs, nil, nil)
    let name = (cg.postScriptName as String?) ?? p
    for (lab, txt) in [("orig", ayah), ("plain", plain(ayah, f))] {
        let toks = tokens(txt)
        let space = Double(CTLineGetTypographicBounds(line(" ", f), nil, nil, nil))
        var slack = 0.0; var x = Double(W) - 20
        let y = Double(H) - yTop - fs
        for tk in toks {
            let l = line(tk, f); let w = Double(CTLineGetTypographicBounds(l, nil, nil, nil)); let ink = CTLineGetImageBounds(l, ctx)
            slack += w - Double(ink.width)
            if x - w < 20 { break }
            ctx.textPosition = CGPoint(x: x - w, y: y); CTLineDraw(l, ctx)
            x -= w + space
        }
        let lab2 = line("\(lab) \(name) space=\(Int(space)) slack/word=\(Int(slack / Double(toks.count)))", CTFontCreateWithName("Helvetica" as CFString, 16, nil))
        ctx.textPosition = CGPoint(x: 20, y: y + fs * 0.9); CTLineDraw(lab2, ctx)
        print(lab, name, "space", space, "slack/word", slack / Double(toks.count))
        // the number in this font
        yTop += fs * 2.0
    }
    yTop += 10
}
let img = ctx.makeImage()!
let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "out/probe.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
