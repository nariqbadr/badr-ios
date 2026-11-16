import SwiftUI
import ImageIO

// MARK: images (memory + disk cache)
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let mem = NSCache<NSURL, UIImage>()
    private let dir: URL = { let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("img"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }()
    init() { mem.totalCostLimit = 120 * 1024 * 1024 }
    /// A name that stays the same from one launch to the next (Swift's hashValue changes every launch).
    private func file(_ u: URL) -> URL {
        var h: UInt64 = 1469598103934665603
        for b in u.absoluteString.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return dir.appendingPathComponent(String(h, radix: 36))
    }
    /// Only what is already decoded in memory: instant, safe to call while drawing.
    func cached(_ u: URL) -> UIImage? { mem.object(forKey: u as NSURL) }
    /// From memory, the disk or the network; the file is read and decoded off the main thread, at most 1200 px wide.
    func load(_ u: URL) async -> UIImage? {
        if let i = cached(u) { return i }
        let f = file(u)
        if let i = await Task.detached(priority: .userInitiated, operation: { ImageCache.decode(try? Data(contentsOf: f)) }).value {
            mem.setObject(i, forKey: u as NSURL, cost: i.cost); return i
        }
        let session = await Repo.shared.session
        guard let (d, _) = try? await session.data(from: u) else { return nil }
        let i = await Task.detached(priority: .userInitiated, operation: { () -> UIImage? in try? d.write(to: f); return ImageCache.decode(d) }).value
        if let i { mem.setObject(i, forKey: u as NSURL, cost: i.cost) }
        return i
    }
    private static func decode(_ d: Data?) -> UIImage? {
        guard let d, let src = CGImageSourceCreateWithData(d as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 1200, kCGImageSourceShouldCacheImmediately: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return UIImage(data: d)?.preparingForDisplay() }
        return UIImage(cgImage: cg)
    }
}
private extension UIImage { var cost: Int { Int(size.width * size.height * scale * scale * 4) } }

struct RemoteImage: View {
    let raw: String?
    var mode: ContentMode = .fill
    @State private var img: UIImage?
    init(raw: String?, mode: ContentMode = .fill) {
        self.raw = raw; self.mode = mode
        // already in memory: shown in the very first frame (no grey flash while scrolling)
        _img = State(initialValue: Repo.media(raw).flatMap { ImageCache.shared.cached($0) })
    }
    @Environment(\.pal) private var c
    var body: some View {
        // takes exactly the space it is given (a «fill» picture never pushes its container wider)
        Color.clear.overlay {
            if let img { Image(uiImage: img).resizable().aspectRatio(contentMode: mode).transition(.opacity) }
            else { ZStack { Rectangle().fill(c.surface2); Image("Logo").resizable().scaledToFit().padding(12).opacity(0.25) } }
        }
        .clipped()
        .task(id: raw) {
            guard let u = Repo.media(raw) else { img = nil; return }
            if let i = ImageCache.shared.cached(u) { img = i; return }
            let i = await ImageCache.shared.load(u)
            if img == nil { withAnimation(.easeOut(duration: 0.25)) { img = i } } else { img = i }
        }
    }
}

// MARK: the site's visual language (same as the Android app): the mihrab arch, the star lattice, gold leaf on ink

