import SwiftUI

// The opening, drawn exactly like the Android app's (and the site's): a star frame draws itself, the logo is traced
// line by line, filled with gold, the sound wave rises, the stars come out, a sheen passes, then the name writes in.

/// A small SVG path reader (M L H V C A Z, absolute and relative) — enough for the logo's paths.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var p = Path()
        var toks: [String] = []
        var cur = ""
        func flush() { if !cur.isEmpty { toks.append(cur); cur = "" } }
        for ch in d {
            if ch.isLetter && ch != "e" { flush(); toks.append(String(ch)) }
            else if ch == "," || ch == " " { flush() }
            else if ch == "-" && !cur.isEmpty && cur.last != "e" { flush(); cur = "-" }
            else { cur.append(ch) }
        }
        flush()
        var i = 0, cmd = "M"
        var pt = CGPoint.zero, start = CGPoint.zero
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(toks[i]) ?? 0) }
        while i < toks.count {
            if let c = toks[i].first, c.isLetter { cmd = toks[i]; i += 1; if cmd == "Z" || cmd == "z" { p.closeSubpath(); pt = start; continue } }
            let rel = cmd == cmd.lowercased()
            switch cmd.uppercased() {
            case "M":
                let x = num(), y = num(); pt = rel ? CGPoint(x: pt.x + x, y: pt.y + y) : CGPoint(x: x, y: y); start = pt; p.move(to: pt)
                cmd = rel ? "l" : "L"
            case "L": let x = num(), y = num(); pt = rel ? CGPoint(x: pt.x + x, y: pt.y + y) : CGPoint(x: x, y: y); p.addLine(to: pt)
            case "H": let x = num(); pt = CGPoint(x: rel ? pt.x + x : x, y: pt.y); p.addLine(to: pt)
            case "V": let y = num(); pt = CGPoint(x: pt.x, y: rel ? pt.y + y : y); p.addLine(to: pt)
            case "C":
                var v = (0..<6).map { _ in num() }
                if rel { for k in stride(from: 0, to: 6, by: 2) { v[k] += pt.x; v[k + 1] += pt.y } }
                p.addCurve(to: CGPoint(x: v[4], y: v[5]), control1: CGPoint(x: v[0], y: v[1]), control2: CGPoint(x: v[2], y: v[3]))
                pt = CGPoint(x: v[4], y: v[5])
            case "A":
                let rx = num(), ry = num(); _ = num(); let large = num() != 0, sweep = num() != 0
                var x = num(), y = num(); if rel { x += pt.x; y += pt.y }
                arc(&p, from: pt, to: CGPoint(x: x, y: y), r: max(rx, ry), large: large, sweep: sweep)
                pt = CGPoint(x: x, y: y)
            default: i += 1
            }
        }
        return p
    }

    /// SVG's endpoint arc (circular, no rotation), drawn as short lines.
    private static func arc(_ p: inout Path, from a: CGPoint, to b: CGPoint, r r0: CGFloat, large: Bool, sweep: Bool) {
        let dx = (a.x - b.x) / 2, dy = (a.y - b.y) / 2
        var r = r0; let d2 = dx * dx + dy * dy
        if d2 > r * r { r = sqrt(d2) }
        let s: CGFloat = (large == sweep ? -1 : 1) * sqrt(max(0, (r * r - d2) / max(d2, 1e-9)))
        let cxp = s * dy, cyp = -s * dx
        let cx = cxp + (a.x + b.x) / 2, cy = cyp + (a.y + b.y) / 2
        let t1 = atan2(a.y - cy, a.x - cx)
        var dt = atan2(b.y - cy, b.x - cx) - t1
        if sweep && dt < 0 { dt += 2 * .pi } else if !sweep && dt > 0 { dt -= 2 * .pi }
        let n = max(8, Int(abs(dt) / (.pi / 24)))
        for k in 1...n { let t = t1 + dt * CGFloat(k) / CGFloat(n); p.addLine(to: CGPoint(x: cx + r * cos(t), y: cy + r * sin(t))) }
    }
}

