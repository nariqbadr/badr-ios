import SwiftUI
import UIKit

/// The Madinah mushaf, bundled (works offline): every page's 15 printed lines in the King Fahd Complex HAFS script
/// (Resources/mushaf.json — the same data as the website and the Android app). A line is a surah title, the basmala, or ayah pieces.
enum MushafData {
    enum Line { case title(Int), basmala, words([Seg]) }
    struct Seg { let g: Int; let text: String; let end: Bool }
    nonisolated(unsafe) private(set) static var pages: [[Line]] = []
    nonisolated(unsafe) private(set) static var pageStart: [Int] = []
    nonisolated(unsafe) private(set) static var juzStart: [Int] = []
    nonisolated(unsafe) private(set) static var quarterStart: [Int] = []
    private static let before: [Int] = { var b = [0]; for n in Quran.ayahs { b.append(b.last! + n) }; return b }()
    static let font = "KFGQPCHAFSUthmanicScript-Regula"
    static let basmala = "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ"
    static var loaded: Bool { !pages.isEmpty }

    static func load() {
        guard pages.isEmpty, let u = Bundle.main.url(forResource: "mushaf", withExtension: "json"), let d = try? Data(contentsOf: u),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        func ints(_ k: String) -> [Int] { (o[k] as? [Any] ?? []).map { ($0 as? NSNumber)?.intValue ?? 0 } }
        pageStart = ints("p"); juzStart = ints("j"); quarterStart = ints("r")
        pages = (o["pages"] as? [[Any]] ?? []).map { pg in
            pg.compactMap { ln -> Line? in
                guard let a = ln as? [Any] else { return nil }
                if let f = a.first as? String { return f == "h" ? .title((a[1] as? NSNumber)?.intValue ?? 1) : .basmala }
                return .words(a.compactMap { sg in
                    guard let x = sg as? [Any], x.count >= 3 else { return nil }
                    return Seg(g: (x[0] as? NSNumber)?.intValue ?? 0, text: x[1] as? String ?? "", end: (x[2] as? NSNumber)?.intValue == 1)
                })
            }
        }
    }
    static func gid(_ s: Int, _ a: Int) -> Int { before[s - 1] + a }
    static func sa(_ g: Int) -> (Int, Int) { var s = 1; while s < 114 && before[s] < g { s += 1 }; return (s, g - before[s - 1]) }
    static func pageOf(_ g: Int) -> Int { var lo = 1, hi = 604; while lo < hi { let m = (lo + hi + 1) / 2; if pageStart[m] <= g { lo = m } else { hi = m - 1 } }; return lo }
    static func juzOf(_ g: Int) -> Int { var j = 1; while j < 30 && juzStart[j + 1] <= g { j += 1 }; return j }
    static func hizbOf(_ g: Int) -> Int { var q = 1; while q < 240 && quarterStart[q + 1] <= g { q += 1 }; return (q + 3) / 4 }
    static func firstG(_ p: Int) -> Int {
        for l in pages[p - 1] { if case .words(let s) = l, let f = s.first { return f.g } }
        return pageStart[p]
    }
    /// the ayah's words as printed (all its pieces on its page or the next)
    static func text(_ g: Int) -> String {
        let p = pageOf(g)
        return (p...min(604, p + 1)).flatMap { pages[$0 - 1] }.flatMap { l -> [Seg] in if case .words(let s) = l { return s }; return [] }.filter { $0.g == g }.map(\.text).joined(separator: " ")
    }
    static func ayahsOn(_ p: Int) -> [Int] {
        var out: [Int] = []
        for l in pages[p - 1] { if case .words(let s) = l { for x in s where !out.contains(x.g) { out.append(x.g) } } }
        return out
    }
    static func endMark(_ g: Int) -> String { "\u{06DD}" + sa(g).1.ar }
}