/// An icon from the site's own set when it has one, else an SF Symbol.
struct Ico: View {
    let name: String; var size: CGFloat = 20; var color: Color? = nil
    /// Apple's names for the icons the site's set has too
    static let alias: [String: String] = ["play.fill": "play", "pause.fill": "pause", "checkmark": "check", "xmark": "close", "square.and.arrow.up": "share",
        "arrow.down.circle": "download", "square.and.arrow.down": "download", "magnifyingglass": "search", "speaker.slash": "mute", "speaker.wave.2": "volume",
        "speaker.wave.2.fill": "volume", "mappin": "pin", "paperplane": "send", "music.note.list": "playlist", "text.append": "queue", "text.line.first.and.arrowtriangle.forward": "next",
        "person.crop.circle": "user", "person": "user", "photo": "image", "repeat.1": "repeat", "ellipsis": "dots", "chevron.left": "chev-l", "chevron.right": "chev-r",
        "chevron.down": "chev-d", "arrow.up": "up", "arrow.counterclockwise": "refresh", "arrow.clockwise": "refresh", "doc.on.doc": "copy", "bell.fill": "bell",
        "heart.fill": "heart-f", "gearshape": "gear", "bubble.left": "chat", "backward.end.fill": "prev", "forward.end.fill": "next", "film.fill": "film",
        "book.fill": "book", "mic.fill": "mic", "link.circle": "link", "envelope": "mail", "calendar.badge.clock": "calendar", "moon.fill": "moon", "sun.max": "sun",
        "cloud.rain": "rain", "water.waves": "wave", "arrow.up.forward.app": "external", "plus.circle": "plus", "trash.fill": "trash", "flag.fill": "flag", "bookmark.fill": "bookmark"]
    var body: some View {
        // left-to-right languages: the back arrow points the other way
        let name = L.rtl ? self.name : self.name == "arrow.right" ? "arrow.left" : self.name == "arrow.left" ? "arrow.right" : self.name
        let n = SiteIcons.data[name] != nil ? name : (Ico.alias[name] ?? name)
        if SiteIcons.data[n] != nil { SiteIcon(name: n, size: size, color: color) }
        else if let color { Image(systemName: name).font(.system(size: size * 0.82)).foregroundStyle(color).frame(width: size, height: size) }
        else { Image(systemName: name).font(.system(size: size * 0.82)).frame(width: size, height: size) }
    }
}