/// CSS-style cubic-bezier easing.
struct Ease {
    let x1, y1, x2, y2: Double
    static let standard = Ease(x1: 0.4, y1: 0, x2: 0.2, y2: 1)        // Android's FastOutSlowIn
    func callAsFunction(_ t: Double) -> Double {
        if t <= 0 { return 0 }; if t >= 1 { return 1 }
        func bx(_ u: Double) -> Double { 3 * u * (1 - u) * (1 - u) * x1 + 3 * u * u * (1 - u) * x2 + u * u * u }
        func by(_ u: Double) -> Double { 3 * u * (1 - u) * (1 - u) * y1 + 3 * u * u * (1 - u) * y2 + u * u * u }
        var lo = 0.0, hi = 1.0, u = t
        for _ in 0..<24 { u = (lo + hi) / 2; if bx(u) < t { lo = u } else { hi = u } }
        return by(u)
    }
}

private struct LogoPaths {
    static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, from a0: CGFloat = 0) -> Path {
        var p = Path(); let n = 120
        for k in 0...n { let t = a0 + 2 * .pi * CGFloat(k) / CGFloat(n); let q = CGPoint(x: cx + r * cos(t), y: cy + r * sin(t)); if k == 0 { p.move(to: q) } else { p.addLine(to: q) } }
        p.closeSubpath(); return p
    }
    static func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x + r, y: y))
        p.addArc(tangent1End: CGPoint(x: x + w, y: y), tangent2End: CGPoint(x: x + w, y: y + h), radius: r)
        p.addArc(tangent1End: CGPoint(x: x + w, y: y + h), tangent2End: CGPoint(x: x, y: y + h), radius: r)
        p.addArc(tangent1End: CGPoint(x: x, y: y + h), tangent2End: CGPoint(x: x, y: y), radius: r)
        p.addArc(tangent1End: CGPoint(x: x, y: y), tangent2End: CGPoint(x: x + w, y: y), radius: r)
        p.closeSubpath(); return p
    }
    static let outer = circle(505, 500, 335, from: -.pi / 2)
    static let inner = circle(540, 486, 330, from: -.pi / 2)
    static let minaret: [Path] = [SVGPath.parse("M357 268 a6 6 0 1 0 0.1 0z"), SVGPath.parse("M352 286 h10 v14 h-10z"), SVGPath.parse("M343 330 L357 296 L371 330 Z"),
                                  rr(341, 330, 32, 56, 3), rr(333, 386, 48, 10, 4), SVGPath.parse("M339 396 h36 l-3 170 h-30 z")]
    static let dome: [Path] = [SVGPath.parse("M392 566 C392 500, 430 470, 458 462 C486 470, 524 500, 524 566 Z"), rr(452, 430, 12, 34, 5),
                               SVGPath.parse("M458 404 a12 12 0 1 0 8 21 a9 9 0 1 1 -8 -21z"), rr(384, 564, 148, 12, 4)]
    static let b: [Path] = [
        SVGPath.parse("M470 232 C575 192, 708 222, 712 318 C716 396, 642 444, 548 456 L552 432 C622 418, 662 380, 660 324 C657 262, 580 238, 480 258 Z"),
        SVGPath.parse("M520 452 C650 440, 768 498, 764 606 C760 710, 640 772, 470 764 C420 762, 384 752, 352 738 C398 746, 432 748, 468 746 C606 748, 702 690, 704 606 C706 530, 630 486, 528 480 Z"),
        SVGPath.parse("M262 776 C400 744, 520 690, 620 600 C580 690, 470 760, 300 792 C286 795, 270 790, 262 776 Z")]
    static let wave: [(CGFloat, CGFloat, CGFloat)] = [(240, 505, 30), (259, 489, 62), (278, 468, 104), (297, 485, 70), (316, 454, 132)]
    static let dots: [(CGFloat, CGFloat)] = [(170, 180), (860, 150), (790, 290), (120, 420), (900, 560), (230, 860), (820, 840), (640, 120), (340, 120), (930, 380)]
}