/// «استمع للصفحة»: ayah after ayah with the chosen reciter; the page turns by itself.
@MainActor
final class MushafAudio: ObservableObject {
    static let shared = MushafAudio()
    @Published var current = 0
    func play(_ g: Int, _ rv: String) {
        current = g
        let (s, a) = MushafData.sa(g)
        UserDefaults.standard.set(g, forKey: "mushafAyah")
        AyahPlayer.shared.play(rv, s, a) { [weak self] in
            guard let self, self.current == g else { return }
            if g < 6236 { self.play(g + 1, rv) } else { self.stop() }
        }
    }
    func stop() { current = 0; AyahPlayer.shared.stop() }
}

/// Mushaf: 604 pages, swiped like a printed mushaf (right to left); opens on the last page read.
struct MushafView: View {
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var ayah: AyahPlayer
    @EnvironmentObject var store: Store
    @ObservedObject private var ma = MushafAudio.shared
    @Environment(\.pal) private var c
    @State private var ready = MushafData.loaded
    @State private var page = max(1, min(604, UserDefaults.standard.integer(forKey: "mushafPage") == 0 ? 1 : UserDefaults.standard.integer(forKey: "mushafPage")))
    @State private var marks: [Int] = (UserDefaults.standard.string(forKey: "mushafMarks") ?? "").split(separator: ",").compactMap { Int($0) }.filter { (1...604).contains($0) }
    @State private var jump = false
    @State private var tafsir = false
    @State private var menu: Int?
    @AppStorage("mushafSize") private var size = 1.0
    @State private var line: [[Int]] = []      // [surah, ayah, start, end, first word] of the recitation playing
    @State private var lineId = ""
    @State private var followG = 0
    @State private var lastFollow = 0

    private var rv: String {
        let opts = ayah.options(1, 1).map(\.value)
        let p = store.ayahReciter.isEmpty ? (repo.data?.site.dailyReciter ?? "yasser") : store.ayahReciter
        return opts.contains(p) ? p : (opts.contains("yasser") ? "yasser" : opts.first ?? "yasser")
    }