/// The mihrab arch (site.css --arch), scaled to any box.
struct ArchShape: Shape {
    var closed = true
    func path(in r: CGRect) -> Path {
        var p = Path(); let w = r.width, h = r.height, x = r.minX, y = r.minY
        p.move(to: CGPoint(x: x, y: y + h)); p.addLine(to: CGPoint(x: x, y: y + 0.385 * h))
        p.addCurve(to: CGPoint(x: x + 0.5 * w, y: y), control1: CGPoint(x: x, y: y + 0.19 * h), control2: CGPoint(x: x + 0.17 * w, y: y + 0.085 * h))
        p.addCurve(to: CGPoint(x: x + w, y: y + 0.385 * h), control1: CGPoint(x: x + 0.83 * w, y: y + 0.085 * h), control2: CGPoint(x: x + w, y: y + 0.19 * h))
        p.addLine(to: CGPoint(x: x + w, y: y + h)); if closed { p.closeSubpath() }
        return p
    }
}
func star8(_ c: CGPoint, _ r: CGFloat) -> Path {
    var p = Path()
    for k in 0..<2 {
        let a0 = Double.pi / 4 * Double(k)
        for i in 0...4 { let a = a0 + .pi / 2 * Double(i) + .pi / 4; let q = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a))); if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
        p.closeSubpath()
    }
    return p
}
func sparkle(_ c: CGPoint, _ r: CGFloat, _ inner: CGFloat = 0.3) -> Path {
    var p = Path()
    for i in 0..<8 { let a = Double.pi / 4 * Double(i) - .pi / 2; let rr = i % 2 == 0 ? r : r * inner; let q = CGPoint(x: c.x + rr * CGFloat(cos(a)), y: c.y + rr * CGFloat(sin(a))); if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
    p.closeSubpath(); return p
}
extension Palette {
    /// the site's gold leaf: light → gold → a little darker
    var goldBrush: LinearGradient { LinearGradient(colors: [gold2, gold, gold.mix(.black, 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing) }
    var goldBrushV: LinearGradient { LinearGradient(colors: [gold2, gold, gold.mix(.black, 0.18)], startPoint: .top, endPoint: .bottom) }
    /// deep end of the page gradient
    var deep: Color { dark ? bg.mix(.black, 0.38) : bg2 }
}
extension Color {
    func mix(_ o: Color, _ t: Double) -> Color {
        let a = UIColor(self), b = UIColor(o); var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1); b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(.sRGB, red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, opacity: a1 + (a2 - a1) * t)
    }
}

/// The site's star lattice (--pattern): an eight-point sparkle with two squares, tiled.
struct StarPattern: View {
    @Environment(\.pal) private var c
    var tile: CGFloat = 96
    var alpha: Double = 1
    var fade = false
    var body: some View {
        Canvas { ctx, size in
            let k = tile / 96
            var cell = Path()
            cell.move(to: CGPoint(x: 48 * k, y: 8 * k)); for (x, y) in [(58, 38), (88, 48), (58, 58), (48, 88), (38, 58), (8, 48), (38, 38)] { cell.addLine(to: CGPoint(x: CGFloat(x) * k, y: CGFloat(y) * k)) }; cell.closeSubpath()
            cell.addRect(CGRect(x: 20 * k, y: 20 * k, width: 56 * k, height: 56 * k))
            cell.addPath(Path(CGRect(x: 20 * k, y: 20 * k, width: 56 * k, height: 56 * k)).applying(CGAffineTransform(translationX: 48 * k, y: 48 * k).rotated(by: .pi / 4).translatedBy(x: -48 * k, y: -48 * k)))
            let col = c.pattern.opacity(alpha)
            var y: CGFloat = 0
            while y < size.height { var x: CGFloat = 0; while x < size.width { ctx.stroke(cell.applying(CGAffineTransform(translationX: x, y: y)), with: .color(col), lineWidth: max(1, k)); x += tile }; y += tile }
        }
        .mask { if fade { GeometryReader { g in RadialGradient(colors: [.black, .clear], center: UnitPoint(x: 0.5, y: 0.25), startRadius: 0, endRadius: max(g.size.width, g.size.height) * 0.75) } } else { Color.black } }
        .allowsHitTesting(false)
    }
}

/// App backdrop: ink gradient, a soft gold glow, the star lattice; twinkling stars on «ليل ونجوم».
struct Backdrop: View {
    @Environment(\.pal) private var c
    var body: some View {
        GeometryReader { g in
            ZStack {
                if c.stars { LinearGradient(colors: [Color(hex: 0xFF05061A), Color(hex: 0xFF0C0F30), Color(hex: 0xFF1D1838)], startPoint: .top, endPoint: .bottom) }
                else if ["dawn", "maroon", "silver", "marble", "nightblue", "sky"].contains(c.key) { LinearGradient(colors: c.grad, startPoint: .top, endPoint: .bottom) }
                else { LinearGradient(colors: [c.bg2, c.bg, c.deep], startPoint: .top, endPoint: .bottom) }
                RadialGradient(colors: [c.gold.opacity(c.dark ? 0.10 : 0.08), .clear], center: UnitPoint(x: 0.78, y: 0), startRadius: 0, endRadius: g.size.width * 1.1)
                StarPattern(tile: 110, alpha: 0.55, fade: true)
                if c.stars { StarField() }
            }
        }.ignoresSafeArea()
    }
}
private struct StarField: View {
    @State private var stars = (0..<70).map { _ in (CGFloat.random(in: 0...1), CGFloat.random(in: 0...1), CGFloat.random(in: 0...1)) }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate / 4.2
                for (i, s) in stars.enumerated() {
                    let ph = ((t + Double(s.2)) * Double(1 + i % 3)).truncatingRemainder(dividingBy: 1)
                    let a = 0.35 + 0.65 * (ph > 0.5 ? 1 - ph : ph) * 2
                    let r = 0.6 + s.2 * 1.5
                    ctx.fill(Path(ellipseIn: CGRect(x: s.0 * size.width - r, y: s.1 * size.height * 0.9 - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(a * (0.4 + Double(s.2) * 0.6))))
                }
            }
        }
    }
}