private func hexC(_ v: UInt32, _ a: Double = 1) -> Color { Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255, opacity: a) }
private let STROKE = hexC(0xE3C88D), FRAME = hexC(0xC9A45C)
private let BG = [hexC(0x173029), hexC(0x0E1D19), hexC(0x070F0D)]

/// Opening: the same timeline as the Android app (seconds from the start).
struct IntroView: View {
    let done: () -> Void
    @EnvironmentObject var store: Store
    @State private var t0 = Date()
    @State private var out = false
    @State private var finished = false

    private func finish() {
        guard !finished else { return }; finished = true
        withAnimation(.easeOut(duration: 0.6)) { out = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { done() }
    }

    var body: some View {
        TimelineView(.animation(paused: finished && out)) { tl in
            let t = min(3.6, tl.date.timeIntervalSince(t0))
            let seg = { (a: Double, b: Double, e: Ease) -> Double in e(min(1, max(0, (t - a) / (b - a)))) }
            let fs = Ease.standard
            GeometryReader { g in
                ZStack {
                    RadialGradient(colors: BG, center: .center, startRadius: 0, endRadius: max(g.size.width, g.size.height) * 0.9).ignoresSafeArea()
                    StarPattern(tile: 110, alpha: 1, fade: true).opacity(seg(0.2, 2.2, fs) * 0.22).ignoresSafeArea()
                    VStack(spacing: 0) {
                        mark(t: t, seg: seg).frame(width: 300, height: 300)
                        Spacer().frame(height: 18)
                        let w = seg(2.0, 2.9, Ease(x1: 0.4, y1: 0, x2: 0.2, y2: 1))
                        Text(tr("بدر التلاوات")).font(F.amiri(40))
                            .foregroundStyle(LinearGradient(colors: [hexC(0xF6E2AD), hexC(0xD9B56D), hexC(0xB48A42)], startPoint: .top, endPoint: .bottom))
                            .mask(GeometryReader { m in Rectangle().frame(width: m.size.width * w).frame(maxWidth: .infinity, alignment: .trailing) }.environment(\.layoutDirection, .leftToRight))
                            .opacity(w > 0 ? 1 : 0)
                        let s = seg(2.6, 3.2, fs)
                        Text("BADR AL TILAWAT").font(.system(size: 13, weight: .medium)).tracking(4).foregroundStyle(FRAME)
                            .padding(.top, 2).opacity(s).offset(y: (1 - s) * 7)
                        if !store.name.isEmpty {
                            let gr = seg(2.9, 3.4, fs)
                            Text(tr("أهلًا بك يا {0}", store.name)).font(F.plex(15, .medium)).foregroundStyle(hexC(0xECE4D2, 0.8))
                                .padding(.top, 12).opacity(gr).offset(y: (1 - gr) * 6)
                        }
                    }
                    VStack { Spacer()
                        Button(action: finish) { Text(tr("تخطَّ")).font(F.plex(14)).foregroundStyle(hexC(0xECE4D2, 0.6)).padding(.horizontal, 18).padding(.vertical, 8)
                            .overlay(Capsule().stroke(hexC(0xECE4D2, 0.15))) }.padding(.bottom, 26)
                    }
                }.frame(width: g.size.width, height: g.size.height)
            }
        }
        .opacity(out ? 0 : 1).scaleEffect(out ? 1.06 : 1)
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle()).onTapGesture(perform: finish)
        .onAppear { t0 = Date(); DispatchQueue.main.asyncAfter(deadline: .now() + 3.85) { finish() } }
    }