    var body: some View {
        Group {
            if !ready { ProgressView().tint(c.gold).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { content }
        }
        .modifier(FollowMark())
        .task { if !ready { await Task.detached { MushafData.load() }.value; ready = true } }
        .onChange(of: page) { UserDefaults.standard.set($0, forKey: "mushafPage") }
        .onChange(of: ma.current) { g in if g > 0 { let p = MushafData.pageOf(g); if p != page { withAnimation { page = p } } } }
        .onDisappear { if ma.current != 0 { ma.stop() } }
        .task(id: player.current?.id ?? "") { await loadTimes() }
        .task(id: lineId) {
            // the mushaf follows the recitation playing in the app's player: the ayah is marked and the pages turn
            while !Task.isCancelled && !line.isEmpty {
                followG = follow(Int(player.currentTime * 1000))
                if followG > 0 && player.playing && followG != lastFollow {
                    lastFollow = followG; let p = MushafData.pageOf(followG); if p != page { withAnimation { page = p } }
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private var content: some View {
        let fg = MushafData.firstG(page), fs = MushafData.sa(fg).0
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { jump = true } label: {
                    HStack(spacing: 0) {
                        Text(tr("سورة {0}", Quran.surahs[fs - 1])).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(1)
                        Text(tr(" · ص {0} · ج {1}", page.ar, MushafData.juzOf(fg).ar)).font(F.plex(12.5, .medium)).foregroundStyle(c.muted).lineLimit(1)
                        Spacer(); SiteIcon(name: "chev-d", size: 20, color: c.gold)
                    }.padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(c.surface.opacity(0.6))).overlay(Capsule().stroke(c.line))
                }.buttonStyle(.plain)
                Chip(text: nil, icon: ma.current > 0 && ayah.playing ? "pause" : "play", on: ma.current > 0) {
                    if ma.current > 0 { if ayah.playing { ma.stop() } else { ma.play(ma.current, rv) } } else { player.pause(); ma.play(MushafData.firstG(page), rv) }
                }
                Chip(text: nil, icon: "bookmark", on: marks.contains(page)) {
                    if let i = marks.firstIndex(of: page) { marks.remove(at: i); ui.say(tr("أُزيلت العلامة")) } else { marks.append(page); ui.say(tr("حُفظت علامة على هذه الصفحة")) }
                    UserDefaults.standard.set(marks.sorted().map(String.init).joined(separator: ","), forKey: "mushafMarks")
                }
                Chip(text: nil, icon: "scroll") { tafsir = true }
            }.padding(.horizontal, 12).padding(.vertical, 6)
            // the reciter, always in sight
            HStack {
                let (rs, ra) = ma.current > 0 ? MushafData.sa(ma.current) : (fs, 1)
                ReciterButton(opts: ayah.options(rs, ra).map { RecChoice(value: $0.value, label: $0.label, img: repo.recImg($0.value, $0.label)) }, value: rv, label: tr("بصوت"), title: tr("القارئ في المصحف")) { v in
                    store.ayahReciter = v; if ma.current > 0 { ma.play(ma.current, v) }
                }
                Spacer()
            }.padding(.horizontal, 12).padding(.vertical, 2)
            if ma.current > 0 {
                let (ps, pa) = MushafData.sa(ma.current)
                HStack { Text("\(Quran.surahs[ps - 1]) · \(pa.ar)").font(F.amiri(17)).foregroundStyle(c.gold); Spacer(); Chip(text: nil, icon: "close") { ma.stop() } }.padding(.horizontal, 14).padding(.vertical, 2)
            }
            if !marks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(marks.sorted(), id: \.self) { m in Pill(title: tr("صفحة {0}", m.ar), on: m == page, icon: "bookmark") { withAnimation { page = m } } } }.padding(.horizontal, 12).padding(.vertical, 2)
                }
            }
            // pages: the next page is to the left, as in a printed mushaf
            TabView(selection: $page) {
                ForEach((1...604).reversed(), id: \.self) { p in
                    MushafPage(pg: p, size: size, hi: ma.current > 0 ? ma.current : (menu ?? followG)) { g in menu = g }
                        .modifier(PageFit(on: size <= 1.01))
                        .padding(.horizontal, 10).padding(.vertical, 8).tag(p)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 4) {
                Button(tr("أ−")) { size = max(1, size - 0.2) }.disabled(size <= 1).foregroundStyle(c.gold).frame(width: 44, height: 32)
                Text(tr("حجم الخط")).font(F.plex(11)).foregroundStyle(c.faint)
                Button(tr("أ+")) { size = min(2.6, size + 0.2) }.foregroundStyle(c.gold).frame(width: 44, height: 32)
            }.font(F.plex(15, .bold)).padding(.vertical, 2)
        }
        .bzSheet(item: Binding(get: { menu.map(IntBox.init(v:)) }, set: { menu = $0?.v })) { b in
            AyahMenu(g: b.v, page: page, seekMs: player.playing && ma.current == 0 ? trackStart(b.v) : nil,
                     onPlay: { menu = nil; player.pause(); ma.play(b.v, rv) },
                     onTrack: { ms in menu = nil; player.seek(max(0, Double(ms - 80) / 1000)); lastFollow = 0 },
                     onMark: { p in if !marks.contains(p) { marks.append(p) }; UserDefaults.standard.set(marks.sorted().map(String.init).joined(separator: ","), forKey: "mushafMarks"); ui.say(tr("حُفظت علامة على هذه الصفحة")); menu = nil })
                .presentationDetents([.medium, .large])
        }
        .bzSheet(isPresented: $jump) { MushafJump(page: page) { p in jump = false; page = p }.presentationDetents([.large]) }
        .bzSheet(isPresented: $tafsir) { PageTafsirSheet(page: page).presentationDetents([.medium, .large]) }
    }

