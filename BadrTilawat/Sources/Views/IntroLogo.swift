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

/// Opening: the site's intro, frame for frame (front-page.php .intro + site.css): the same elements, delays, durations and easing.
struct IntroView: View {
    /// turned off from the dashboard while it plays (the site's newer word): it fades out as at its end, never cut
    var stop = false
    let done: () -> Void
    @EnvironmentObject var store: Store
    @EnvironmentObject var repo: Repo
    @State private var t0 = Date()
    @State private var out = false
    @State private var finished = false
    /// screenshot runs (CI): the opening held at this second, to compare its frames with the site's and Android's
    static let frozen: Double? = ProcessInfo.processInfo.environment["BZ_INTRO_T"].flatMap(Double.init)

    private func finish() {
        guard !finished else { return }; finished = true
        withAnimation(.easeOut(duration: 0.7)) { out = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { done() }
    }

    // CSS timing functions used by the site
    static let ease = Ease(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    static let easeInOut = Ease(x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    static let draw = Ease(x1: 0.6, y1: 0.05, x2: 0.3, y2: 1)
    static let pen = Ease(x1: 0.45, y1: 0.05, x2: 0.25, y2: 1)
    static let wave = Ease(x1: 0.3, y1: 1.4, x2: 0.5, y2: 1)
    static let write = Ease(x1: 0.4, y1: 0, x2: 0.2, y2: 1)

    var body: some View {
        let site = repo.data?.site
        let title = (site?.title).flatMap { $0.isEmpty ? nil : $0 } ?? tr("بدر التلاوات")
        let tagline = (site?.tagline).flatMap { $0.isEmpty ? nil : $0 } ?? "Badr Al Tilawat"
        let sub = site?.subtitle ?? ""
        TimelineView(.animation(paused: finished && out)) { tl in
            let t = IntroView.frozen ?? min(4, tl.date.timeIntervalSince(t0))
            // a CSS animation: [delay, duration], eased progress 0…1 («forwards»)
            let k = { (d: Double, du: Double, e: Ease) -> Double in e(min(1, max(0, (t - d) / du))) }
            GeometryReader { g in
                let side = min(340, g.size.width * 0.72)
                ZStack {
                    EllipticalGradient(colors: [hexC(0x13241F), hexC(0x070D0C)], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.99).ignoresSafeArea()   // CSS: ellipse, #13241f → #070d0c at 70%
                    StarPattern(tile: 110, alpha: 1, fade: true).opacity(k(0.3, 2.4, IntroView.ease) * 0.2).ignoresSafeArea()
                    VStack(spacing: 6) {
                        mark(k: k).frame(width: side, height: side)
                        let w = k(1.9, 1.2, IntroView.write)
                        Text(title).font(F.amiri(26)).foregroundStyle(hexC(0xECE4D2)).multilineTextAlignment(.center)
                            .mask(GeometryReader { m in Rectangle().frame(width: m.size.width * w).frame(maxWidth: .infinity, alignment: .trailing) }.environment(\.layoutDirection, .leftToRight))
                            .opacity(w).padding(.top, 18)
                        let en = k(2.5, 0.8, IntroView.ease)
                        Text(tagline.uppercased()).font(.system(size: 13, weight: .medium)).tracking(13 * 0.32).foregroundStyle(FRAME)
                            .opacity(en).offset(y: (1 - en) * 6).padding(.top, -2)
                        if !sub.isEmpty {
                            let sb = k(2.7, 0.8, IntroView.ease)
                            Text(sub).font(F.plex(15)).foregroundStyle(FRAME).opacity(sb).offset(y: (1 - sb) * 6)
                        }
                        if !store.name.isEmpty {
                            let gr = k(2.9, 0.8, IntroView.ease)
                            Text(tr("أهلًا بك يا {0}", store.name)).font(F.plex(15, .medium)).foregroundStyle(hexC(0xECE4D2, 0.8)).opacity(gr).offset(y: (1 - gr) * 6).padding(.top, 6)
                        }
                    }.padding(20)
                    VStack { Spacer()
                        Button(action: finish) { Text(tr("تخطَّ")).font(F.plex(14)).foregroundStyle(hexC(0xECE4D2, 0.6)).padding(.horizontal, 18).padding(.vertical, 8)
                            .overlay(Capsule().stroke(hexC(0xECE4D2, 0.15))) }.padding(.bottom, 26)
                    }
                }.frame(width: g.size.width, height: g.size.height)
            }
        }
        .opacity(out ? 0 : 1)
        .environment(\.colorScheme, .dark)
        .onAppear { t0 = Date(); if IntroView.frozen == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 3.9) { finish() } } }
        .onChange(of: stop) { if $0 { finish() } }
    }

    @ViewBuilder private func mark(k: @escaping (Double, Double, Ease) -> Double) -> some View {
        GeometryReader { g in
            let side = g.size.width
            ZStack(alignment: .topLeading) {
                // the star: four squares drawn with a 600-long dash (viewBox 200), then a soft gold glow
                Canvas(rendersAsynchronously: true) { ctx, size in
                    let u = size.width / 200
                    let glow = k(1.6, 1.4, IntroView.ease)
                    if glow > 0 { ctx.addFilter(.shadow(color: Color(red: 201 / 255, green: 164 / 255, blue: 92 / 255, opacity: 0.45 * glow), radius: 9)) }
                    func sq(_ x: CGFloat, _ w: CGFloat, rot: Bool) -> Path {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: x)); p.addLine(to: CGPoint(x: x + w, y: x)); p.addLine(to: CGPoint(x: x + w, y: x + w)); p.addLine(to: CGPoint(x: x, y: x + w)); p.closeSubpath()
                        var tr = CGAffineTransform(scaleX: u, y: u)
                        if rot { tr = CGAffineTransform(translationX: 100, y: 100).rotated(by: .pi / 4).translatedBy(x: -100, y: -100).concatenating(tr) }
                        return p.applying(tr)
                    }
                    let rects: [(CGFloat, CGFloat, Bool, Double, CGFloat, Double)] = [(44, 112, false, 0.15, 1.4, 1), (44, 112, true, 0.45, 1.4, 1), (32, 136, true, 0.8, 0.8, 0.55), (32, 136, false, 1.0, 0.8, 0.55)]
                    for r in rects {
                        let e = k(r.3, 1.5, IntroView.draw)
                        let shown = min(1, 600 * e / (4 * r.1))
                        if shown > 0 { ctx.stroke(sq(r.0, r.1, rot: r.2).trimmedPath(from: 0, to: shown), with: .color(FRAME.opacity(r.5)), lineWidth: r.4 * u) }
                    }
                }
                logo(k: k).frame(width: side * 0.65, height: side * 0.65).offset(x: side * 0.175, y: side * 0.175)
            }
        }
    }

    /// The logo (viewBox 1024), every piece with its own delay and duration as in the site's markup.
    private func logo(k: @escaping (Double, Double, Ease) -> Double) -> some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            let s = size.width / 1024
            ctx.scaleBy(x: s, y: s)
            ctx.clip(to: Path(ellipseIn: CGRect(x: 0, y: 0, width: 1024, height: 1024)))
            let ease = IntroView.ease
            // .lg-bg
            let bg = k(0.4, 0.8, ease)
            if bg > 0 {
                var c = ctx; c.opacity = bg
                c.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: 1024, height: 1024)),
                       with: .radialGradient(Gradient(stops: [.init(color: hexC(0x173029), location: 0), .init(color: hexC(0x0E1D19), location: 0.5), .init(color: hexC(0x070F0D), location: 1)]),
                                             center: CGPoint(x: 512, y: 512), startRadius: 0, endRadius: 720))
            }
            // .lg-dot
            for (i, p) in LogoPaths.dots.enumerated() {
                let a = k(1.9 + Double(i) * 0.05, 0.4, ease) * 0.55
                if a > 0 { let r = 2.4 + CGFloat(i % 3); ctx.fill(Path(ellipseIn: CGRect(x: p.0 - r, y: p.1 - r, width: r * 2, height: r * 2)), with: .color(hexC(0xE9DCC0, a))) }
            }
            // .lg-moon
            let moon = k(1.9, 0.8, ease) * 0.75
            if moon > 0 {
                var m = ctx
                var hole = Path(CGRect(x: 0, y: 0, width: 1024, height: 1024)); hole.addPath(Path(ellipseIn: CGRect(x: 796, y: 166, width: 52, height: 52)))
                m.clip(to: hole, style: FillStyle(eoFill: true))
                m.fill(Path(ellipseIn: CGRect(x: 780, y: 176, width: 56, height: 56)), with: .color(hexC(0xEFE3C6, moon)))
            }
            // the lines: drawn (stroke-dashoffset 1 → 0), then fading out at 2 s over 0.6 s
            let lineOut = 1 - k(2.0, 0.6, ease)
            let st = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
            func trace(_ c: GraphicsContext, _ p: Path, _ d: Double, _ du: Double, _ w: CGFloat) {
                let e = k(d, du, IntroView.pen)
                if e > 0 && lineOut > 0 { c.stroke(p.trimmedPath(from: 0, to: e), with: .color(STROKE.opacity(lineOut)), style: st(w)) }
            }
            var notInner = Path(CGRect(x: -200, y: -200, width: 1424, height: 1424)); notInner.addPath(LogoPaths.inner)
            var o = ctx; o.clip(to: notInner, style: FillStyle(eoFill: true)); trace(o, LogoPaths.outer, 0.35, 1.15, 5)
            var n = ctx; n.clip(to: LogoPaths.outer); trace(n, LogoPaths.inner, 0.45, 1.15, 5)
            // .lg-f crescent
            let cf = k(1.45, 0.8, ease)
            if cf > 0 {
                var f = ctx; f.clip(to: notInner, style: FillStyle(eoFill: true)); f.opacity = cf
                f.fill(LogoPaths.outer, with: .linearGradient(Gradient(stops: [.init(color: hexC(0xE9CF91), location: 0), .init(color: hexC(0xB78F48, 0.9), location: 0.5), .init(color: hexC(0xB78F48, 0), location: 1)]),
                                                              startPoint: CGPoint(x: 170, y: 0), endPoint: CGPoint(x: 840, y: 0)))
            }
            let gold2 = GraphicsContext.Shading.linearGradient(Gradient(colors: [hexC(0xF3DCA2), hexC(0xB48A42)]), startPoint: CGPoint(x: 0, y: 260), endPoint: CGPoint(x: 0, y: 580))
            let pf = k(1.45, 0.8, ease)
            for (i, p) in LogoPaths.minaret.enumerated() {
                trace(ctx, p, 0.6 + Double(i) * 0.06, 0.8, 3)
                if pf > 0 { var f = ctx; f.opacity = pf; f.fill(p, with: gold2) }
            }
            for (i, p) in LogoPaths.dome.enumerated() {
                trace(ctx, p, 0.75 + Double(i) * 0.06, 0.8, 3)
                if pf > 0 { var f = ctx; f.opacity = pf; f.fill(p, with: gold2) }
            }
            let gold = GraphicsContext.Shading.linearGradient(Gradient(stops: [.init(color: hexC(0xF6E2AD), location: 0), .init(color: hexC(0xD9B56D), location: 0.5), .init(color: hexC(0x9A7434), location: 1)]),
                                                              startPoint: .zero, endPoint: CGPoint(x: 1024, y: 1024))
            for (i, p) in LogoPaths.b.enumerated() {
                trace(ctx, p, 0.55 + Double(i) * 0.3, 1.05, 4)
                let bf = k([1.50, 1.62, 1.74][i], 0.8, ease)
                if bf > 0 { var f = ctx; f.opacity = bf; f.fill(p, with: gold) }
            }
            // .lg-wave: scaleY 0 → 1 from its centre
            let wv = GraphicsContext.Shading.linearGradient(Gradient(colors: [hexC(0xD9B56D, 0.15), hexC(0xE9CF91)]), startPoint: CGPoint(x: 240, y: 0), endPoint: CGPoint(x: 324, y: 0))
            for (i, w) in LogoPaths.wave.enumerated() {
                let gw = k(1.75 + Double(i) * 0.08, 0.6, IntroView.wave)
                let hh = w.2 * gw, cy = w.1 + w.2 / 2
                if hh > 0.3 { ctx.fill(Path(roundedRect: CGRect(x: w.0, y: cy - hh / 2, width: 8, height: hh), cornerRadius: min(4, hh / 2)), with: wv) }
            }
            // .lg-sheen: a 1024-wide band moving from x −1024 to +1024
            let sh = k(2.3, 0.8, IntroView.easeInOut)
            if sh > 0 && sh < 1 {
                let x = -1024 + 2048 * sh
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1024, height: 1024)),
                         with: .linearGradient(Gradient(stops: [.init(color: hexC(0xFFF3D0, 0), location: 0), .init(color: hexC(0xFFF3D0, 0.18), location: 0.5), .init(color: hexC(0xFFF3D0, 0), location: 1)]),
                                               startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + 1024, y: 1024)))
            }
        }
    }
}
