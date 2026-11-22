import SwiftUI
import UIKit

/// One recitation the reader can follow: one of the site's analysed recitations, or a whole-surah reciter.
struct RSrc: Hashable { let kind: String, id: String, label: String; var from = 0, to = 0; var name = "", title = "", img = "" }

extension Repo {
    func readSources(_ sn: Int) -> [RSrc] {
        guard let d = data else { return [] }
        var out: [RSrc] = []
        for (id, v) in d.readableTracks.sorted(by: { $0.key < $1.key }) where v.count >= 3 && v[0] == sn {
            guard let t = track(id) else { continue }
            let r = reciter(t.reciterId)
            out.append(RSrc(kind: "track", id: id, label: "\(r?.name ?? "") — \(t.title)", from: v[1], to: v[2], name: r?.name ?? "", title: t.title, img: t.image.isEmpty ? (r?.image ?? "") : t.image))
        }
        for r in d.surahReciters where (d.readableSr[r.id] ?? []).contains(sn) {
            out.append(RSrc(kind: "sr", id: r.id, label: r.name, name: r.name, title: tr("المصحف المرتّل"), img: quranRec(r.id).map { quranImage($0) } ?? ""))
        }
        return out
    }
    func readSurahs() -> [Int] {
        guard let d = data else { return [] }
        return Array(Set(d.readableTracks.values.filter { $0.count >= 3 }.map { $0[0] } + d.readableSr.values.flatMap { $0 })).sorted()
    }
}
func rangeText(_ a: Int, _ b: Int) -> String { a == b ? tr("الآية {0}", a.ar) : tr("الآيات {0} – {1}", a.ar, b.ar) }
func noSheikh(_ n: String) -> String { n.replacingOccurrences(of: "^\\s*الشيخ\\s+", with: "", options: .regularExpression) }

/// A menu shown as a small labelled field.
struct OptMenu<V: Hashable>: View {
    let label: String; let value: V; let opts: [(V, String)]; let pick: (V) -> Void
    @Environment(\.pal) private var c
    var body: some View {
        Menu { ForEach(opts, id: \.0) { o in Button { pick(o.0) } label: { if o.0 == value { Label(o.1, systemImage: "checkmark") } else { Text(o.1) } } } } label: {
            HStack(spacing: 6) {
                if !label.isEmpty { Text(label).font(F.plex(11.5)).foregroundStyle(c.muted) }
                Text(opts.first { $0.0 == value }?.1 ?? "").font(F.plex(13, .medium)).foregroundStyle(c.text).lineLimit(1)
                Ico(name: "chevron.down", size: 12.0).foregroundStyle(c.gold)
            }.padding(.horizontal, 11).padding(.vertical, 7).background(Capsule().fill(c.surface.opacity(0.7))).overlay(Capsule().stroke(c.line))
        }
    }
}