    /// the ayah timings of the recitation playing now (its own, or the whole-Quran reciter's)
    private func loadTimes() async {
        line = []; lineId = ""
        guard let id = player.current?.id, let t = repo.track(id) else { return }
        var ay: [[Int]] = [], ws: [[[Int]]] = [], sn = t.surahNumber, extra: [[Int]] = []
        if id.hasPrefix("quran-") {
            let rid = id.replacingOccurrences(of: "^quran-(.+)-\\d+$", with: "$1", options: .regularExpression)
            if repo.data?.surahReciters.contains(where: { $0.id == rid }) == true, let tm = await repo.ayahTimes("sr:\(rid)", sn) { ay = tm.ayahs; ws = tm.words }
        } else if let tm = await repo.trackTimes(id) {
            ay = tm.ayahs; ws = tm.words; if (1...114).contains(tm.surah) { sn = tm.surah }
            // a recording of several surahs (a juz, a night's prayer): the surahs it goes on to and al-Fatiha of each rak'ah
            // are followed too (only the first surah was, and the mushaf stayed on another page)
            extra = tm.parts.flatMap { p in p.ayahs.enumerated().map { i, x in [p.surah, x[0], x[1], x.count > 2 ? x[2] : 0, p.words[safe: i]?.first?[safe: 1] ?? 0] } }
        }
        guard (1...114).contains(sn), !ay.isEmpty else {
            // no ayah timings: at least open its surah
            if (1...114).contains(t.surahNumber) && player.playing && ma.current == 0 && MushafData.sa(MushafData.firstG(page)).0 != t.surahNumber { page = Quran.surahPage[t.surahNumber - 1] }
            return
        }
        line = (ay.enumerated().map { i, x in [sn, x[0], x[1], x.count > 2 ? x[2] : 0, ws[safe: i]?.first?[safe: 1] ?? 0] } + extra)
            .filter { (1...114).contains($0[0]) && $0[1] >= 1 }.sorted { $0[2] < $1[2] }
        lineId = id
    }
    private func follow(_ pos: Int) -> Int {
        guard ma.current == 0, !line.isEmpty else { return 0 }
        if let l = line.last, l[3] > 0, pos > l[3] + 2000 { return 0 }
        var i = -1
        for (k, x) in line.enumerated() {
            let prev = k > 0 ? line[k - 1] : nil
            let go = max(x[2], x[4] > 0 ? x[4] - 250 : 0, prev != nil && prev![0] == x[0] && prev![3] > 0 ? prev![3] - 250 : 0)
            if go <= pos + 150 { i = k } else if x[2] > pos + 150 { break }
        }
        let h = line[max(0, i)]
        return MushafData.gid(h[0], max(1, min(Quran.ayahs[h[0] - 1], h[1])))
    }
    private func trackStart(_ g: Int) -> Int? {
        let (s0, a0) = MushafData.sa(g)
        let hits = line.filter { $0[0] == s0 && $0[1] == a0 }
        let pos = Int(player.currentTime * 1000)
        return (hits.first { $0[2] >= pos - 1000 } ?? hits.first)?[2]
    }
}

/// The whole page in sight, shaped like a printed page (1 : 1.55, as on the site): the 15 lines sit evenly and
/// close together, never spread out over a tall screen. Enlarged text scrolls instead.
private struct PageFit: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.aspectRatio(1 / 1.55, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: .infinity) } else { content }
    }
}

