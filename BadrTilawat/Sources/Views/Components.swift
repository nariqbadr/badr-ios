import SwiftUI

// MARK: images (memory + disk cache)
final class ImageCache {
    static let shared = ImageCache()
    private let mem = NSCache<NSURL, UIImage>()
    private var dir: URL { let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("img"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }
    private func file(_ u: URL) -> URL { dir.appendingPathComponent(String(u.absoluteString.hashValue, radix: 36)) }
    func cached(_ u: URL) -> UIImage? {
        if let i = mem.object(forKey: u as NSURL) { return i }
        if let d = try? Data(contentsOf: file(u)), let i = UIImage(data: d) { mem.setObject(i, forKey: u as NSURL); return i }
        return nil
    }
    func load(_ u: URL) async -> UIImage? {
        if let i = cached(u) { return i }
        guard let (d, _) = try? await Repo.shared.session.data(from: u), let i = UIImage(data: d) else { return nil }
        mem.setObject(i, forKey: u as NSURL); try? d.write(to: file(u)); return i
    }
}

struct RemoteImage: View {
    let raw: String?
    var mode: ContentMode = .fill
    @State private var img: UIImage?
    @Environment(\.pal) private var c
    var body: some View {
        ZStack {
            if let img { Image(uiImage: img).resizable().aspectRatio(contentMode: mode).transition(.opacity) }
            else { Rectangle().fill(c.surface2); Image("Logo").resizable().scaledToFit().padding(12).opacity(0.25) }
        }
        .clipped()
        .task(id: raw) {
            guard let u = Repo.media(raw) else { img = nil; return }
            if let i = ImageCache.shared.cached(u) { img = i; return }
            let i = await ImageCache.shared.load(u)
            withAnimation(.easeOut(duration: 0.35)) { img = i }
        }
    }
}

// MARK: shapes & decoration
/// The mihrab arch used on the site for reciter portraits.
struct ArchShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height, top = w * 0.42
        p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: top))
        p.addQuadCurve(to: CGPoint(x: w / 2, y: 0), control: CGPoint(x: 0, y: top * 0.22))
        p.addQuadCurve(to: CGPoint(x: w, y: top), control: CGPoint(x: w, y: top * 0.22))
        p.addLine(to: CGPoint(x: w, y: h)); p.closeSubpath()
        return p
    }
}

/// Eight-pointed star lattice (the site's background pattern).
struct StarPattern: View {
    @Environment(\.pal) private var c
    var cell: CGFloat = 90
    var body: some View {
        Canvas { ctx, size in
            for y in stride(from: 0, through: size.height + cell, by: cell) {
                for x in stride(from: 0, through: size.width + cell, by: cell) {
                    for rot in [0.0, 45.0] {
                        var p = Path(); let r = cell * 0.3
                        for i in 0..<4 {
                            let a = (Double(i) * 90 + rot) * .pi / 180
                            let pt = CGPoint(x: x + r * cos(a), y: y + r * sin(a))
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                        p.closeSubpath()
                        ctx.stroke(p, with: .color(c.pattern), lineWidth: 1)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct Backdrop: View {
    @Environment(\.pal) private var c
    var body: some View {
        ZStack {
            LinearGradient(colors: c.grad, startPoint: .top, endPoint: .bottom)
            StarPattern().opacity(0.9)
            RadialGradient(colors: [c.gold.opacity(c.dark ? 0.10 : 0.06), .clear], center: .top, startRadius: 0, endRadius: 420)
        }.ignoresSafeArea()
    }
}

struct Panel<Content: View>: View {
    @Environment(\.pal) private var c
    var pad: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(pad).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [c.surface, c.surface.opacity(0.85)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(c.line, lineWidth: 1))
    }
}

// MARK: buttons
struct GoldButton: View {
    let title: String; var icon: String? = nil; let action: () -> Void
    @Environment(\.pal) private var c
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { if let icon { Image(systemName: icon) }; Text(title).font(F.plex(15, .bold)) }
                .foregroundStyle(c.onGold).padding(.horizontal, 20).frame(minHeight: 48)
                .background(Capsule().fill(c.goldGradient)).shadow(color: c.gold.opacity(0.35), radius: 10, y: 3)
        }.buttonStyle(Press())
    }
}
struct GhostButton: View {
    let title: String; var icon: String? = nil; let action: () -> Void
    @Environment(\.pal) private var c
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { if let icon { Image(systemName: icon).foregroundStyle(c.gold) }; Text(title).font(F.plex(15, .semibold)).foregroundStyle(c.text) }
                .padding(.horizontal, 18).frame(minHeight: 48)
                .background(Capsule().fill(c.surface.opacity(0.6))).overlay(Capsule().stroke(c.line, lineWidth: 1))
        }.buttonStyle(Press())
    }
}
struct Pill: View {
    let title: String; let on: Bool; let action: () -> Void
    @Environment(\.pal) private var c
    var body: some View {
        Button(action: action) {
            Text(title).font(F.plex(13.5, on ? .bold : .medium)).foregroundStyle(on ? c.onGold : c.text)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(on ? AnyShapeStyle(c.goldGradient) : AnyShapeStyle(c.surface.opacity(0.7))))
                .overlay(Capsule().stroke(on ? .clear : c.line, lineWidth: 1))
        }.buttonStyle(Press())
    }
}
struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1).animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct SectionHead: View {
    let title: String; var action: String? = nil; var tap: (() -> Void)? = nil
    @Environment(\.pal) private var c
    var body: some View {
        HStack {
            Text(title).font(F.amiri(22)).foregroundStyle(c.text)
            Spacer()
            if let action, let tap { Button(action: tap) { HStack(spacing: 4) { Text(action).font(F.plex(13, .semibold)); Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)) }.foregroundStyle(c.gold) } }
        }.padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 8)
    }
}