/// Index of «اقرأ واستمع واحفظ»: continue, the site's analysed recitations (filtered by reciter), and the recited mushaf.
struct ReadIndexView: View {
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.pal) private var c
    @State private var who = ""
    @State private var rec = ""
    @State private var q = ""
    var body: some View {
        let d = repo.data
        let own: [(String, Track, Int, Int, Int)] = (d?.readableTracks ?? [:]).compactMap { id, v in v.count >= 3 ? repo.track(id).map { (id, $0, v[0], v[1], v[2]) } : nil }.sorted { ($0.2, $0.3) < ($1.2, $1.3) }
        var cnt: [String: Int] = [:]; own.forEach { cnt[$0.1.reciterId, default: 0] += 1 }
        let whos = cnt.sorted { $0.value > $1.value }.compactMap { repo.reciter($0.key) }
        let shown = own.filter { who.isEmpty || $0.1.reciterId == who }
        let srs = (d?.surahReciters ?? []).map { ($0, d?.readableSr[$0.id] ?? []) }.filter { !$0.1.isEmpty }
        let cur = srs.first { $0.0.id == rec } ?? srs.first
        let last = Store.shared.str("readLast")
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if last.contains("|") {
                    let p = (last.components(separatedBy: "|") + ["", "", ""])
                    Button { if let r = Route.readPath(p[0]) { ui.path.append(r) } } label: {
                        HStack(spacing: 12) {
                            Ico(name: "play.circle.fill", size: 38.4).foregroundStyle(c.onGold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tr("تابع من حيث توقفت")).font(F.plex(12, .medium)); Text(p[1]).font(F.plex(15, .bold)); Text(p[2]).font(F.plex(12)).opacity(0.8).lineLimit(1)
                            }.foregroundStyle(c.onGold)
                            Spacer(); Ico(name: "chevron.left", size: 20).foregroundStyle(c.onGold)
                        }.padding(16).background(RoundedRectangle(cornerRadius: 20).fill(c.goldGradient))
                    }.buttonStyle(Press()).padding(.horizontal, 16)
                }
                if !own.isEmpty {
                    head(tr("من تلاوات الموقع"), tr("{0} تلاوة تضيء كلمةً كلمة مع الصوت", own.count.ar))
                    if whos.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                avatarChip(nil, tr("الكل"), who.isEmpty) { who = "" }
                                ForEach(whos) { r in avatarChip(r.image, noSheikh(r.name), who == r.id) { who = r.id } }
                            }.padding(.horizontal, 16)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(shown, id: \.0) { x in card(x.1, x.2, x.3, x.4, player.current?.id == x.1.id) { ui.path.append(.read("track", x.0)) } }
                        }.padding(.horizontal, 16)
                    }
                }
                if let cur {
                    head(tr("المصحف المرتّل"), tr("{0} — {1} سورة", noSheikh(cur.0.name), cur.1.count.ar))
                    if srs.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(srs, id: \.0.id) { r, l in
                                    let on = r.id == cur.0.id
                                    Button { rec = r.id } label: {
                                        VStack(alignment: .leading, spacing: 1) { Text(nm(noSheikh(r.name))).font(F.plex(13, .semibold)).foregroundStyle(c.text).lineLimit(1); Text(l.count >= 114 ? tr("المصحف كاملًا") : tr("{0} سورة", l.count.ar)).font(F.plex(11)).foregroundStyle(c.muted) }
                                            .padding(.horizontal, 14).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 16).fill(on ? c.gold.opacity(0.12) : c.surface)).overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? c.gold : c.lineSoft))
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.horizontal, 16)
                        }
                    }
                    SearchField(text: $q, hint: tr("ابحث باسم السورة أو رقمها")).padding(.horizontal, 16)
                    let lastSn: Int? = {
                        let p = last.components(separatedBy: "|").first ?? ""
                        guard p.hasSuffix("/" + cur.0.id), let n = Int(p.components(separatedBy: "/").dropFirst().first ?? "") else { return nil }
                        return n
                    }()
                    let list = cur.1.filter { q.isEmpty || QuranMeta.norm(Quran.surahs[$0 - 1]).contains(QuranMeta.norm(q)) || "\($0)" == q.trimmingCharacters(in: .whitespaces) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(list, id: \.self) { sn in
                            Button { ui.path.append(.read("\(sn)", cur.0.id)) } label: {
                                VStack(spacing: 1) {
                                    Text(sn.ar).font(F.plex(11.5)).foregroundStyle(sn == lastSn ? c.gold : c.faint)
                                    Text(Quran.surahs[sn - 1]).font(F.amiri(18)).foregroundStyle(c.text).lineLimit(1).minimumScaleFactor(0.7)
                                    Text(tr("{0} آية", Quran.ayahs[sn - 1].ar)).font(F.plex(11)).foregroundStyle(c.muted)
                                }.frame(maxWidth: .infinity).padding(.vertical, 9).background(RoundedRectangle(cornerRadius: 14).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 14).stroke(sn == lastSn ? c.gold : c.lineSoft))
                            }.buttonStyle(Press())
                        }
                    }.padding(.horizontal, 16)
                }
                if own.isEmpty && cur == nil { Empty(text: tr("لا توجد تلاوات جاهزة للمتابعة بعد."), icon: "waveform") }
            }.padding(.vertical, 12).padding(.bottom, 20)
        }
        .navigationTitle(tr("اقرأ واستمع واحفظ")).navigationBarTitleDisplayMode(.inline)
    }
    private func head(_ t: String, _ k: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(t).font(F.amiri(22)).foregroundStyle(c.text); Text(k).font(F.plex(12)).foregroundStyle(c.gold) }.padding(.horizontal, 16).padding(.top, 6)
    }
    private func avatarChip(_ img: String?, _ name: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            VStack(spacing: 5) {
                ZStack { if let img { RemoteImage(raw: img) } else { c.surface3; Ico(name: "person.3.fill", size: 20).foregroundStyle(c.text) } }
                    .frame(width: 56, height: 56).clipShape(Circle()).overlay(Circle().stroke(on ? c.gold : c.lineSoft, lineWidth: on ? 2 : 1))
                Text(name).font(F.plex(12, on ? .bold : .regular)).foregroundStyle(on ? c.text : c.muted).lineLimit(2).multilineTextAlignment(.center).frame(width: 70)
            }
        }.buttonStyle(.plain)
    }
    private func card(_ t: Track, _ sn: Int, _ a: Int, _ b: Int, _ cur: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .bottom) {
                    RemoteImage(raw: t.image.isEmpty ? repo.reciter(t.reciterId)?.image : t.image)
                    LinearGradient(colors: [.clear, Color.black.opacity(0.15), Color.black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 1) { Text(rangeText(a, b)).font(F.plex(11.5, .semibold)).foregroundStyle(.white.opacity(0.8)); Text(tr("سورة {0}", Quran.surahs[sn - 1])).font(F.amiri(18)).foregroundStyle(.white).lineLimit(2) }
                        Spacer(minLength: 4)
                        Ico(name: "play.fill", size: 15.6).foregroundStyle(c.onGold).frame(width: 34, height: 34).background(Circle().fill(c.gold))
                    }.padding(10)
                }.frame(width: 150, height: 180).clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(cur ? c.gold : .clear, lineWidth: 2))
                Text(repo.reciter(t.reciterId)?.shown ?? "").font(F.plex(13, .semibold)).foregroundStyle(c.text).lineLimit(1).frame(width: 150, alignment: .leading)
            }
        }.buttonStyle(Press())
    }
}

