import SwiftUI
import WebKit

/// YouTube player (live stream, fiqh lessons).
struct YouTube: UIViewRepresentable {
    let id: String
    var autoplay = false
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration(); cfg.allowsInlineMediaPlayback = true; cfg.mediaTypesRequiringUserActionForPlayback = []
        let w = WKWebView(frame: .zero, configuration: cfg); w.isOpaque = false; w.backgroundColor = .black; w.scrollView.isScrollEnabled = false
        return w
    }
    func updateUIView(_ w: WKWebView, context: Context) {
        let html = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;background:#000;height:100%}iframe{border:0;width:100%;height:100%}</style></head>
        <body><iframe src="https://www.youtube.com/embed/\(id)?playsinline=1&autoplay=\(autoplay ? 1 : 0)&rel=0" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe></body></html>
        """
        if context.coordinator.loaded != id { context.coordinator.loaded = id; w.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com")) }
    }
    func makeCoordinator() -> Coord { Coord() }
    final class Coord { var loaded = "" }
}

struct LiveView: View {
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    var body: some View {
        let l = repo.data?.site.live
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let id = ytId(l?["url"].str ?? "") {
                    YouTube(id: id, autoplay: true).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 20))
                } else { Empty(text: "البث المباشر غير متاح الآن.", icon: "dot.radiowaves.left.and.right") }
                HStack(spacing: 6) { Circle().fill(.red).frame(width: 9, height: 9); Text("مباشر").font(F.plex(13, .bold)).foregroundStyle(c.danger) }
                Text(l?["title"].str ?? "البث المباشر").font(F.amiri(26)).foregroundStyle(c.text)
                Text("يمكنك تشغيل الصوت ومتابعة البث، أو فتحه على يوتيوب.").font(F.plex(14)).foregroundStyle(c.muted)
                if let u = URL(string: l?["url"].str ?? "") { Link(destination: u) { Label("فتح على يوتيوب", systemImage: "arrow.up.forward.app").font(F.plex(14, .semibold)).foregroundStyle(c.gold) } }
            }.padding(16)
        }
    }
}

struct FiqhView: View {
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    @State private var open: String?
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                Text("دروس الفقه").font(F.amiri(28)).foregroundStyle(c.text).padding(.top, 14)
                if (repo.data?.fiqh ?? []).isEmpty { Empty(text: "لا توجد دروس بعد.", icon: "text.book.closed") }
                ForEach(repo.data?.fiqh ?? []) { f in
                    Panel(pad: 12) {
                        if open == f.id, let id = ytId(f.video) { YouTube(id: id, autoplay: true).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 16)) }
                        else {
                            Button { open = f.id } label: {
                                ZStack {
                                    RemoteImage(raw: ytId(f.video).map { "https://i.ytimg.com/vi/\($0)/hqdefault.jpg" }).aspectRatio(16 / 9, contentMode: .fill).clipShape(RoundedRectangle(cornerRadius: 16))
                                    Image(systemName: "play.fill").foregroundStyle(c.onGold).frame(width: 54, height: 54).background(Circle().fill(c.gold))
                                }
                            }.buttonStyle(.plain)
                        }
                        Text(f.title).font(F.plex(15, .semibold)).foregroundStyle(c.text).padding(.top, 10)
                        if !f.teacher.isEmpty { Text(f.teacher).font(F.plex(12.5)).foregroundStyle(c.gold) }
                    }.padding(.horizontal, 16)
                }
            }.padding(.bottom, 24)
        }
    }
}

struct AboutView: View {
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    var body: some View {
        let a = repo.data?.site.about
        ScrollView {
            VStack(spacing: 14) {
                RemoteImage(raw: a?["image"].str).frame(width: 210, height: 260).clipShape(ArchShape()).overlay(ArchShape().stroke(c.gold.opacity(0.6), lineWidth: 1.5)).padding(.top, 20)
                Text(a?["name"].str ?? "الشيخ خالد بن سالم باوزير").font(F.amiri(28)).foregroundStyle(c.text)
                if let i = a?["intro"].str, !i.isEmpty { Text(i).font(F.plex(15, .medium)).foregroundStyle(c.gold).multilineTextAlignment(.center) }
                if let b = a?["bio"].str, !b.isEmpty { Text(b).font(F.plex(15)).foregroundStyle(c.text).lineSpacing(6).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                let ms = a?["milestones"].array ?? []
                if !ms.isEmpty {
                    SectionHead(title: "محطات")
                    ForEach(Array(ms.enumerated()), id: \.offset) { _, m in
                        HStack(alignment: .top, spacing: 12) { Text(m["year"].str).font(F.plex(14, .bold)).foregroundStyle(c.gold).frame(width: 60); Text(m["text"].str).font(F.plex(14)).foregroundStyle(c.text); Spacer() }
                    }
                }
            }.padding(20)
        }
    }
}

struct TimelineScreen: View {
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    var body: some View {
        let items = (repo.data?.events ?? []).sorted { (Fmt.parse($0.date) ?? .distantPast) > (Fmt.parse($1.date) ?? .distantPast) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("الخط الزمني").font(F.amiri(28)).foregroundStyle(c.text).frame(maxWidth: .infinity).padding(.vertical, 14)
                if items.isEmpty { Empty(text: "لا توجد أحداث بعد.", icon: "clock") }
                ForEach(items) { e in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) { Circle().fill(c.gold).frame(width: 12, height: 12); Rectangle().fill(c.line).frame(width: 2) }
                        VStack(alignment: .leading, spacing: 6) {
                            if let d = Fmt.parse(e.date) { Text(Fmt.date(d)).font(F.plex(12)).foregroundStyle(c.gold) }
                            Text(e.title).font(F.plex(16, .semibold)).foregroundStyle(c.text)
                            if !e.text.isEmpty { Text(e.text).font(F.plex(14)).foregroundStyle(c.muted) }
                            if !e.image.isEmpty { RemoteImage(raw: e.image).frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 14)) }
                        }.padding(.bottom, 22)
                    }.padding(.horizontal, 20)
                }
            }
        }
    }
}

struct ThemeSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let c = Themes.get(store.theme)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("المظهر").font(F.amiri(24)).foregroundStyle(c.text)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Themes.all, id: \.key) { p in
                        Button { withAnimation { store.theme = p.key } } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 4) { Circle().fill(p.gold).frame(width: 18); Circle().fill(p.surface2).frame(width: 18); Circle().fill(p.text).frame(width: 18) }
                                Text(p.name).font(F.plex(14, .semibold)).foregroundStyle(p.text)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(RoundedRectangle(cornerRadius: 18).fill(p.bg)).overlay(RoundedRectangle(cornerRadius: 18).stroke(store.theme == p.key ? p.gold : p.line, lineWidth: store.theme == p.key ? 2 : 1))
                        }.buttonStyle(Press())
                    }
                }
            }.padding(20)
        }.background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, .rightToLeft).presentationDetents([.medium])
    }
}

struct NameSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var v = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("اسمك في التطبيق").font(F.amiri(24)).foregroundStyle(c.text)
            Text("اكتب اسمك هنا للترحيب بك.").font(F.plex(14)).foregroundStyle(c.muted)
            TextField("مثال: أحمد", text: $v).font(F.plex(16)).padding(14).background(RoundedRectangle(cornerRadius: 16).fill(c.surface))
            HStack {
                GoldButton(title: "حفظ", icon: "checkmark") { store.name = String(v.trimmingCharacters(in: .whitespaces).prefix(30)); if !store.name.isEmpty { Repo.shared.event("name", ["visitorName": store.name]) }; dismiss() }
                if !store.name.isEmpty { GhostButton(title: "حذف الاسم") { store.name = ""; dismiss() } }
            }
            Spacer()
        }.padding(22).background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, .rightToLeft).onAppear { v = store.name }.presentationDetents([.medium])
    }
}

struct NoticesSheet: View {
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("التنبيهات").font(F.amiri(24)).foregroundStyle(c.text)
                if (repo.data?.notices ?? []).isEmpty { Empty(text: "لا توجد تنبيهات.", icon: "bell") }
                ForEach(repo.data?.notices ?? []) { n in
                    Panel { Text(n.title).font(F.plex(16, .semibold)).foregroundStyle(c.text); if !n.text.isEmpty { Text(n.text).font(F.plex(14)).foregroundStyle(c.muted).padding(.top, 4) } }
                }
            }.padding(20)
        }.background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, .rightToLeft)
    }
}