/// Gold hairline that fades at both ends, with a small star in the middle.
struct Ornament: View {
    var width: CGFloat = 160
    @Environment(\.pal) private var c
    var body: some View {
        Canvas { ctx, size in
            let y = size.height / 2, mid = size.width / 2
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: mid - 12, y: y)) }, with: .linearGradient(Gradient(colors: [.clear, c.gold.opacity(0.7)]), startPoint: .zero, endPoint: CGPoint(x: mid - 12, y: 0)), lineWidth: 1.2)
            ctx.stroke(Path { $0.move(to: CGPoint(x: mid + 12, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }, with: .linearGradient(Gradient(colors: [c.gold.opacity(0.7), .clear]), startPoint: CGPoint(x: mid + 12, y: 0), endPoint: CGPoint(x: size.width, y: 0)), lineWidth: 1.2)
            ctx.stroke(star8(CGPoint(x: mid, y: y), 6.5), with: .color(c.gold), lineWidth: 1.3)
            ctx.fill(Path(ellipseIn: CGRect(x: mid - 1.8, y: y - 1.8, width: 3.6, height: 3.6)), with: .color(c.gold))
        }.frame(width: width, height: 14)
    }
}

/// Slowly rotating eight-point rosette (behind the play button, the empty states).
struct Rosette: View {
    let color: Color; var spin = true
    @State private var r = 0.0
    var body: some View {
        Canvas { ctx, size in
            let ctr = CGPoint(x: size.width / 2, y: size.height / 2), rr = min(size.width, size.height) / 2
            ctx.stroke(star8(ctr, rr * 0.98), with: .color(color), lineWidth: 1.2)
            ctx.stroke(star8(ctr, rr * 0.78), with: .color(color.opacity(0.55)), lineWidth: 1)
        }
        .rotationEffect(.degrees(r))
        .onAppear { if spin { withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) { r = 360 } } }
    }
}

