import SwiftUI
import PDFKit

struct QuranView: View {
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var q = ""
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack(spacing: 12) {
                    tile("المصحف الشريف", "صفحات مصحف المدينة", "book") { ui.path.append(.mushaf) }
                    tile("اقرأ واستمع واحفظ", "الكلمات تضيء مع التلاوة", "waveform") { ui.path.append(.readIndex) }
                }.padding(16)
                QuranFullBanner().padding(.horizontal, 16).padding(.bottom, 12)
                TextField("ابحث عن سورة باسمها أو رقمها", text: $q).font(F.plex(15)).padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(c.surface.opacity(0.7))).overlay(RoundedRectangle(cornerRadius: 16).stroke(c.line)).padding(.horizontal, 16)
                ForEach(Array(Quran.surahs.enumerated()).filter { q.isEmpty || $0.element.contains(q) || "\($0.offset + 1)" == q }, id: \.offset) { i, n in
                    Button { ui.path.append(.surah(i + 1)) } label: {
                        HStack(spacing: 14) {
                            ZStack { Image(systemName: "seal").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(c.gold); Text((i + 1).ar).font(F.plex(12, .bold)).foregroundStyle(c.gold) }.frame(width: 40)
                            VStack(alignment: .leading, spacing: 2) { Text("سورة \(n)").font(F.amiri(19)).foregroundStyle(c.text); Text("\(Quran.ayahs[i].ar) آية · صفحة \(Quran.surahPage[i].ar)").font(F.plex(12)).foregroundStyle(c.muted) }
                            Spacer()
                            Image(systemName: "chevron.left").foregroundStyle(c.faint)
                        }.padding(.horizontal, 18).padding(.vertical, 10).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(.bottom, 20)
        }
    }
    private func tile(_ t: String, _ s: String, _ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            VStack(alignment: .leading, spacing: 6) { Image(systemName: icon).font(.system(size: 22)).foregroundStyle(c.gold); Text(t).font(F.plex(15, .bold)).foregroundStyle(c.text); Text(s).font(F.plex(12)).foregroundStyle(c.muted) }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(RoundedRectangle(cornerRadius: 22).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 22).stroke(c.line))
        }.buttonStyle(Press())
    }
}

/// «اقرأ واستمع واحفظ»: the surah's text, tap an ayah to hear it, or play the whole surah ayah after ayah.
struct SurahView: View {
    @State var s: Int
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var ayah: AyahPlayer
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var ayahs: [String] = []
    @State private var tafsir: [Int: String] = [:]
    @State private var showTafsir: Int?
    @State private var continuous = false
    @State private var size: CGFloat = 26
    var rv: String { store.ayahReciter.isEmpty ? (repo.data?.site.dailyReciter ?? "yasser") : store.ayahReciter }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Text("سورة \(Quran.surahs[s - 1])").font(F.amiri(30)).foregroundStyle(c.gold).padding(.top, 16)
                    Text("\(Quran.ayahs[s - 1].ar) آية").font(F.plex(12)).foregroundStyle(c.muted)
                    HStack(spacing: 10) {
                        Button { if continuous { continuous = false; ayah.stop() } else { continuous = true; playFrom(1) } } label: {
                            Label(continuous ? "إيقاف" : "تشغيل السورة", systemImage: continuous ? "stop.fill" : "play.fill").font(F.plex(13, .bold)).foregroundStyle(c.onGold).padding(.horizontal, 16).padding(.vertical, 9).background(Capsule().fill(c.gold))
                        }
                        Menu { ForEach(ayah.options(s, 1), id: \.self) { o in Button(o.label) { store.ayahReciter = o.value } } } label: {
                            Text(ayah.label(rv, s, 1).isEmpty ? "القارئ" : ayah.label(rv, s, 1)).font(F.plex(13)).foregroundStyle(c.text).lineLimit(1).padding(.horizontal, 12).padding(.vertical, 9).background(Capsule().fill(c.surface2))
                        }
                        Button { size = size >= 34 ? 22 : size + 4 } label: { Image(systemName: "textformat.size").foregroundStyle(c.gold) }
                    }.padding(.vertical, 12)
                    if s != 1 && s != 9 { Text("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ").font(F.quran(24)).foregroundStyle(c.text).padding(.bottom, 8) }
                    if ayahs.isEmpty { ProgressView().padding(40) }
                    ForEach(Array(ayahs.enumerated()), id: \.offset) { i, t in
                        let a = i + 1, on = ayah.key?.hasPrefix("\(s):\(a)|") == true
                        Button { continuous = false; if on && ayah.playing { ayah.stop() } else { ayah.play(rv, s, a) } } label: {
                            Text(clean(a, t) + " ﴿\(a.ar)﴾").font(F.quran(size)).lineSpacing(size * 0.55).foregroundStyle(on ? c.gold : c.text)
                                .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.horizontal, 18).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 16).fill(on ? c.gold.opacity(0.1) : .clear))
                        }.buttonStyle(.plain).id(a)
                        .contextMenu {
                            Button { Task { if tafsir.isEmpty { tafsir = await repo.tafsir(s) }; showTafsir = a } } label: { Label("التفسير الميسر", systemImage: "text.book.closed") }
                            Button { share("﴿\(clean(a, t))﴾ [سورة \(Quran.surahs[s - 1]): \(a)]") } label: { Label("مشاركة", systemImage: "square.and.arrow.up") }
                            if repo.data?.site.sec("community") != false { Button { ui.path.append(.compose("ayah:\(s):\(a)|\(rv)")) } label: { Label("انشرها في المجتمع", systemImage: "bubble.left") } }
                        }
                    }
                    HStack {
                        if s < 114 { GhostButton(title: "السورة التالية") { ayah.stop(); s += 1 } }
                        if s > 1 { GhostButton(title: "السورة السابقة") { ayah.stop(); s -= 1 } }
                    }.padding(24)
                }
            }
            .onChange(of: ayah.key) { k in if continuous, let k, let a = Int(k.split(separator: "|")[0].split(separator: ":")[1]) { withAnimation { proxy.scrollTo(a, anchor: .center) } } }
        }
        .background(Backdrop())
        .navigationTitle("سورة \(Quran.surahs[s - 1])").navigationBarTitleDisplayMode(.inline)
        .task(id: s) { ayahs = []; tafsir = [:]; ayahs = await repo.surahText(s) ?? [] }
        .sheet(item: Binding(get: { showTafsir.map { IntBox(v: $0) } }, set: { showTafsir = $0?.v })) { b in
            ScrollView { VStack(alignment: .leading, spacing: 10) {
                Text("التفسير الميسر — الآية \(b.v.ar)").font(F.plex(15, .bold)).foregroundStyle(c.gold)
                Text(tafsir[b.v] ?? "تعذّر تحميل التفسير.").font(F.plex(16)).foregroundStyle(c.text).lineSpacing(6)
            }.padding(22) }.presentationDetents([.medium, .large]).environment(\.layoutDirection, .rightToLeft)
        }
        .onDisappear { continuous = false }
    }
    private func clean(_ a: Int, _ t: String) -> String {
        guard a == 1, s != 1, let r = t.range(of: "^بِسْمِ\\s+ٱللَّهِ\\s+ٱلرَّحْمَٰنِ\\s+ٱلرَّحِيمِ\\s*", options: .regularExpression) else { return t }
        var x = t; x.removeSubrange(r); return x
    }
    private func playFrom(_ a: Int) {
        guard continuous, a <= Quran.ayahs[s - 1] else { continuous = false; return }
        ayah.play(rv, s, a) { playFrom(a + 1) }
    }
}
struct IntBox: Identifiable { let v: Int; var id: Int { v } }