    @ViewBuilder private func mark(t: Double, seg: @escaping (Double, Double, Ease) -> Double) -> some View {
        let fs = Ease.standard
        ZStack {
            // star frame (a square and a diamond) and a faint ring, drawn first
            Canvas { ctx, size in
                let ctr = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) * 0.49
                let glow = seg(1.7, 2.6, fs)
                if glow > 0 {
                    let gr = r * 1.15
                    ctx.opacity = glow
                    ctx.fill(Path(ellipseIn: CGRect(x: ctr.x - gr, y: ctr.y - gr, width: gr * 2, height: gr * 2)),
                             with: .radialGradient(Gradient(colors: [FRAME.opacity(0.33), .clear]), center: ctr, startRadius: 0, endRadius: gr))
                    ctx.opacity = 1
                }
                let a = r * 0.72
                var sq1 = Path(); sq1.addRect(CGRect(x: ctr.x - a, y: ctr.y - a, width: a * 2, height: a * 2))
                let d = r * 1.018
                var sq2 = Path(); sq2.move(to: CGPoint(x: ctr.x, y: ctr.y - d)); sq2.addLine(to: CGPoint(x: ctr.x + d, y: ctr.y)); sq2.addLine(to: CGPoint(x: ctr.x, y: ctr.y + d)); sq2.addLine(to: CGPoint(x: ctr.x - d, y: ctr.y)); sq2.closeSubpath()
                let fe = Ease(x1: 0.6, y1: 0.05, x2: 0.3, y2: 1)
                let st = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                ctx.stroke(sq1.trimmedPath(from: 0, to: seg(0.05, 1.3, fe)), with: .color(FRAME), style: st)
                ctx.stroke(sq2.trimmedPath(from: 0, to: seg(0.3, 1.55, fe)), with: .color(FRAME), style: st)
                let sm = r * 0.86
                ctx.stroke(LogoPaths.circle(ctr.x, ctr.y, sm, from: -.pi / 2).trimmedPath(from: 0, to: seg(0.7, 1.8, fs)), with: .color(FRAME.opacity(0.53)), lineWidth: 1)
            }
            // the logo, inside the star
            Canvas { ctx, size in
                let k = size.width / 1024
                let full = Path(ellipseIn: CGRect(origin: .zero, size: size))
                ctx.clip(to: full)
                ctx.opacity = seg(0.4, 1.2, fs)
                ctx.fill(full, with: .radialGradient(Gradient(colors: BG), center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0, endRadius: size.width * 0.7))
                ctx.opacity = 1
                var c = ctx
                c.scaleBy(x: k, y: k)
                let fill = seg(1.45, 2.25, fs), line = 1 - seg(2.0, 2.6, fs)
                let tw = seg(1.9, 2.7, fs)
                let stroke = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
                // stars and the small moon
                for (i, p) in LogoPaths.dots.enumerated() {
                    let r = 2.4 + CGFloat(i % 3)
                    c.fill(Path(ellipseIn: CGRect(x: p.0 - r, y: p.1 - r, width: r * 2, height: r * 2)), with: .color(hexC(0xE9DCC0, 0.55 * seg(1.9 + Double(i) * 0.05, 2.3 + Double(i) * 0.05, fs))))
                }
                if tw > 0 {
                    var m = c
                    m.clip(to: Path(ellipseIn: CGRect(x: 780, y: 176, width: 56, height: 56)))
                    var mp = Path(ellipseIn: CGRect(x: 780, y: 176, width: 56, height: 56)); mp.addPath(Path(ellipseIn: CGRect(x: 796, y: 166, width: 52, height: 52)))
                    m.fill(mp, with: .color(hexC(0xEFE3C6, 0.75 * tw)), style: FillStyle(eoFill: true))
                }
                // crescent: the outer circle's line outside the inner one, the inner one's line inside the outer one
                let cp = seg(0.35, 1.5, fs)
                if line > 0 && cp > 0 {
                    var o = c
                    var notInner = Path(CGRect(x: -100, y: -100, width: 1224, height: 1224)); notInner.addPath(LogoPaths.inner)
                    o.clip(to: notInner, style: FillStyle(eoFill: true))
                    o.stroke(LogoPaths.outer.trimmedPath(from: 0, to: cp), with: .color(STROKE.opacity(line)), style: stroke(5))
                    var n = c
                    n.clip(to: LogoPaths.outer)
                    n.stroke(LogoPaths.inner.trimmedPath(from: 0, to: cp), with: .color(STROKE.opacity(line)), style: stroke(5))
                }
                if fill > 0 {
                    var f = c
                    f.clip(to: LogoPaths.outer)
                    var cres = LogoPaths.outer; cres.addPath(LogoPaths.inner)
                    f.opacity = fill
                    f.fill(cres, with: .linearGradient(Gradient(stops: [.init(color: hexC(0xE9CF91), location: 0), .init(color: hexC(0xB78F48, 0.9), location: 0.5), .init(color: hexC(0xB78F48, 0), location: 1)]),
                                                     startPoint: CGPoint(x: 170, y: 0), endPoint: CGPoint(x: 840, y: 0)), style: FillStyle(eoFill: true))
                }
                // minaret and dome
                let gold2 = GraphicsContext.Shading.linearGradient(Gradient(colors: [hexC(0xF3DCA2), hexC(0xB48A42)]), startPoint: CGPoint(x: 0, y: 260), endPoint: CGPoint(x: 0, y: 580))
                for (i, p) in LogoPaths.minaret.enumerated() {
                    let d = Double(i) * 0.06
                    if line > 0 { c.stroke(p.trimmedPath(from: 0, to: seg(0.6 + d, 1.4 + d, fs)), with: .color(STROKE.opacity(line)), style: stroke(3)) }
                    if fill > 0 { var f = c; f.opacity = fill; f.fill(p, with: gold2) }
                }
                for (i, p) in LogoPaths.dome.enumerated() {
                    let d = Double(i) * 0.06
                    if line > 0 { c.stroke(p.trimmedPath(from: 0, to: seg(0.75 + d, 1.55 + d, fs)), with: .color(STROKE.opacity(line)), style: stroke(3)) }
                    if fill > 0 { var f = c; f.opacity = fill; f.fill(p, with: gold2) }
                }
                // the B ribbons, written like a pen stroke
                let gold = GraphicsContext.Shading.linearGradient(Gradient(colors: [hexC(0xF6E2AD), hexC(0xD9B56D), hexC(0x9A7434)]), startPoint: .zero, endPoint: CGPoint(x: 1024, y: 1024))
                let pen = Ease(x1: 0.45, y1: 0.05, x2: 0.25, y2: 1)
                for (i, p) in LogoPaths.b.enumerated() {
                    let d = Double(i) * 0.3
                    if line > 0 { c.stroke(p.trimmedPath(from: 0, to: seg(0.55 + d, 1.6 + d, pen)), with: .color(STROKE.opacity(line)), style: stroke(4)) }
                    let bf = seg(1.5 + Double(i) * 0.12, 2.3 + Double(i) * 0.12, fs)
                    if bf > 0 { var f = c; f.opacity = bf; f.fill(p, with: gold) }
                }
                // the sound wave rising
                let wv = GraphicsContext.Shading.linearGradient(Gradient(colors: [hexC(0xD9B56D, 0.15), hexC(0xE9CF91)]), startPoint: CGPoint(x: 240, y: 0), endPoint: CGPoint(x: 324, y: 0))
                for (i, w) in LogoPaths.wave.enumerated() {
                    let gw = seg(1.75 + Double(i) * 0.08, 2.35 + Double(i) * 0.08, Ease(x1: 0.3, y1: 1.4, x2: 0.5, y2: 1))
                    let hh = w.2 * gw; let cy = w.1 + w.2 / 2
                    if hh > 0.5 { c.fill(Path(roundedRect: CGRect(x: w.0, y: cy - hh / 2, width: 8, height: hh), cornerRadius: min(4, hh / 2)), with: wv) }
                }
                // a sheen sweeping across once the gold is in
                let sh = seg(2.3, 3.1, fs)
                if sh > 0.01 && sh < 0.99 {
                    ctx.fill(full, with: .linearGradient(Gradient(colors: [.clear, hexC(0xFFF3D0, 0.4), .clear]),
                                                         startPoint: CGPoint(x: size.width * (sh * 2 - 1), y: 0), endPoint: CGPoint(x: size.width * (sh * 2 - 0.4), y: size.height)))
                }
            }
            .frame(width: 196, height: 196)
        }
    }
}