/// One printed page: header, the 15 lines justified edge to edge, page number. [hi]: the ayah being read or chosen.
struct MushafPage: View {
    let pg: Int; let size: Double; let hi: Int; let onAyah: (Int) -> Void
    @Environment(\.pal) private var c
    var body: some View {
        let lines = MushafData.pages[pg - 1]
        let fg = MushafData.firstG(pg), fs = MushafData.sa(fg).0
        let open = pg <= 2
        VStack(spacing: 0) {
            HStack {
                Text(Quran.surahs[fs - 1]).font(F.amiri(15)).foregroundStyle(c.gold)
                Spacer()
                Text(tr("الجزء {0} · الحزب {1}", MushafData.juzOf(fg).ar, MushafData.hizbOf(fg).ar)).font(F.plex(11)).foregroundStyle(c.muted)
            }.padding(.bottom, 4)
            GeometryReader { geo in
                let widths = lines.map { l -> CGFloat in if case .words(let s) = l { return MushafPage.width(s) } else { return 0 } }
                let widest = max(1, widths.max() ?? 1)
                let byW = 100 * (geo.size.width * 0.97) / widest
                let rowH = open ? geo.size.height / 9 : geo.size.height / 15
                let font = min(byW, rowH / 1.75) * size
                if size > 1.01 {
                    ScrollViewReader { sp in
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(Array(groups(lines).enumerated()), id: \.offset) { _, gp in
                                    switch gp {
                                    case .title(let s): title(s, font)
                                    case .basmala: Text(MushafData.basmala).font(.custom(MushafData.font, size: font)).foregroundStyle(c.text).frame(maxWidth: .infinity)
                                    case .words(let segs):
                                        FlowLayout(spacing: font * 0.3) {
                                            ForEach(Array(tokens(segs).enumerated()), id: \.offset) { _, t in word(t, font).id(t.first ? "a\(t.g)" : "w\(t.g).\(t.k)") }
                                        }
                                        .backgroundPreferenceValue(HiWords.self) { a in hiBand(a, font) }
                                    }
                                }
                            }.padding(.vertical, 6)
                        }
                        // text ids: a ForEach's own ids are its offsets (0, 1, 2 …), so a bare ayah number such as 45 also matched
                        // the 45th word of the page and the page jumped back up while reading along
                        .onChange(of: hi) { g in if g > 0 { withAnimation { sp.scrollTo("a\(g)", anchor: .center) } } }
                    }
                } else {
                    VStack(spacing: open ? 10 : 0) {
                        if open { Spacer(minLength: 0) }
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                            Group {
                                switch l {
                                case .title(let s): title(s, font)
                                case .basmala: Text(MushafData.basmala).font(.custom(MushafData.font, size: font)).foregroundStyle(c.text).lineLimit(1)
                                case .words(let segs):
                                    let short = widths[i] > 0 && widths[i] <= widest * 0.55
                                    HStack(spacing: open || short ? font * 0.28 : 0) {
                                        let toks = tokens(segs)
                                        ForEach(Array(toks.enumerated()), id: \.offset) { k, t in
                                            word(t, font)
                                            if !(open || short) && k < toks.count - 1 { Spacer(minLength: 0) }
                                        }
                                    }.frame(maxWidth: .infinity)
                                    .backgroundPreferenceValue(HiWords.self) { a in hiBand(a, font) }
                                }
                            }.frame(maxWidth: .infinity, maxHeight: open ? nil : .infinity)
                        }
                        if open { Spacer(minLength: 0) }
                    }
                }
            }
            Text(pg.ar).font(F.plex(12.5, .medium)).foregroundStyle(c.gold).padding(.horizontal, 12).padding(.vertical, 2).background(Capsule().fill(c.gold.opacity(0.12))).padding(.top, 4)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 20).fill(c.dark ? c.surface.opacity(0.85) : Color(hex: 0xFFFFFCF4)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(c.lineSoft))
    }
    struct Tok { let g: Int; let k: Int; let w: String; let mark: Bool; let first: Bool }
    private func tokens(_ segs: [MushafData.Seg]) -> [Tok] {
        segs.flatMap { sg -> [Tok] in
            var ws = sg.text.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            if sg.end { ws.append(MushafData.endMark(sg.g)) }
            return ws.enumerated().map { Tok(g: sg.g, k: $0.offset, w: $0.element, mark: sg.end && $0.offset == ws.count - 1, first: $0.offset == 0) }
        }
    }
    private func word(_ t: Tok, _ font: CGFloat) -> some View {
        // the ayah being read: gold words on a gold band (as on the site), the band reaching over the gaps between words
        // (the band itself is drawn once per line under the ayah's words — see hiBand — one piece, not a box per word)
        Text(t.w).font(.custom(MushafData.font, size: font)).foregroundStyle(t.g == hi ? c.gold2 : t.mark ? c.gold : c.text).lineLimit(1).fixedSize()
            .anchorPreference(key: HiWords.self, value: .bounds) { t.g == hi && hi > 0 ? [$0] : [] }
            .animation(.easeOut(duration: 0.35), value: t.g == hi)
            .contentShape(Rectangle()).onTapGesture { onAyah(t.g) }
    }
    /// the ayah being read: one gold band under its words on each line, reaching over the gaps between them
    private func hiBand(_ a: [Anchor<CGRect>], _ font: CGFloat) -> some View {
        GeometryReader { p in
            let rows = HiWords.rows(a.map { p[$0] }, font * 0.5)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                RoundedRectangle(cornerRadius: font * 0.32).fill(c.gold.opacity(0.22))
                    .frame(width: r.width + font * 0.44, height: r.height + font * 0.1).position(x: r.midX, y: r.midY)
            }
        }.animation(.easeOut(duration: 0.3), value: a.count)
    }
    private func title(_ s: Int, _ font: CGFloat) -> some View {
        HStack(spacing: 12) {
            LinearGradient(colors: [c.gold.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing).frame(height: 1)
            Text(tr("سورة {0}", Quran.surahs[s - 1])).font(F.amiri(font * 0.82)).foregroundStyle(c.gold).lineLimit(1).fixedSize()
            LinearGradient(colors: [.clear, c.gold.opacity(0.7)], startPoint: .leading, endPoint: .trailing).frame(height: 1)
        }
    }
    /// enlarged pages: the ayat flow and wrap between the titles
    private func groups(_ lines: [MushafData.Line]) -> [MushafData.Line] {
        var out: [MushafData.Line] = [], cur: [MushafData.Seg] = []
        for l in lines { if case .words(let s) = l { cur += s } else { if !cur.isEmpty { out.append(.words(cur)); cur = [] }; out.append(l) } }
        if !cur.isEmpty { out.append(.words(cur)) }
        return out
    }
    /// a printed line's width at size 100
    nonisolated(unsafe) private static var wcache: [String: CGFloat] = [:]
    static func width(_ s: [MushafData.Seg]) -> CGFloat {
        let str = s.map { $0.text + ($0.end ? " " + MushafData.endMark($0.g) : "") }.joined(separator: " ")
        if let w = wcache[str] { return w }
        let f = UIFont(name: MushafData.font, size: 100) ?? .systemFont(ofSize: 100)
        let w = (str as NSString).size(withAttributes: [.font: f]).width
        wcache[str] = w; return w
    }
}