/// Card with layered ink, a gold hairline border and a faint lattice.
struct Panel<Content: View>: View {
    @Environment(\.pal) private var c
    var pad: CGFloat = 18
    var radius: CGFloat = 26
    var lattice = true
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(pad).frame(maxWidth: .infinity, alignment: .leading)
            .background(ZStack { LinearGradient(colors: [c.surface2, c.surface], startPoint: .top, endPoint: .bottom); if lattice { StarPattern(tile: 84, alpha: 0.9, fade: true) } })
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(LinearGradient(colors: [c.gold.opacity(0.45), c.line, c.gold.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }
}

// MARK: buttons and chips (the site's)
struct GoldButton: View {
    let title: String; var icon: String? = nil; let action: () -> Void
    @Environment(\.pal) private var c
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { if let icon { Ico(name: icon, size: 20, color: c.onGold) }; Text(title).font(F.plex(15, .bold)).foregroundStyle(c.onGold).lineLimit(1) }
                .padding(.horizontal, 20).padding(.vertical, 12).frame(minHeight: 48)
                .background(Capsule().fill(c.goldBrush)).shadow(color: c.gold.opacity(0.45), radius: 8, y: 3)
        }.buttonStyle(Press())
    }
}
struct GhostButton: View {
    let title: String; var icon: String? = nil; let action: () -> Void
    @Environment(\.pal) private var c
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { if let icon { Ico(name: icon, size: 20, color: c.gold) }; Text(title).font(F.plex(15, .semibold)).foregroundStyle(c.text).lineLimit(1) }
                .padding(.horizontal, 18).padding(.vertical, 12).frame(minHeight: 48)
                .background(Capsule().fill(c.surface.opacity(0.55))).overlay(Capsule().stroke(c.line, lineWidth: 1))
        }.buttonStyle(Press())
    }
}
struct Pill: View {
    let title: String; let on: Bool; var icon: String? = nil; let action: () -> Void
    @Environment(\.pal) private var c
    init(title: String, on: Bool, icon: String? = nil, action: @escaping () -> Void) { self.title = title; self.on = on; self.icon = icon; self.action = action }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Ico(name: icon, size: 17, color: on ? c.onGold : c.gold) }
                Text(title).font(F.plex(14, .semibold)).foregroundStyle(on ? c.onGold : c.text).lineLimit(1)
            }
            .padding(.horizontal, 15).padding(.vertical, 8)
            .background(Capsule().fill(on ? c.gold : c.surface.opacity(0.7)))
            .overlay(Capsule().stroke(on ? .clear : c.line, lineWidth: 1))
            .animation(.easeOut(duration: 0.26), value: on)
        }.buttonStyle(Press())
    }
}
/// The site's small outlined «chip» buttons (copy, tafsir, design…).
struct Chip: View {
    let text: String?; let icon: String; var on = false; let action: () -> Void
    @Environment(\.pal) private var c
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { Ico(name: icon, size: 18, color: c.gold); if let text { Text(text).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(1) } }
                .padding(.horizontal, text == nil ? 10 : 13).padding(.vertical, 8)
                .background(Capsule().fill(on ? c.gold.opacity(0.16) : c.bg2.opacity(0.5))).overlay(Capsule().stroke(on ? c.gold.opacity(0.6) : c.line, lineWidth: 1))
        }.buttonStyle(Press()).accessibilityLabel(text ?? icon)
    }
}
struct Press: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? scale : 1).animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
/// Round gold play/pause, with an optional slow rosette behind.
struct PlayCircle: View {
    let playing: Bool; var loading = false; var size: CGFloat = 56; var rosette = false; let action: () -> Void
    @Environment(\.pal) private var c
    var body: some View {
        ZStack {
            if rosette { Rosette(color: c.gold.opacity(0.35), spin: playing).frame(width: size * 1.5, height: size * 1.5) }
            Button(action: action) {
                ZStack {
                    Circle().fill(c.gold.opacity(playing ? 0.30 : 0.18)).frame(width: size + 14, height: size + 14)
                    Circle().fill(c.goldBrush).frame(width: size, height: size)
                    SiteIcon(name: playing ? "pause" : "play", size: size * 0.52, color: c.onGold).id(playing).transition(.scale(scale: 0.6).combined(with: .opacity))
                    if loading { ProgressView().tint(c.onGold) }
                }.animation(.easeOut(duration: 0.18), value: playing)
            }.buttonStyle(Press(scale: 0.9)).accessibilityLabel(playing ? tr("إيقاف مؤقت") : tr("تشغيل"))
        }.frame(width: rosette ? size * 1.5 : size + 14, height: rosette ? size * 1.5 : size + 14)
    }
}

struct SectionHead: View {
    let title: String; var action: String? = nil; var kicker: String? = nil; var tap: (() -> Void)? = nil
    @Environment(\.pal) private var c
    init(title: String, action: String? = nil, kicker: String? = nil, tap: (() -> Void)? = nil) { self.title = title; self.action = action; self.kicker = kicker; self.tap = tap }
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                if let kicker { Text(kicker).font(F.plex(12.5, .medium)).foregroundStyle(c.gold) }
                HStack(spacing: 8) {
                    Canvas { ctx, s in ctx.fill(sparkle(CGPoint(x: s.width / 2, y: s.height / 2), s.width / 2), with: .color(c.gold)) }.frame(width: 12, height: 12)
                    Text(title).font(F.amiri(23)).foregroundStyle(c.text)
                }
            }
            Spacer()
            if let action, let tap {
                Button(action: tap) {
                    HStack(spacing: 2) { Text(action).font(F.plex(12.5, .medium)); SiteIcon(name: "chev-l", size: 16, color: c.gold) }.foregroundStyle(c.gold)
                        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 6).overlay(Capsule().stroke(c.line))
                }.buttonStyle(Press())
            }
        }.padding(.leading, 18).padding(.trailing, 12).padding(.top, 22).padding(.bottom, 8)
    }
}