extension Route {
    /// "read/track/<id>" or "read/<surah>/<reciter>"
    static func readPath(_ p: String) -> Route? {
        let x = p.components(separatedBy: "/"); guard x.count >= 3, x[0] == "read" else { return nil }
        return .read(x[1], x.dropFirst(2).joined(separator: "/"))
    }
}

/// One ayah of the reader: its time span, words and the start time of each word.
struct RItem { let n: Int, st: Int, en: Int; let toks: [String]; let wt: [Int]?; let w0: Int }

/// Start time of each displayed word from the model's word timings (same as the site's wordStarts).
func readWordStarts(_ toks: [String], _ wt: [[Int]]) -> [Int]? {
    if wt.isEmpty { return nil }
    func nLet(_ t: String) -> Int { t.unicodeScalars.filter { (0x621...0x63A).contains($0.value) || (0x641...0x64A).contains($0.value) || $0.value == 0x671 }.count }
    let total = max(1, toks.reduce(0) { $0 + nLet($1) })
    var acc = 0; var prev: Int?
    return toks.map { t in
        let f = Double(acc) / Double(total) * 1000; acc += nLet(t)
        if nLet(t) == 0, let p = prev { return p }
        var k = 0; while k + 1 < wt.count && Double(wt[k + 1][0]) <= f + 8 { k += 1 }
        var ms = Double(wt[k][1])
        if k + 1 < wt.count && f > Double(wt[k][0]) {
            let f0 = Double(wt[k][0]), m0 = Double(wt[k][1]), f1 = Double(wt[k + 1][0]), m1 = Double(wt[k + 1][1])
            ms = m0 + (m1 - m0) * min(1, (f - f0) / max(1, f1 - f0))
        }
        let v = Int(ms - 60); prev = v; return v
    }
}