/// Tapping an ayah: carry on the recitation from here, listen, tafsir, copy, share, bookmark.
struct AyahMenu: View {
    let g: Int; let page: Int; let seekMs: Int?
    let onPlay: () -> Void; let onTrack: (Int) -> Void; let onMark: (Int) -> Void
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var tafsir = false
    var body: some View {
        let (s, a) = MushafData.sa(g), text = MushafData.text(g)
        let cite = tr("﴿{0}﴾ [سورة {1}: {2}]", text, Quran.surahs[s - 1], a)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SheetHead(title: tr("سورة {0} — الآية {1}", Quran.surahs[s - 1], a.ar))
                Text(orn(text)).font(.custom(MushafData.font, size: 22)).foregroundStyle(c.text).lineSpacing(16).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.horizontal, 20)
                VStack(spacing: 8) {
                    if let ms = seekMs {
                        GoldButton(title: tr("أكمل التلاوة من هنا"), icon: "play") { onTrack(ms) }.frame(maxWidth: .infinity)
                        Chip(text: tr("استمع لهذه الآية بصوت قارئ المصحف"), icon: "play") { onPlay() }
                    } else { GoldButton(title: tr("استمع من هنا"), icon: "play") { onPlay() } }
                    HStack(spacing: 8) {
                        Chip(text: tr("التفسير"), icon: "scroll") { tafsir = true }.frame(maxWidth: .infinity)
                        Chip(text: tr("نسخ"), icon: "copy") { UIPasteboard.general.string = cite; ui.say(tr("نُسخت الآية")) }.frame(maxWidth: .infinity)
                    }
                    HStack(spacing: 8) {
                        Chip(text: tr("مشاركة"), icon: "share") { share(cite) }.frame(maxWidth: .infinity)
                        Chip(text: tr("علامة على الصفحة"), icon: "bookmark") { onMark(page) }.frame(maxWidth: .infinity)
                    }
                }.padding(20)
            }
        }
        .background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir)
        .onAppear { UserDefaults.standard.set(g, forKey: "mushafAyah") }
        .bzSheet(isPresented: $tafsir) { TafsirSheet(s: s, a: a, text: text).presentationDetents([.medium, .large]) }
    }
}