struct Empty: View {
    let text: String; var icon = "library"
    var action: String? = nil; var onAction: (() -> Void)? = nil
    @Environment(\.pal) private var c
    var body: some View {
        VStack(spacing: 12) {
            ZStack { Rosette(color: c.gold.opacity(0.35), spin: false); Ico(name: icon, size: 34, color: c.gold) }.frame(width: 84, height: 84)
            Text(text).font(F.plex(14)).foregroundStyle(c.muted).multilineTextAlignment(.center)
            if let action, let onAction { GhostButton(title: action, action: onAction).padding(.top, 2) }
        }.padding(36).frame(maxWidth: .infinity)
    }
}

/// Equaliser bars for whatever is playing.
struct Equalizer: View {
    var playing = true
    var color: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { tl in
            Canvas { ctx, size in
                let w = size.width / 5, t = tl.date.timeIntervalSinceReferenceDate
                for (i, d) in [0.38, 0.52, 0.44].enumerated() {
                    let ph = (t / d).truncatingRemainder(dividingBy: 2); let v = ph < 1 ? ph : 2 - ph
                    let h = size.height * (playing ? 0.25 + 0.75 * v : 0.3)
                    ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * w * 2, y: size.height - h, width: w, height: h), cornerRadius: w / 2), with: .color(color))
                }
            }
        }.frame(width: 16, height: 14)
    }
}

/// Image inside the mihrab arch with the site's gold outline and a soft foot shadow.
struct ArchImg: View {
    let raw: String?; var outline = true
    @Environment(\.pal) private var c
    var body: some View {
        ZStack {
            if outline { ArchShape(closed: false).stroke(LinearGradient(colors: [c.gold.opacity(0.85), c.gold.opacity(0.15)], startPoint: .top, endPoint: .bottom), lineWidth: 1.6) }
            ZStack { RemoteImage(raw: raw); LinearGradient(stops: [.init(color: .clear, location: 0.55), .init(color: c.bg.opacity(0.75), location: 1)], startPoint: .top, endPoint: .bottom) }
                .clipShape(ArchShape()).padding(outline ? 7 : 0)
        }
    }
}

// MARK: recitation row and card (like the site)
/// The current recitation's mark on its cover: a spinner while it loads, else the moving bars.
struct NowMark: View {
    let playing: Bool
    @ObservedObject private var clock = AudioPlayer.shared.clock
    @Environment(\.pal) private var c
    var body: some View {
        if clock.buffering { ProgressView().tint(c.gold) } else { Equalizer(playing: playing, color: c.gold).frame(width: 20, height: 18) }
    }
}