struct Empty: View {
    let text: String; var icon = "music.note"
    @Environment(\.pal) private var c
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(c.gold.opacity(0.7))
            Text(text).font(F.plex(15)).foregroundStyle(c.muted).multilineTextAlignment(.center)
        }.padding(40).frame(maxWidth: .infinity)
    }
}

/// Animated equalizer bars (playing indicator).
struct Equalizer: View {
    var color: Color
    @State private var on = false
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(color).frame(width: 3, height: on ? [10, 6, 12][i] : [4, 11, 5][i])
                    .animation(.easeInOut(duration: [0.45, 0.6, 0.5][i]).repeatForever(autoreverses: true), value: on)
            }
        }.frame(height: 12).onAppear { on = true }
    }
}

// MARK: recitation row
struct TrackRow: View {
    let t: Track; let list: [Track]
    var rank: Int = 0; var count: Int = 0
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    var body: some View {
        let cur = player.current?.id == t.id
        Button { if cur { player.toggle() } else { player.play(t, in: list) } } label: {
            HStack(spacing: 12) {
                if rank > 0 { Text(rank.ar).font(F.amiri(22)).foregroundStyle(rank <= 3 ? c.gold : c.faint).frame(width: 28) }
                ZStack {
                    RemoteImage(raw: Repo.shared.image(for: t)).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 14))
                    if cur && player.playing { RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.35)).frame(width: 56, height: 56); Equalizer(color: c.gold2) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(t.title).font(F.plex(15, .semibold)).foregroundStyle(cur ? c.gold : c.text).lineLimit(2).multilineTextAlignment(.leading)
                        if Fmt.isNew(t) { Text("جديد").font(F.plex(10, .bold)).foregroundStyle(c.onGold).padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(c.gold)) }
                    }
                    HStack(spacing: 6) {
                        Text(Repo.shared.reciter(t.reciterId)?.name ?? "").font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(1)
                        if !t.durationText.isEmpty { Text("· " + t.durationText).font(F.plex(12)).foregroundStyle(c.faint) }
                        if count > 0 { Text("· \(count.ar) استماع").font(F.plex(12)).foregroundStyle(c.faint) }
                    }
                }
                Spacer(minLength: 4)
                Button { store.toggleFav(t.id) } label: { Image(systemName: store.favs.contains(t.id) ? "heart.fill" : "heart").foregroundStyle(store.favs.contains(t.id) ? c.danger : c.muted) }.buttonStyle(.plain)
                Button { ui.menuFor = t } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).foregroundStyle(c.muted).frame(width: 30, height: 30) }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
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