/// «انتقل إلى»: a surah, a juz or a page.
struct MushafJump: View {
    let page: Int; let go: (Int) -> Void
    @Environment(\.pal) private var c
    @State private var tab = 0
    @State private var num = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetHead(title: tr("انتقل إلى"))
            Seg(items: [tr("السورة"), tr("الجزء"), tr("الصفحة")], selected: tab) { tab = $0 }.padding(.horizontal, 20)
            switch tab {
            case 0:
                List(0..<114, id: \.self) { i in
                    Button { go(Quran.surahPage[i]) } label: {
                        HStack(spacing: 12) {
                            ZStack { Canvas { ctx, s in ctx.stroke(star8(CGPoint(x: s.width / 2, y: s.height / 2), s.width / 2 - 1), with: .color(c.gold.opacity(0.6)), lineWidth: 1) }; Text((i + 1).ar).font(F.plex(12, .bold)).foregroundStyle(c.gold) }.frame(width: 38, height: 38)
                            Text(tr("سورة {0}", Quran.surahs[i])).font(F.amiri(19)).foregroundStyle(c.text)
                            Spacer(); Text(tr("ص {0}", Quran.surahPage[i].ar)).font(F.plex(13)).foregroundStyle(c.muted)
                        }
                    }.listRowBackground(Color.clear)
                }.listStyle(.plain).scrollContentBackground(.hidden)
            case 1:
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(0..<30, id: \.self) { j in
                            let on = Quran.juzOfPage(page) == j + 1
                            Button { go(Quran.juzPage[j]) } label: {
                                Text((j + 1).ar).font(F.plex(14, .semibold)).foregroundStyle(on ? c.onGold : c.text).frame(maxWidth: .infinity).frame(height: 50)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(on ? c.gold : c.surface)).overlay(RoundedRectangle(cornerRadius: 14).stroke(c.line))
                            }.buttonStyle(Press())
                        }
                    }.padding(.horizontal, 16)
                }
            default:
                HStack(spacing: 10) {
                    TextField(tr("رقم الصفحة (١–٦٠٤)"), text: Binding(get: { num }, set: { num = String($0.filter(\.isNumber).prefix(3)) })).keyboardType(.numberPad).font(F.plex(15))
                        .padding(12).background(RoundedRectangle(cornerRadius: 18).fill(c.surface.opacity(0.6))).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.line))
                    GoldButton(title: tr("انتقل")) { if let p = Int(num), (1...604).contains(p) { go(p) } }
                }.padding(20)
                Spacer()
            }
        }
        .background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir)
    }
}

/// «تفسير الصفحة»: every ayah on the page with its tafsir.
struct PageTafsirSheet: View {
    let page: Int
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    @AppStorage("tafsirEd") private var ed = L.quran[L.code]?.0 ?? "ar.muyassar"
    @State private var rows: [(Int, Int, String, String)]?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SheetHead(title: tr("تفسير الصفحة {0}", page.ar))
                Seg(items: TafsirSheet.editions.map(\.1), selected: TafsirSheet.editions.firstIndex { $0.0 == ed } ?? 0) { ed = TafsirSheet.editions[$0].0 }.padding(.horizontal, 20)
                if let rows {
                    if rows.isEmpty { Text(tr("تعذّر تحميل التفسير الآن.")).font(F.plex(14)).foregroundStyle(c.muted).padding(20) }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        Panel(pad: 14, lattice: false) {
                            Text(orn(r.2)).font(.custom(MushafData.font, size: 19)).foregroundStyle(c.text).lineSpacing(12)
                            Text("\(Quran.surahs[r.0 - 1]) \(r.1.ar)").font(F.plex(12.5, .medium)).foregroundStyle(c.gold)
                            Text(r.3).font(!ed.hasPrefix("ar.") ? F.plex(16) : F.amiri(17, bold: false)).foregroundStyle(c.text).lineSpacing(8).padding(.top, 6)
                                .environment(\.layoutDirection, !ed.hasPrefix("ar.") ? (["ur.jalandhry", "fa.khorramdel"].contains(ed) ? .rightToLeft : .leftToRight) : .rightToLeft).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.horizontal, 20).padding(.vertical, 5)
                    }
                } else { ProgressView().tint(c.gold).frame(maxWidth: .infinity).padding(40) }
            }.padding(.bottom, 20)
        }
        .background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir)
        .task(id: ed) {
            rows = nil
            let gs = MushafData.ayahsOn(page)
            var bySurah: [Int: [Int: String]] = [:]
            for s in Set(gs.map { MushafData.sa($0).0 }) { bySurah[s] = await repo.tafsir(s, edition: ed) }
            rows = gs.map { g in let (s, a) = MushafData.sa(g); return (s, a, MushafData.text(g), bySurah[s]?[a] ?? "") }
        }
    }
}