struct TrackRow: View {
    let t: Track; let list: [Track]
    var rank: Int = 0; var count: Int = 0; var showReciter = true
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var store: Store
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    var body: some View {
        let cur = player.current?.id == t.id
        let r = Repo.shared.reciter(t.reciterId)
        let detail = titleDetail(t)
        let meta = [t.durationText, relAgo(t), count > 0 ? tr("{0} استماع", count.ar) : ""].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        HStack(spacing: 0) {
            if rank > 0 { Text(rank.ar).font(F.amiri(22)).foregroundStyle(rank <= 3 ? c.gold : c.faint).frame(width: 26) }
            ZStack(alignment: .bottomLeading) {
                RemoteImage(raw: t.cover.isEmpty ? r?.image : t.cover).frame(width: t.isVideo ? 84 : 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 14))
                if t.isVideo { SiteIcon(name: "film", size: 13, color: .white).frame(width: 20, height: 20).background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.65))).padding(4) }
                if cur {
                    ZStack { RoundedRectangle(cornerRadius: 14).fill(c.bg.opacity(0.55)); NowMark(playing: player.playing) }
                        .frame(width: t.isVideo ? 84 : 56, height: 56).transition(.opacity)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(shortTitleL(t)).font(F.plex(15, .bold)).foregroundStyle(cur ? c.gold : c.text).lineLimit(2).multilineTextAlignment(.leading)
                if !detail.isEmpty { Text(detail).font(F.plex(12)).foregroundStyle(c.gold.opacity(0.78)).lineLimit(2).multilineTextAlignment(.leading) }
                if showReciter, let n = r?.name, !n.isEmpty { Text(n).font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(1) }
                HStack(spacing: 0) {
                    if isNewTrack(t) { Circle().fill(c.gold).frame(width: 6, height: 6).padding(.trailing, 6) }
                    if OfflineFiles.local(t.id) != nil { Image(systemName: "arrow.down.circle.fill").font(.system(size: 12)).foregroundStyle(c.ok).padding(.trailing, 4) }
                    Text(meta).font(F.plex(12)).foregroundStyle(c.faint).lineLimit(1)
                    if store.favs.contains(t.id) { SiteIcon(name: "heart-f", size: 13, color: c.gold).padding(.leading, 6) }
                }.padding(.top, 1)
            }.padding(.leading, 12).frame(maxWidth: .infinity, alignment: .leading)
            Button { play(cur) } label: {
                SiteIcon(name: cur && player.playing ? "pause" : "play", size: 17, color: cur ? c.onGold : c.gold)
                    .frame(width: 40, height: 40).background(Circle().fill(cur ? c.gold : .clear)).overlay(Circle().stroke(cur ? c.gold : c.line, lineWidth: 1.5))
            }.buttonStyle(Press()).padding(.leading, 6).accessibilityLabel(cur && player.playing ? tr("إيقاف مؤقت") : tr("تشغيل"))
            Button { ui.menuFor = t } label: { SiteIcon(name: "dots", size: 22, color: c.muted).frame(width: 36, height: 36) }.buttonStyle(.plain).accessibilityLabel(tr("خيارات أخرى"))
        }
        .padding(.horizontal, 8).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 18).fill(cur ? c.gold.opacity(0.09) : .clear))
        .contentShape(Rectangle()).onTapGesture { play(cur) }
        .padding(.horizontal, 10).padding(.vertical, 2)
        .animation(.easeOut(duration: 0.25), value: cur)
    }
    private func play(_ cur: Bool) {
        if t.isVideo { ui.path.append(.watch(t.id)) } else if cur { player.toggle() } else { player.play(t, in: list.filter { !$0.isVideo }) }
    }
}

/// «أحدث التلاوات» on the home page: the reciter's picture with the surah on it, swiped sideways.
struct TrackCard: View {
    let t: Track; let list: [Track]
    @EnvironmentObject var player: AudioPlayer
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    var body: some View {
        let cur = player.current?.id == t.id
        let r = Repo.shared.reciter(t.reciterId)
        let title = shortTitle(t), detail = titleDetail(t), k = title.hasPrefix("تلاوة من ")
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RemoteImage(raw: t.cover.isEmpty ? r?.image : t.cover)
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: Color(hex: 0x26050C0A), location: 0.45), .init(color: Color(hex: 0xEB050C0A), location: 1)], startPoint: .top, endPoint: .bottom)
                VStack {
                    HStack {
                        if !t.durationText.isEmpty { Text(t.durationText).font(F.plex(11.5, .semibold)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(.black.opacity(0.55))) }
                        Spacer()
                        if isNewTrack(t) { Text(tr("جديد")).font(F.plex(11, .bold)).foregroundStyle(c.onGold).padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(c.goldBrush)) }
                    }.padding(9)
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            if k { Text(tr("تلاوة من")).font(F.plex(11.5, .semibold)).foregroundStyle(.white.opacity(0.8)) }
                            Text(L.ar ? (k ? String(title.dropFirst(9)) : title) : { let loc = shortTitleL(t), pre = tr("تلاوة من") + " "; return k && loc.hasPrefix(pre) ? String(loc.dropFirst(pre.count)) : loc }()).font(F.amiri(19)).foregroundStyle(.white).lineLimit(2)
                        }
                        Spacer(minLength: 6)
                        SiteIcon(name: cur && player.playing ? "pause" : "play", size: 15, color: c.onGold).frame(width: 34, height: 34).background(Circle().fill(c.gold))
                    }.padding(10)
                }
            }
            .aspectRatio(5 / 6, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(cur ? c.gold : .clear, lineWidth: 2))
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(nm(r?.name)).font(F.plex(13, .semibold)).foregroundStyle(c.text).lineLimit(1)
                    if !detail.isEmpty { Text(detail).font(F.plex(11.5)).foregroundStyle(c.gold.opacity(0.78)).lineLimit(2) }
                    Text(relAgo(t)).font(F.plex(11.5)).foregroundStyle(c.faint)
                }.padding(.top, 7).frame(maxWidth: .infinity, alignment: .leading)
                Button { ui.menuFor = t } label: { SiteIcon(name: "dots", size: 18, color: c.muted).frame(width: 32, height: 32) }.buttonStyle(.plain).accessibilityLabel(tr("خيارات أخرى"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if t.isVideo { ui.path.append(.watch(t.id)) } else if cur { player.toggle() } else { player.play(t, in: list.filter { !$0.isVideo }) } }
    }
}