/// «اقرأ واستمع واحفظ»: the ayahs light up word by word with the recitation; memorisation mode repeats and hides words.
/// The recitation plays in the app's player, so it goes on when the page is left.
struct ReadView: View {
    let a: String, b: String
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.pal) private var c
    @State private var items: [RItem]?
    @State private var failed = false
    @State private var pos = -1
    @State private var size: CGFloat = 1
    @AppStorage("readWords") private var words = true
    @AppStorage("readFollow") private var follow = true
    @State private var hifz = false
    @State private var from = 1
    @State private var to = 5
    @AppStorage("readRepA") private var repA = 3
    @AppStorage("readRepR") private var repR = 0
    @State private var hide = "none"
    @State private var rep = 0
    @State private var round = 0
    @State private var hcur = -1
    @State private var peek = Set<Int>()
    @State private var lastUser = Date.distantPast
    @State private var logged = -1
    @State private var whoOpen = false
    @State private var scrollTo: Int?

    private var sn: Int { a == "track" ? (repo.data?.readableTracks[b]?.first ?? 0) : (Int(a) ?? 0) }
    private var src: RSrc? {
        let all = repo.readSources(sn)
        return a == "track" ? all.first { $0.kind == "track" && $0.id == b } : (all.first { $0.kind == "sr" && $0.id == b } ?? all.first)
    }
    private var tid: String { guard let s = src else { return "" }; return s.kind == "track" ? (Repo.partBase(s.id) ?? s.id) : "quran-\(s.id)-\(sn)" }
    private var track: Track? { repo.track(tid) }
    private var mine: Bool { player.current?.id == tid && !tid.isEmpty }
    private var playing: Bool { mine && player.playing }
    private var path: String { guard let s = src else { return "" }; return s.kind == "track" ? "read/track/\(s.id)" : "read/\(sn)/\(s.id)" }

    var body: some View {
        if let src, sn > 0 { content(src).modifier(FollowMark(pushed: true)) }
        else { Empty(text: tr("تعذّر العثور على هذه التلاوة."), icon: "waveform").navigationTitle(tr("اقرأ واستمع واحفظ")) }
    }

    private func rangeIdx() -> (Int, Int) {
        guard let l = items else { return (0, 0) }
        var x = l.firstIndex { $0.n == from } ?? 0, y = l.firstIndex { $0.n == to } ?? 0
        if y < x { swap(&x, &y) }; return (x, y)
    }
    private func seekAyah(_ i: Int, play: Bool = false) {
        guard let it = items?[safe: i], let t = track else { return }
        let at = Double(max(0, it.st)) / 1000
        if player.current?.id == tid { player.seek(at); if play && !player.playing { player.toggle() } }
        else if play { player.play(t, in: [t], startAt: at) }
        hcur = i; pos = Int(at * 1000)
    }
    /// the ayah heard now: marked when its voice starts (its first word), not in the pause before it
    private var idx: Int { idxAt(pos) }
    private func idxAt(_ pos: Int) -> Int {
        guard let l = items, pos >= 0 else { return -1 }
        var k = -1
        for j in l.indices {
            let x = l[j]; let go = max(x.st, x.w0 > 0 ? x.w0 - 250 : 0, j > 0 ? l[j - 1].en - 250 : 0)
            if go <= pos + 120 { k = j } else if x.st > pos + 120 { break }
        }
        return k < 0 && !l.isEmpty ? 0 : k
    }
    private func wcur(_ i: Int) -> Int {
        wcurAt(i, pos)
    }
    private func wcurAt(_ i: Int, _ pos: Int) -> Int {
        guard words, let w = items?[safe: i]?.wt else { return -1 }
        var k = -1; for j in w.indices where pos >= w[j] { k = j }; return k
    }
    private func hidden(_ i: Int, _ k: Int, _ cur: Int, _ wc: Int) -> Bool {
        switch hide {
        case "first": return k > 0
        case "all": return !peek.contains(i << 20 | k)
        case "until": return i > cur || (i == cur && wc >= 0 && k > wc)
        case "grow": return (k * 7 + i * 3) % max(1, repA) < rep
        default: return false
        }
    }
    private func playPause() {
        guard let t = track, let src else { return }
        if playing { player.pause(); return }
        let (x, y) = rangeIdx()
        if hifz && (hcur < 0 || !(x...y).contains(hcur)) { seekAyah(x, play: true) }
        else if mine { player.toggle() }
        else if src.kind == "track" && src.id != tid { seekAyah(0, play: true) }
        else { player.play(t, in: [t], startAt: 0) }
    }

    private func load(_ src: RSrc) async {
        items = nil; failed = false
        var ay: [[Int]] = [], ws: [[[Int]]] = []
        if src.kind == "track" { if let tm = await repo.trackTimes(src.id) { ay = tm.ayahs; ws = tm.words } }
        else if let tm = await repo.ayahTimes("sr:\(src.id)", sn) { ay = tm.ayahs; ws = tm.words }
        guard !ay.isEmpty, let text = await repo.surahText(sn), track != nil else { failed = true; return }
        let l: [RItem] = ay.enumerated().compactMap { i, v in
            guard v.count >= 3, v[0] >= 1, v[0] <= text.count else { return nil }
            let toks = ayahClean(sn, v[0], text[v[0] - 1]).split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let w = ws[safe: i] ?? []
            return RItem(n: v[0], st: v[1], en: v[2], toks: toks, wt: readWordStarts(toks, w), w0: w.first?[safe: 1] ?? 0)
        }
        if l.isEmpty { failed = true; return }
        items = l; from = l[0].n; to = l[min(l.count - 1, 4)].n
    }

    private func content(_ src: RSrc) -> some View {
        let cur = idx, wc = wcur(cur)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("سورة {0}", Quran.surahs[sn - 1])).font(F.amiri(28)).foregroundStyle(c.text)
                HStack(spacing: 8) {
                    Button { whoOpen = true } label: {
                        HStack(spacing: 8) {
                            RemoteImage(raw: src.img).frame(width: 32, height: 32).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 0) {
                                Text(noSheikh(src.name)).font(F.plex(13, .semibold)).foregroundStyle(c.text).lineLimit(1)
                                Text(src.kind == "track" ? rangeText(src.from, src.to) : tr("المصحف المرتّل")).font(F.plex(11)).foregroundStyle(c.muted).lineLimit(1)
                            }
                            Ico(name: "chevron.down", size: 13.2).foregroundStyle(c.muted)
                        }.padding(.leading, 5).padding(.trailing, 10).padding(.vertical, 4).background(Capsule().fill(c.surface.opacity(0.6))).overlay(Capsule().stroke(c.line))
                    }.buttonStyle(.plain)
                    OptMenu(label: "", value: sn, opts: repo.readSurahs().map { ($0, "\($0.ar) \(Quran.surahs[$0 - 1])") }) { s in if s != sn { ui.path.removeLast(); ui.path.append(.read("\(s)", "")) } }
                }
                FlowLayout(spacing: 6) {
                    Pill(title: playing ? tr("إيقاف") : tr("استمع"), on: true) { playPause() }
                    Pill(title: tr("تتبّع الكلمة"), on: words) { words.toggle() }
                    Pill(title: tr("تمرير تلقائي"), on: follow) { follow.toggle() }
                    Pill(title: tr("وضع الحفظ"), on: hifz) { hifz.toggle(); rep = 0; round = 0 }
                    Pill(title: tr("أ−"), on: false) { size = max(0.7, size - 0.1) }
                    Pill(title: tr("أ+"), on: false) { size = min(1.8, size + 0.1) }
                }
                if hifz, let its = items {
                    let ns = its.map { ($0.n, $0.n.ar) }
                    VStack(alignment: .leading, spacing: 6) {
                        FlowLayout(spacing: 6) {
                            OptMenu(label: tr("من"), value: from, opts: ns) { from = $0; rep = 0; round = 0 }
                            OptMenu(label: tr("إلى"), value: to, opts: ns) { to = $0; rep = 0; round = 0 }
                            OptMenu(label: tr("تكرار كل آية"), value: repA, opts: [(1, tr("مرة")), (2, tr("مرتين")), (3, tr("٣ مرات")), (5, tr("٥ مرات")), (10, tr("١٠ مرات"))]) { repA = $0; rep = 0 }
                            OptMenu(label: tr("تكرار المقطع"), value: repR, opts: [(1, tr("مرة")), (2, tr("مرتين")), (3, tr("٣ مرات")), (0, tr("بلا توقف"))]) { repR = $0; round = 0 }
                            OptMenu(label: tr("إخفاء الكلمات"), value: hide, opts: [("none", tr("إظهار الكل")), ("until", tr("إخفاء حتى تُقرأ")), ("first", tr("أول كلمة فقط")), ("all", tr("إخفاء الكل (المس للإظهار)")), ("grow", tr("إخفاء يزيد مع كل تكرار"))]) { hide = $0; peek = [] }
                        }
                        let (x, y) = rangeIdx()
                        if let it = its[safe: hcur], (x...y).contains(hcur) {
                            Text(tr("الآية {0} — التكرار {1} من {2}", it.n.ar, (rep + 1).ar, repA.ar) + (repR != 1 ? tr(" · الجولة {0}{1}", (round + 1).ar, repR != 0 ? " من \(repR.ar)" : "") : "")).font(F.plex(12.5, .medium)).foregroundStyle(c.gold)
                        }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 16).fill(c.surface2))
                }
            }.padding(.horizontal, 14).padding(.vertical, 6)
            ZStack {
                if let its = items {
                    ReadText(items: its, sn: sn, cur: cur, wcur: wc, words: words, size: size, scrollTo: follow && playing && Date().timeIntervalSince(lastUser) > 4 ? cur : nil,
                             hidden: { i, k in hidden(i, k, cur, wc) }, pal: c,
                             onTap: { i, k in
                                 if hide == "all" && k >= 0 { let key = i << 20 | k; if peek.contains(key) { peek.remove(key) } else { peek.insert(key) }; return }
                                 rep = 0; seekAyah(i, play: true)
                             }, onUser: { lastUser = Date() })
                } else if failed { Text(tr("تعذّر تحميل التلاوة الآن. حاول مرة أخرى.")).font(F.plex(14)).foregroundStyle(c.muted) }
                else { ProgressView().tint(c.gold) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(tr("اقرأ واستمع واحفظ")).navigationBarTitleDisplayMode(.inline)
        .task(id: src) { await load(src) }
        .task(id: tid) {
            while !Task.isCancelled {
                let m = player.current?.id == tid
                let pl = m && player.playing
                let np = m ? Int(player.currentTime * 1000) : -1
                // the screen redraws only when the lit ayah or word changes (not 25 times a second)
                let ni = idxAt(np), oi = idxAt(pos)
                if ni != oi || wcurAt(ni, np) != wcurAt(oi, pos) || (np < 0) != (pos < 0) { pos = np }
                if pl && hifz, let l = items, hcur >= 0 {
                    let pos = np
                    let (x, y) = rangeIdx()
                    // the listener moved the bar (or the lock screen) himself: follow him, never pull him back to the ayah
                    // being repeated (it jumped back to it from wherever he went)
                    let st0 = l[hcur].st, en0 = hcur + 1 < l.count ? max(l[hcur].en, l[hcur + 1].st) : l[hcur].en
                    if pos >= 0 && (pos < st0 - 1500 || pos > en0 + 2500) { hcur = idxAt(pos); rep = 0 }
                    else if (x...y).contains(hcur) {
                        let it = l[hcur]; let nextSt = hcur + 1 < l.count ? l[hcur + 1].st : Int.max
                        if pos >= min(it.en, nextSt == Int.max ? Int.max : nextSt + 150) {
                            if rep + 1 < repA { rep += 1; seekAyah(hcur) }
                            else if hcur < y { rep = 0; seekAyah(hcur + 1) }
                            else { rep = 0; round += 1; if repR != 0 && round >= repR { player.pause(); round = 0 }; seekAyah(x) }
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: pl ? 40_000_000 : 250_000_000)
            }
        }
        .onChange(of: cur) { i in
            guard let it = items?[safe: i] else { return }
            if mine { player.nowLabel = (tid, tr("سورة {0} · الآية {1}", Quran.surahs[sn - 1], it.n.ar)) }
            if playing && i != logged {
                logged = i
                Store.shared.set("readLast", tr("{0}|سورة {1} — الآية {2}|{3}", path, Quran.surahs[sn - 1], it.n.ar, src.name.isEmpty ? src.label : src.name))
                repo.event("ayah", ["s": "\(sn)", "a": "\(it.n)"])
            }
        }
        .onDisappear { if player.nowLabel?.0 == tid { player.nowLabel = nil } }
        .bzSheet(isPresented: $whoOpen) {
            MenuSheet(title: tr("اختر التلاوة")) {
                ForEach(repo.readSources(sn), id: \.self) { x in
                    let on = x.kind == src.kind && x.id == src.id
                    Button {
                        whoOpen = false
                        if !on { ui.path.removeLast(); ui.path.append(x.kind == "track" ? .read("track", x.id) : .read("\(sn)", x.id)) }
                    } label: {
                        HStack(spacing: 12) {
                            RemoteImage(raw: x.img).frame(width: 46, height: 46).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(nm(x.name)).font(F.plex(14.5, .bold)).foregroundStyle(c.text).lineLimit(1)
                                Text(x.kind == "track" ? "\(x.title) · \(rangeText(x.from, x.to))" : tr("المصحف المرتّل — السورة كاملة")).font(F.plex(12)).foregroundStyle(c.muted).lineLimit(2)
                            }
                            Spacer(); if on { Ico(name: "checkmark", size: 20).foregroundStyle(c.gold) }
                        }.padding(10).background(RoundedRectangle(cornerRadius: 14).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? c.gold : c.lineSoft))
                    }.buttonStyle(.plain).padding(.horizontal, 14)
                }
            }.presentationDetents([.medium, .large])
        }
    }
}