/// The site's mushaf PDF (downloaded once, then works offline).
struct MushafView: View {
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    @State private var doc: PDFDocument?
    @State private var progress: Double = 0
    @State private var failed = false
    @State private var page = UserDefaults.standard.integer(forKey: "mushafPage")
    @State private var jump = false
    var body: some View {
        ZStack {
            if let doc {
                PDFPages(doc: doc, page: $page)
            } else if failed {
                VStack(spacing: 14) { Empty(text: "تعذّر تحميل المصحف — تحقق من الإنترنت.", icon: "wifi.slash"); GhostButton(title: "إعادة المحاولة") { failed = false; Task { await load() } } }
            } else {
                VStack(spacing: 12) { ProgressView().tint(c.gold); Text("جارٍ تحميل المصحف لأول مرة… قد يستغرق دقيقة").font(F.plex(14)).foregroundStyle(c.muted) }
            }
        }
        .background(Backdrop())
        .navigationTitle("المصحف — صفحة \(max(1, page + 1 - (repo.data?.site.mushafOffset ?? 0)).ar)").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { jump = true } label: { Image(systemName: "list.bullet") } }
        .sheet(isPresented: $jump) {
            NavigationStack {
                List(Array(Quran.surahs.enumerated()), id: \.offset) { i, n in
                    Button("\((i + 1).ar). سورة \(n)") { page = Quran.surahPage[i] - 1 + (repo.data?.site.mushafOffset ?? 0); jump = false }.foregroundStyle(c.text)
                }.navigationTitle("اذهب إلى سورة").navigationBarTitleDisplayMode(.inline)
            }.environment(\.layoutDirection, .rightToLeft)
        }
        .task { await load() }
        .onChange(of: page) { UserDefaults.standard.set($0, forKey: "mushafPage") }
    }
    private func load() async {
        let f = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("mushaf.pdf")
        if let d = PDFDocument(url: f) { doc = d; return }
        guard let u = Repo.media(repo.data?.site.mushafUrl ?? "/standard1-quran.pdf") else { failed = true; return }
        do {
            let (tmp, _) = try await URLSession.shared.download(from: u)
            try? FileManager.default.removeItem(at: f)
            try FileManager.default.moveItem(at: tmp, to: f)
            doc = PDFDocument(url: f); if doc == nil { failed = true }
        } catch { failed = true }
    }
}

struct PDFPages: UIViewRepresentable {
    let doc: PDFDocument
    @Binding var page: Int
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView(); v.document = doc; v.displayMode = .singlePage; v.displayDirection = .horizontal; v.autoScales = true
        v.usePageViewController(true); v.displaysRTL = true; v.backgroundColor = .clear
        if let p = doc.page(at: max(0, min(page, doc.pageCount - 1))) { v.go(to: p) }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.changed(_:)), name: .PDFViewPageChanged, object: v)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {
        if let cur = v.currentPage, doc.index(for: cur) != page, let p = doc.page(at: max(0, min(page, doc.pageCount - 1))) { v.go(to: p) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject {
        let parent: PDFPages
        init(_ p: PDFPages) { parent = p }
        @objc func changed(_ n: Notification) { if let v = n.object as? PDFView, let p = v.currentPage { let i = parent.doc.index(for: p); DispatchQueue.main.async { self.parent.page = i } } }
    }
}