/// One button with the chosen reciter's photo; it opens a sheet of every reciter.
struct ReciterButton: View {
    let opts: [RecChoice]; let value: String; var label: String? = nil; var title = tr("اختر القارئ"); let pick: (String) -> Void
    @Environment(\.pal) private var c
    @State private var open = false
    @State private var q = ""
    var body: some View {
        let cur = opts.first { $0.value == value } ?? opts.first
        Button { open = true } label: {
            HStack(spacing: 8) {
                Avatar2(img: cur?.img, name: cur?.label ?? "", size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    if let label { Text(label).font(F.plex(11)).foregroundStyle(c.muted) }
                    Text(noSheikh(cur?.label ?? "")).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(1)
                }
                SiteIcon(name: "chev-d", size: 16, color: c.muted)
            }.padding(.leading, 5).padding(.trailing, 8).padding(.vertical, 4).background(Capsule().fill(c.surface.opacity(0.6))).overlay(Capsule().stroke(c.line))
        }.buttonStyle(.plain)
        .bzSheet(isPresented: $open) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    SheetHead(title: title)
                    if opts.count > 8 { SearchField(text: $q, hint: tr("ابحث باسم القارئ")).padding(.horizontal, 16) }
                    let shown = opts.filter { q.isEmpty || $0.label.contains(q.trimmingCharacters(in: .whitespaces)) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                        ForEach(shown, id: \.value) { o in
                            Button { pick(o.value); open = false } label: {
                                VStack(spacing: 5) {
                                    Avatar2(img: o.img, name: o.label, size: 56, ring: o.value == value)
                                    Text(noSheikh(o.label)).font(F.plex(12, o.value == value ? .bold : .regular)).foregroundStyle(o.value == value ? c.text : c.muted).lineLimit(2).multilineTextAlignment(.center)
                                }.padding(.vertical, 4)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 12)
                }.padding(.bottom, 20)
            }.background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir).presentationDetents([.medium, .large])
        }
    }
}


/// Marks a page that lights the words with the voice while it is on screen (the player then keeps exact timing).
struct FollowMark: ViewModifier {
    /// a pushed page (not a tab) counts whenever it is shown
    var pushed = false
    @Environment(\.tabActive) private var tabOn
    private var active: Bool { pushed || tabOn }
    @State private var on = false
    private func set(_ v: Bool) { if v != on { on = v; AudioPlayer.shared.follow += v ? 1 : -1 } }
    func body(content: Content) -> some View {
        content.onAppear { set(active) }.onDisappear { set(false) }.onChange(of: active) { set($0) }
    }
}

/// Where the words of the ayah being read are on a line (or on each wrapped line of an enlarged page).
struct HiWords: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) { value += nextValue() }
    /// the words' boxes joined into one box per row
    static func rows(_ rs: [CGRect], _ tol: CGFloat) -> [CGRect] {
        var out: [CGRect] = []
        for r in rs.sorted(by: { $0.midY < $1.midY }) {
            if let i = out.firstIndex(where: { abs($0.midY - r.midY) < tol }) { out[i] = out[i].union(r) } else { out.append(r) }
        }
        return out
    }
}