/// The site's segmented tabs (.seg).
struct Seg: View {
    let items: [String]; let selected: Int; let pick: (Int) -> Void
    @Environment(\.pal) private var c
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Button { pick(i) } label: {
                    Text(items[i]).font(F.plex(14, .semibold)).foregroundStyle(i == selected ? c.onGold : c.text).lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Capsule().fill(i == selected ? c.gold : .clear))
                }.buttonStyle(.plain)
            }
        }.padding(4).background(Capsule().fill(c.surface.opacity(0.7))).overlay(Capsule().stroke(c.line)).animation(.easeOut(duration: 0.25), value: selected)
    }
}

/// A sheet's heading like the site: the title, a close button, the gold ornament.
struct SheetHead: View {
    let title: String
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title).font(F.amiri(22)).foregroundStyle(c.text); Spacer(); Button { dismiss() } label: { SiteIcon(name: "close", size: 22, color: c.muted).frame(width: 40, height: 40) }.accessibilityLabel(tr("إغلاق")) }
            Ornament(width: 120).padding(.bottom, 8)
        }.padding(.leading, 22).padding(.trailing, 10).padding(.top, 14)
    }
}

extension View {
    /// Soft entrance: fade + rise once.
    func reveal(_ delay: Double = 0) -> some View { modifier(Reveal(delay: delay)) }
}
private struct Reveal: ViewModifier {
    let delay: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
            .onAppear { withAnimation(.easeOut(duration: 0.5).delay(delay)) { shown = true } }
    }
}

func share(_ text: String) {
    let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController?.topMost.present(av, animated: true)
}
extension UIViewController { var topMost: UIViewController { presentedViewController?.topMost ?? self } }


// MARK: - sheets and lists in the app's colours (the system's black never shows)

/// Every sheet sits on the theme's sheet colour, like Android's bottom sheets (containerColor = bg2).
struct SheetSkin: ViewModifier {
    @Environment(\.pal) private var c
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) { content.presentationBackground(c.bg2).environment(\.pal, c).preferredColorScheme(c.dark ? .dark : .light) }
        else { content.background(c.bg2.ignoresSafeArea()).environment(\.pal, c).preferredColorScheme(c.dark ? .dark : .light) }
    }
}
extension View {
    func bzSheet<V: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> V) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) { content().modifier(SheetSkin()) }
    }
    func bzSheet<I: Identifiable, V: View>(item: Binding<I?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (I) -> V) -> some View {
        sheet(item: item, onDismiss: onDismiss) { content($0).modifier(SheetSkin()) }
    }
    /// A system List drawn on the theme's colours instead of the system's black and grey.
    func bzList(_ c: Palette) -> some View {
        self.scrollContentBackground(.hidden).background(c.bg2.ignoresSafeArea())
            .toolbarBackground(c.bg2, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
    }
}