/// The reader's text: one justified right-to-left block in the Quran font; a tap on a word reports (ayah, word), a tap on
/// the ayah number (ayah, -1). Rebuilt only when what it shows changes.
struct ReadText: UIViewRepresentable {
    let items: [RItem]; let sn: Int; let cur: Int; let wcur: Int; let words: Bool; let size: CGFloat; let scrollTo: Int?
    let hidden: (Int, Int) -> Bool; let pal: Palette
    let onTap: (Int, Int) -> Void; let onUser: () -> Void
    static let key = NSAttributedString.Key("bzWord")

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false; v.isSelectable = false; v.backgroundColor = .clear
        v.textContainerInset = UIEdgeInsets(top: 10, left: 14, bottom: 60, right: 14)
        v.semanticContentAttribute = .forceRightToLeft
        v.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coord.tap(_:))))
        v.delegate = context.coordinator
        return v
    }
    func makeCoordinator() -> Coord { Coord() }
    func updateUIView(_ v: UITextView, context: Context) {
        let co = context.coordinator; co.parent = self
        var sig = Hasher(); sig.combine(items.count); sig.combine(items.first?.n); sig.combine(cur); sig.combine(wcur); sig.combine(words); sig.combine(size); sig.combine(pal.key)
        for i in items.indices { for k in items[i].toks.indices where hidden(i, k) { sig.combine(i << 20 | k) } }
        let s = sig.finalize()
        if s != co.sig {
            co.sig = s
            let off = v.contentOffset
            let (str, offs) = build(); co.offsets = offs
            v.attributedText = str
            v.layoutIfNeeded(); v.setContentOffset(off, animated: false)
        }
        if let i = scrollTo, i != co.scrolled, let o = co.offsets[safe: i] {
            co.scrolled = i
            let r = v.layoutManager.boundingRect(forGlyphRange: v.layoutManager.glyphRange(forCharacterRange: NSRange(location: o, length: 1), actualCharacterRange: nil), in: v.textContainer)
            let y = max(0, min(r.minY + v.textContainerInset.top - 160, v.contentSize.height - v.bounds.height))
            v.setContentOffset(CGPoint(x: 0, y: y), animated: true)
        }
        if scrollTo == nil { co.scrolled = -1 }
    }
    /// the number at an ayah's end in right-to-left text: ﴿ then the number then ﴾, no direction marks (with them the
    /// brackets came out facing away from the number, and in the surah page the number went to the start of the line)
    static func mark(_ n: String) -> String { "\u{FD3F}\(n)\u{FD3E}" }
    private func build() -> (NSAttributedString, [Int]) {
        let font = UIFont(name: "AmiriQuran-Regular", size: 25 * size) ?? .systemFont(ofSize: 25 * size)
        let ps = NSMutableParagraphStyle(); ps.alignment = .justified; ps.baseWritingDirection = .rightToLeft; ps.minimumLineHeight = 54 * size; ps.maximumLineHeight = 54 * size
        let out = NSMutableAttributedString()
        let gold = UIColor(pal.gold), text = UIColor(pal.text), muted = UIColor(pal.muted), hl = UIColor(pal.gold.opacity(0.14)), hid = UIColor(pal.surface3)
        if sn != 1 && sn != 9 && items.first?.n == 1 {
            let bp = NSMutableParagraphStyle(); bp.alignment = .center; bp.baseWritingDirection = .rightToLeft; bp.paragraphSpacing = 10
            out.append(NSAttributedString(string: tr("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ\n"), attributes: [.font: UIFont(name: "AmiriQuran-Regular", size: 24 * size) ?? font, .foregroundColor: gold, .paragraphStyle: bp]))
        }
        var offs: [Int] = []
        for (i, it) in items.enumerated() {
            offs.append(out.length)
            let on = i == cur
            for (k, w) in it.toks.enumerated() {
                let h = hidden(i, k)
                let col: UIColor = h ? .clear : (on && words && it.wt != nil && k == wcur ? gold : (on && words && it.wt != nil && k < wcur ? muted : text))
                var at: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: col, .paragraphStyle: ps, ReadText.key: "\(i):\(k)"]
                if h { at[.backgroundColor] = hid } else if on { at[.backgroundColor] = hl }
                out.append(NSAttributedString(string: w, attributes: at))
                out.append(NSAttributedString(string: " ", attributes: [.font: font, .paragraphStyle: ps]))
            }
            out.append(NSAttributedString(string: ReadText.mark(it.n.ar), attributes: [.font: font, .foregroundColor: gold, .paragraphStyle: ps, ReadText.key: "\(i):-1"]))
            out.append(NSAttributedString(string: " ", attributes: [.font: font, .paragraphStyle: ps]))
        }
        return (out, offs)
    }
    final class Coord: NSObject, UITextViewDelegate {
        var parent: ReadText?
        var sig = 0
        var scrolled = -1
        var offsets: [Int] = []
        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let v = g.view as? UITextView, let p = parent else { return }
            var pt = g.location(in: v); pt.x -= v.textContainerInset.left; pt.y -= v.textContainerInset.top
            let i = v.layoutManager.characterIndex(for: pt, in: v.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            guard i < v.attributedText.length, let s = v.attributedText.attribute(ReadText.key, at: i, effectiveRange: nil) as? String else { return }
            let x = s.split(separator: ":").compactMap { Int($0) }
            if x.count == 2 { p.onUser(); p.onTap(x[0], x[1]) }
        }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { parent?.onUser() }
    }
}
