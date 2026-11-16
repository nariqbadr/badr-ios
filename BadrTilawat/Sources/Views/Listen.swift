import SwiftUI

/// «استمع كاملًا»: one whole-Quran recording. src: mp3 (pat with {s}, padded to pad digits) · files (surah → url) · yt (a YouTube playlist).
struct QuranRec: Identifiable, Hashable {
    let id: String, name: String, image: String, src: String, pat: String, pad: Int
    let dur: [String: Int], builtin: Bool, featured: Bool, nameSet: Bool, yt: String, ytKind: String, files: [String: String], only: [Int]
    init(_ j: J) {
        id = j["id"].str; name = j["name"].str; image = j["image"].str; src = j["src"].str.isEmpty ? "mp3" : j["src"].str; pat = j["pat"].str
        pad = j["pad"].isNull ? 3 : j["pad"].int; dur = j["dur"].dict.mapValues { $0.int }; builtin = j["builtin"].bool(); featured = j["featured"].bool()
        nameSet = j["nameSet"].bool(); yt = j["yt"].str; ytKind = j["ytKind"].str.isEmpty ? "surah" : j["ytKind"].str
        files = j["files"].dict.mapValues { $0.str }; only = j["only"].array.map { $0.int }
    }
    init(id: String, name: String, pat: String, dur: [String: Int]) {
        self.id = id; self.name = name; image = ""; src = "mp3"; self.pat = pat; pad = 3; self.dur = dur; builtin = true; featured = false; nameSet = false
        yt = ""; ytKind = "surah"; files = [:]; only = []
    }
}

enum QuranMeta {
    static let medinan: Set<Int> = [2, 3, 4, 5, 8, 9, 13, 22, 24, 33, 47, 48, 49, 55, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 76, 98, 99, 110]
    /// letters only, for searching names
    static func norm(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "[\\u064B-\\u065F\\u0670\\u0640]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "[أإآٱ]", with: "ا", options: .regularExpression).replacingOccurrences(of: "ى", with: "ي").replacingOccurrences(of: "ة", with: "ه")
        return t.trimmingCharacters(in: .whitespaces)
    }
    static func juzOfSurah(_ s: Int) -> Int { let p = Quran.surahPage[s - 1]; return p < 22 ? 1 : min(30, (p - 2) / 20 + 1) }
}

extension Repo {
    func quranFullRec() -> QuranRec? {
        guard let q = data?.quranFull, q.base.hasPrefix("https://"), !q.id.isEmpty else { return nil }
        return QuranRec(id: q.id, name: q.name, pat: q.base + "{s}.mp3", dur: q.dur)
    }
    func quranReciter() -> Reciter? {
        guard let q = data?.quranFull, !q.id.isEmpty else { return nil }
        return reciter(q.id) ?? data?.reciters.first { $0.name.contains("بدر") && $0.name.contains("التركي") }
    }
    /// Every whole-Quran recording, in the site's order (featured first); just Sheikh Badr on an older site.
    func quranRecs() -> [QuranRec] {
        if let all = data?.quranFulls { return all.filter { $0.src == "yt" ? !$0.yt.isEmpty : ($0.src == "files" ? !$0.files.isEmpty : $0.pat.hasPrefix("https://")) } }
        return quranFullRec().map { [$0] } ?? []
    }
    func quranRec(_ id: String?) -> QuranRec? { quranRecs().first { $0.id == id } }
    func quranDefault() -> QuranRec? { quranRec(data?.quranFull.id) ?? quranRecs().first { $0.src != "yt" } }
    func quranJuz(_ r: QuranRec) -> Bool { r.src == "yt" && r.ytKind == "juz" }
    func quranNums(_ r: QuranRec) -> [Int] {
        if r.src == "files" { return r.files.keys.compactMap { Int($0) }.filter { (1...114).contains($0) }.sorted() }
        if !r.only.isEmpty { return r.only.filter { (1...114).contains($0) }.sorted() }
        return Array(1...(quranJuz(r) ? 30 : 114))
    }
    func quranName(_ r: QuranRec) -> String { r.builtin && !r.nameSet ? (quranReciter()?.name ?? r.name) : r.name }
    func quranImage(_ r: QuranRec) -> String { r.image.isEmpty ? (r.builtin ? quranReciter()?.image ?? "" : "") : r.image }
    func quranTrack(_ id: String?) -> Track? {
        guard let id, let m = id.range(of: "^quran-([a-z0-9_-]+)-(\\d{1,3})$", options: .regularExpression) else { return nil }
        let s = String(id[m]); let parts = s.split(separator: "-")
        guard let n = Int(parts.last ?? ""), let r = quranRec(parts.dropFirst().dropLast().joined(separator: "-")) else { return nil }
        return quranTrack(r, n)
    }
    /// A surah of one recording, as a recitation the player can play (YouTube recordings open in YouTube instead).
    func quranTrack(_ r: QuranRec, _ s: Int) -> Track? {
        if r.src == "yt" || !(1...114).contains(s) || (!r.only.isEmpty && !r.only.contains(s)) { return nil }
        let audio: String
        if r.src == "files" { guard let f = r.files["\(s)"], !f.isEmpty else { return nil }; audio = f }
        else { let p = max(1, min(3, r.pad)); audio = r.pat.replacingOccurrences(of: "{s}", with: String(repeating: "0", count: max(0, p - String(s).count)) + String(s)) }
        let rc = r.builtin ? quranReciter() : nil
        let d = r.dur["\(s)"] ?? 0
        return Track(id: "quran-\(r.id)-\(s)", reciterId: rc?.id ?? r.id, title: tr("سورة {0}", Quran.surahs[s - 1]), surah: Quran.surahs[s - 1], surahNumber: s,
                     audio: audio, image: quranImage(r), durationSec: d > 20 ? d : 0)
    }
    func quranTracks(_ r: QuranRec?) -> [Track] { guard let r else { return [] }; return quranNums(r).compactMap { quranTrack(r, $0) } }
}

/// Saving surahs one after another (the whole Quran, a juz, chosen surahs).
@MainActor
final class QuranDownloads: ObservableObject {
    static let shared = QuranDownloads()
    @Published private(set) var queue: [String] = []
    @Published private(set) var running = false
    @Published private(set) var current: String?
    @Published private(set) var savedTick = 0
    private var task: Task<Void, Never>?
    func add(_ ids: [String]) { for i in ids where !queue.contains(i) && OfflineFiles.local(i) == nil { queue.append(i) }; run() }
    func run() {
        guard !running, !queue.isEmpty else { return }
        running = true
        task = Task {
            while let id = queue.first, !Task.isCancelled {
                current = id
                if let t = Repo.shared.track(id) { _ = await OfflineFiles.save(t) }
                if Task.isCancelled { break }
                queue.removeAll { $0 == id }; savedTick += 1
            }
            current = nil; running = false
        }
    }
    func stop() { task?.cancel(); running = false; current = nil }
    func cancel() { stop(); queue = [] }
    func delete(_ id: String) { OfflineFiles.delete(id); savedTick += 1 }
}

/* «بصمة الصوت»: every reciter has his own tone and his own wave (drawn from his id — the same wave as on the website). */
private let TONES: [Color] = [0x2F8A64, 0x9A3A4C, 0x3A62A0, 0x9A7A32, 0x6A4AA0, 0x2A8A8A, 0xA0582E, 0x5E8A2E].map { Color(red: Double($0 >> 16) / 255, green: Double(($0 >> 8) & 255) / 255, blue: Double($0 & 255) / 255) }
private func qHash(_ s: String) -> UInt64 { var h: UInt64 = 2166136261; for ch in s.utf16 { h = ((h ^ UInt64(ch)) &* 16777619) & 0xFFFFFFFF }; return h }
private func waveBars(_ seed: String, _ k: Int) -> [Double] {
    var h = qHash(seed); if h == 0 { h = 1 }
    let ph = Double(h % 100) / 30, sp = 2.6 + Double(h % 7) / 4
    return (0..<k).map { i in
        h = (((h &* 1103515245) & 0xFFFFFFFF) &+ 12345) & 0xFFFFFFFF
        let v = 22 + 78 * abs(sin(Double(i) / sp + ph)) * (0.45 + Double((h >> 9) % 100) / 180)
        return Double(Int(min(100, v).rounded())) / 100
    }
}
private struct QWave: View {
    let seed: String, p: Double, bars: Int, height: CGFloat
    @Environment(\.pal) private var c
    var body: some View {
        let hs = waveBars(seed, bars), n = Int((p * Double(bars)).rounded())
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(hs.enumerated()), id: \.offset) { i, v in RoundedRectangle(cornerRadius: 2).fill(i < n ? c.gold : c.gold.opacity(0.3)).frame(maxWidth: .infinity).frame(height: height * v) }
        }.frame(height: height)
    }
}
private func tone(_ recs: [QuranRec], _ r: QuranRec) -> Color { TONES[((recs.firstIndex { $0.id == r.id }) ?? Int(qHash(r.id) % 8)) % TONES.count] }
private struct ToneBG: View {
    let tone: Color
    @Environment(\.pal) private var c
    var body: some View { LinearGradient(colors: [tone.opacity(c.dark ? 0.34 : 0.13), tone.opacity(c.dark ? 0.14 : 0.05), .clear], startPoint: .topLeading, endPoint: .bottomTrailing).background(c.surface) }
}
private struct RecAvatar: View {
    let r: QuranRec; let size: CGFloat
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    var body: some View {
        let img = repo.quranImage(r)
        ZStack { Circle().fill(c.gold.opacity(0.18)); if img.isEmpty { Text(String(repo.quranName(r).replacingOccurrences(of: "الشيخ ", with: "").prefix(1))).font(F.amiri(size * 0.42)).foregroundStyle(c.gold) } else { RemoteImage(raw: img) } }
            .frame(width: size, height: size).clipShape(Circle()).overlay(Circle().stroke(c.gold.opacity(0.4)))
    }
}
private struct PlayDot: View {
    let playing: Bool, on: Bool, size: CGFloat
    @Environment(\.pal) private var c
    var body: some View {
        Ico(name: playing ? "pause.fill" : "play.fill", size: 20).font(.system(size: size * 0.4)).foregroundStyle(on ? c.onGold : c.gold)
            .frame(width: size, height: size).background(Circle().fill(on ? c.gold : .clear)).overlay(Circle().stroke(c.gold.opacity(on ? 1 : 0.55)))
    }
}
@MainActor private func countLabel(_ repo: Repo, _ r: QuranRec) -> String {
    if repo.quranJuz(r) { return tr("٣٠ جزءًا") }
    let n = repo.quranNums(r).count
    return n == 1 ? tr("سورة واحدة") : n == 2 ? tr("سورتان") : "\(n.ar) \(n <= 10 ? "سور" : "سورة")"
}
private func ytURL(_ r: QuranRec, _ index: Int = 0) -> URL? { URL(string: "https://www.youtube.com/playlist?list=\(r.yt)" + (index > 0 ? "&index=\(index + 1)" : "")) }
private func msFmt(_ s: Double) -> String { let x = Int(s); return x >= 3600 ? String(format: "%d:%02d:%02d", x / 3600, x % 3600 / 60, x % 60) : String(format: "%d:%02d", x / 60, x % 60) }

/// Where a recording was left: the surah and how far into the whole.
@MainActor private func progress(_ repo: Repo, _ r: QuranRec, _ p: AudioPlayer) -> (id: String?, frac: Double, pos: Double) {
    let pre = "quran-\(r.id)-", nums = repo.quranNums(r)
    var id: String?, pos = 0.0, dur = 0.0
    if let cur = p.current?.id, cur.hasPrefix(pre) { id = cur; pos = p.position; dur = p.duration }
    else if let h = Store.shared.history.first(where: { $0.hasPrefix(pre) }) { id = h; pos = Store.shared.position(h); dur = Double(repo.track(h)?.durationSec ?? 0) }
    guard let id else { return (nil, 0, 0) }
    let i = nums.firstIndex(of: Int(id.dropFirst(pre.count)) ?? 0) ?? -1
    let f = dur > 0 ? min(1, max(0, pos / dur)) : 0
    return (id, i < 0 || nums.isEmpty ? 0 : min(1, (Double(i) + f) / Double(nums.count)), pos)
}

/// «القرآن الكريم كاملًا»: one reciter — his surahs right away; more than one — «اختر القارئ», then his page.
struct ListenView: View {
    @EnvironmentObject var repo: Repo
    @State private var rid = ""
    var body: some View {
        let recs = repo.quranRecs()
        if recs.isEmpty { Empty(text: tr("القرآن الكريم كاملًا غير متاح الآن."), icon: "book") }
        else if let playable = recs.first(where: { $0.src != "yt" }) {
            if recs.count > 1, !recs.contains(where: { $0.id == rid && $0.src != "yt" }) { QuranLibraryView(recs: recs) { rid = $0 } }
            else { ReciterQuranView(recs: recs, r: recs.first { $0.id == rid } ?? playable, back: recs.count > 1 ? { rid = "" } : nil) }
        } else { QuranLibraryView(recs: recs) { rid = $0 } }
    }
}

private struct QuranLibraryView: View {
    let recs: [QuranRec]; let open: (String) -> Void
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.pal) private var c
    @Environment(\.openURL) private var openURL
    @State private var q = ""
    @State private var pick = 0
    var body: some View {
        let nq = QuranMeta.norm(q).replacingOccurrences(of: "سوره", with: "").trimmingCharacters(in: .whitespaces)
        let n0 = Int(String(q.trimmingCharacters(in: .whitespaces).map { c in c.wholeNumberValue.map { Character(String($0)) } ?? c }))
        let hits = nq.isEmpty ? [] : Array((1...114).filter { (n0 != nil && $0 == n0) || QuranMeta.norm(Quran.surahs[$0 - 1]).contains(nq) }.prefix(8))
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SearchField(text: $q, hint: tr("ابحث عن سورة واسمعها بصوت أي قارئ")).padding(.horizontal, 16).padding(.top, 8)
                if !nq.isEmpty {
                    if hits.isEmpty { Empty(text: tr("لا توجد سورة بهذا الاسم.")) }
                    else {
                        let sn = hits.contains(pick) ? pick : hits[0]
                        if hits.count > 1 { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(hits, id: \.self) { n in Pill(title: Quran.surahs[n - 1], on: n == sn) { pick = n } } }.padding(.horizontal, 16) } }
                        Text(tr("سورة {0} · اختر بصوت مَن تسمعها", Quran.surahs[sn - 1])).font(F.plex(13, .bold)).foregroundStyle(c.gold).padding(.horizontal, 18).padding(.vertical, 6)
                        ForEach(recs) { r in
                            let juz = repo.quranJuz(r), n = juz ? QuranMeta.juzOfSurah(sn) : sn
                            let t = repo.quranTrack(r, n)
                            if t != nil || r.src == "yt" {
                                let on = t != nil && player.current?.id == t?.id
                                Button { if let t { if on { player.toggle() } else { player.play(t, in: repo.quranTracks(r)) } } else if let u = ytURL(r, n - 1) { openURL(u) } } label: {
                                    HStack(spacing: 10) {
                                        RecAvatar(r: r, size: 40)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(nm(repo.quranName(r).replacingOccurrences(of: "الشيخ ", with: ""))).font(F.amiri(17)).foregroundStyle(c.text).lineLimit(1)
                                            Text(juz ? tr("الجزء {0} (فيه السورة)", n.ar) : (t.map { Fmt.dur($0.durationSec) }.flatMap { $0.isEmpty ? nil : $0 } ?? countLabel(repo, r))).font(F.plex(12)).foregroundStyle(c.text.opacity(0.62))
                                        }.frame(minWidth: 92, alignment: .leading)
                                        QWave(seed: "\(r.id):\(n)", p: 0, bars: 22, height: 22).padding(.horizontal, 6)
                                        PlayDot(playing: on && player.playing, on: on, size: 36)
                                    }.padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(ToneBG(tone: tone(recs, r))).clipShape(RoundedRectangle(cornerRadius: 18))
                                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(on ? c.gold.opacity(0.65) : c.text.opacity(0.07)))
                                }.buttonStyle(Press()).padding(.horizontal, 16)
                            }
                        }
                    }
                } else {
                    Text(tr("اختر القارئ")).font(F.plex(13, .bold)).foregroundStyle(c.gold).padding(.horizontal, 18).padding(.vertical, 4)
                    ForEach(recs) { r in
                        let pr = progress(repo, r, player), lt = repo.track(pr.id)
                        let mine = player.current?.id.hasPrefix("quran-\(r.id)-") == true
                        let all = repo.quranTracks(r)
                        let sub = mine && player.playing ? tr("يُشغَّل الآن · {0}", lt?.title ?? "") : lt != nil ? tr("وصلت إلى {0}{1}", lt!.title, pr.pos > 10 ? "، \(msFmt(pr.pos))" : "") : countLabel(repo, r)
                        Button { if r.src == "yt" { if let u = ytURL(r) { openURL(u) } } else { open(r.id) } } label: {
                            VStack(spacing: 10) {
                                HStack(spacing: 12) {
                                    RecAvatar(r: r, size: 46)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(nm(repo.quranName(r))).font(F.amiri(20)).foregroundStyle(c.text).lineLimit(1)
                                        HStack(spacing: 6) {
                                            if r.featured { Text(tr("مميّز")).font(F.plex(11, .bold)).foregroundStyle(c.gold).padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(c.gold.opacity(0.16))) }
                                            Text(sub).font(F.plex(12)).foregroundStyle(c.text.opacity(0.64)).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Button {
                                        if r.src == "yt" { if let u = ytURL(r) { openURL(u) } } else if mine { player.toggle() } else if let lt { player.play(lt, in: all) } else if let f = all.first { player.play(f, in: all) }
                                    } label: { PlayDot(playing: mine && player.playing, on: mine, size: 42) }.buttonStyle(Press())
                                }
                                QWave(seed: r.id, p: pr.frac, bars: 48, height: 36)
                            }.padding(.horizontal, 16).padding(.vertical, 14)
                            .background(ToneBG(tone: tone(recs, r))).clipShape(RoundedRectangle(cornerRadius: 22))
                            .overlay(RoundedRectangle(cornerRadius: 22).stroke(mine || r.featured ? c.gold.opacity(0.65) : c.text.opacity(0.07)))
                        }.buttonStyle(Press()).padding(.horizontal, 16)
                    }
                }
            }.padding(.bottom, 24)
        }
    }
}

/// One reciter's page: the hero with his wave, carry on / from the start, repeat, saving, and every surah.
private struct ReciterQuranView: View {
    let recs: [QuranRec]; let r: QuranRec; let back: (() -> Void)?
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var player: AudioPlayer
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @ObservedObject private var dl = QuranDownloads.shared
    @Environment(\.pal) private var c
    @State private var q = ""
    @State private var filter = "all"
    @State private var select = false
    @State private var picked = Set<String>()
    @State private var sheet: String?
    @State private var more: Track?
    @State private var ra = 67
    @State private var rb = 114

    init(recs: [QuranRec], r: QuranRec, back: (() -> Void)?) { self.recs = recs; self.r = r; self.back = back }
    private func saved(_ id: String) -> Bool { _ = dl.savedTick; return OfflineFiles.local(id) != nil }

    var body: some View {
        let all = repo.quranTracks(r)
        if all.isEmpty { Empty(text: tr("هذا المصحف غير متاح الآن.")) } else { page(all) }
    }

    private func page(_ all: [Track]) -> some View {
        let savedCount = all.filter { saved($0.id) }.count
        let nq = QuranMeta.norm(q)
        let shown = all.filter { nq.isEmpty || QuranMeta.norm($0.surah).contains(nq) || "\($0.surahNumber)" == q.trimmingCharacters(in: .whitespaces) || $0.surahNumber.ar == q.trimmingCharacters(in: .whitespaces) }
            .filter { switch filter { case "saved": return saved($0.id); case "makki": return !QuranMeta.medinan.contains($0.surahNumber); case "madani": return QuranMeta.medinan.contains($0.surahNumber); default: return true } }
        let pr = progress(repo, r, player), last = repo.track(pr.id)
        let mine = player.current?.id.hasPrefix("quran-\(r.id)-") == true
        let repOn = mine && (player.repeatMode != 0 || player.repN > 0)
        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let back { Button(action: back) { HStack(spacing: 4) { Ico(name: "chevron.right", size: 20); Text(tr("كل القرّاء")) }.font(F.plex(14)).foregroundStyle(c.muted) }.padding(.horizontal, 18).padding(.top, 6) }
                    // hero
                    VStack(spacing: 14) {
                        HStack(spacing: 14) {
                            RecAvatar(r: r, size: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(nm(repo.quranName(r))).font(F.amiri(23)).foregroundStyle(c.text)
                                Text(last != nil ? tr("وصلت إلى {0}{1}", last!.title, pr.pos > 10 ? "، \(msFmt(pr.pos))" : "") : r.builtin ? tr("المصحف المرتّل · ١١٤ سورة · رواية حفص عن عاصم") : countLabel(repo, r))
                                    .font(F.plex(12.5)).foregroundStyle(c.text.opacity(0.66))
                            }
                            Spacer(minLength: 0)
                        }
                        QWave(seed: r.id, p: pr.frac, bars: 56, height: 52)
                    }.padding(16).background(ToneBG(tone: tone(recs, r))).clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(pr.id != nil ? c.gold.opacity(0.6) : c.text.opacity(0.07))).padding(.horizontal, 16)
                    // carry on / from the start / repeat
                    HStack(spacing: 8) {
                        if mine {
                            GoldButton(title: player.playing ? tr("إيقاف مؤقت") : tr("أكمل {0}", player.current?.title ?? ""), icon: player.playing ? "pause.fill" : "play.fill") { player.toggle() }
                            GhostButton(title: tr("من {0}", all[0].surah), icon: "play.fill") { player.play(all[0], in: all, fromStart: true) }
                        } else if let last {
                            GoldButton(title: tr("أكمل من {0}", last.surah), icon: "play.fill") { player.play(last, in: all) }
                            GhostButton(title: tr("من {0}", all[0].surah), icon: "play.fill") { player.play(all[0], in: all, fromStart: true) }
                        } else {
                            GoldButton(title: tr("تشغيل من {0}", all[0].surah), icon: "play.fill") { player.play(all[0], in: all) }
                            GhostButton(title: tr("عشوائي"), icon: "shuffle") { if let t = all.randomElement() { player.play(t, in: all); player.shuffle = true } }
                        }
                        Button { sheet = "rep" } label: { Ico(name: "repeat", size: 21.6).foregroundStyle(repOn ? c.onGold : c.gold).frame(width: 46, height: 46).background(Circle().fill(repOn ? c.gold : .clear)).overlay(Circle().stroke(repOn ? c.gold : c.line)) }
                            .accessibilityLabel(tr("التكرار"))
                    }.padding(.horizontal, 16)
                    // saving in progress
                    if dl.running || !dl.queue.isEmpty {
                        let cur = dl.queue.first.flatMap { repo.track($0) }
                        HStack(spacing: 12) {
                            Ico(name: "arrow.down", size: 20).foregroundStyle(c.onGold).frame(width: 38, height: 38).background(Circle().fill(c.gold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dl.running ? tr("جارٍ الحفظ: {0}", cur?.title ?? "") : tr("توقّف الحفظ")).font(F.plex(14, .semibold)).foregroundStyle(c.text)
                                Text(tr("تبقّى {0} سورة{1}", dl.queue.count.ar, dl.running ? " · يمكنك متابعة الاستماع أثناء الحفظ" : "")).font(F.plex(12)).foregroundStyle(c.muted)
                            }
                            Spacer()
                            GhostButton(title: dl.running ? tr("إيقاف") : tr("استكمال")) { if dl.running { dl.stop() } else { dl.run() } }
                        }.padding(12).background(RoundedRectangle(cornerRadius: 16).fill(c.gold.opacity(0.1))).overlay(RoundedRectangle(cornerRadius: 16).stroke(c.gold.opacity(0.4))).padding(.horizontal, 16)
                    }
                    SearchField(text: $q, hint: tr("ابحث عن سورة بالاسم أو الرقم")).padding(.horizontal, 16)
                    HStack(spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Pill(title: tr("الكل"), on: filter == "all") { filter = "all" }
                                Pill(title: tr("المحفوظة{0}", savedCount > 0 ? " (\(savedCount.ar))" : ""), on: filter == "saved") { filter = "saved" }
                                Pill(title: tr("مكية"), on: filter == "makki") { filter = "makki" }
                                Pill(title: tr("مدنية"), on: filter == "madani") { filter = "madani" }
                            }
                        }
                        Button { sheet = "dl" } label: { Ico(name: "arrow.down.circle", size: 24.0).foregroundStyle(c.gold) }.accessibilityLabel(tr("التحميل"))
                        Button { select.toggle(); picked = [] } label: { Ico(name: select ? "xmark" : "checklist", size: 21.6).foregroundStyle(c.gold) }.accessibilityLabel(select ? tr("إلغاء التحديد") : tr("تحديد سور"))
                    }.padding(.horizontal, 16)
                    if shown.isEmpty { Empty(text: filter == "saved" ? tr("لم تحفظ أي سورة بعد. اضغط زر التحميل لحفظ القرآن كاملًا أو بعض السور.") : tr("لا توجد سورة بهذا الاسم.")) }
                    ForEach(shown) { t in row(t, all) }
                }.padding(.bottom, select ? 96 : 24)
            }
            if select {
                HStack(spacing: 8) {
                    Text(picked.isEmpty ? tr("اختر السور") : tr("تم تحديد {0} سورة", picked.count.ar)).font(F.plex(14, .semibold)).foregroundStyle(c.text)
                    Spacer()
                    GoldButton(title: tr("تحميل"), icon: "arrow.down") { if picked.isEmpty { ui.say(tr("اختر سورة واحدة على الأقل")) } else { dl.add(all.map(\.id).filter { picked.contains($0) }); select = false; picked = [] } }
                    GhostButton(title: tr("تشغيل"), icon: "play.fill") { let l = all.filter { picked.contains($0.id) }; if let f = l.first { player.play(f, in: l, fromStart: true); select = false; picked = [] } else { ui.say(tr("اختر سورة واحدة على الأقل")) } }
                }.padding(10).background(RoundedRectangle(cornerRadius: 18).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.gold.opacity(0.4))).padding(12)
            }
        }
        .bzSheet(item: Binding(get: { sheet.map { SID(id: $0) } }, set: { sheet = $0?.id })) { s in
            Group {
                switch s.id {
                case "rep": repeatSheet(all, mine: mine, last: last)
                case "range": rangeSheet(all)
                default: downloadSheet(all, savedCount)
                }
            }.environment(\.layoutDirection, L.dir).presentationDetents([.medium, .large])
        }
        .bzSheet(item: $more) { t in
            MenuSheet(title: t.title) {
                MenuRow(icon: "repeat", title: tr("تكرار هذه السورة")) { more = nil; player.play(t, in: all); player.setRepeat(2); ui.say(tr("ستُكرَّر {0}", t.title)) }
                MenuRow(icon: "text.line.first.and.arrowtriangle.forward", title: tr("تشغيل بعد الحالية")) { more = nil; player.playNext(t); ui.say(tr("ستُشغَّل بعد التلاوة الحالية")) }
                MenuRow(icon: "text.badge.plus", title: tr("إضافة إلى قائمة الانتظار")) { more = nil; player.enqueue(t); ui.say(tr("أُضيفت إلى قائمة الانتظار")) }
                MenuRow(icon: saved(t.id) ? "trash" : "arrow.down.circle", title: saved(t.id) ? tr("حذف من الجهاز") : tr("حفظ للاستماع دون إنترنت")) {
                    more = nil; if saved(t.id) { dl.delete(t.id); ui.say(tr("حُذفت من الجهاز")) } else { dl.add([t.id]) }
                }
            }.presentationDetents([.medium])
        }
    }
    private struct SID: Identifiable { let id: String }

    private func row(_ t: Track, _ all: [Track]) -> some View {
        let on = player.current?.id == t.id, playing = on && player.playing
        let sv = saved(t.id), busy = dl.current == t.id, waiting = dl.queue.contains(t.id) && !busy
        let isPicked = picked.contains(t.id)
        let meta = [QuranMeta.medinan.contains(t.surahNumber) ? tr("مدنية") : tr("مكية"), tr("{0} آية", Quran.ayahs[t.surahNumber - 1].ar), Fmt.dur(t.durationSec), sv ? tr("محفوظة") : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: 12) {
            Text(t.surahNumber.ar).font(F.amiri(16)).foregroundStyle(c.gold).frame(width: 42, height: 42).background(Circle().stroke(c.gold.opacity(0.5)))
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(F.amiri(19)).foregroundStyle(on ? c.gold : c.text)
                Text(meta).font(F.plex(12)).foregroundStyle(c.muted)
            }
            Spacer(minLength: 4)
            if on && player.repN > 1 { Text("\(min(max(1, player.repDone), player.repN).ar)/\(player.repN.ar)").font(F.plex(11, .bold)).foregroundStyle(c.onGold).padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(c.gold)) }
            else if on && player.repeatMode == 2 { Ico(name: "repeat.1", size: 20).foregroundStyle(c.gold) }
            if select {
                Ico(name: isPicked ? "checkmark.square.fill" : "square", size: 26.4).foregroundStyle(isPicked ? c.gold : c.line)
            } else {
                Button {
                    if busy || waiting { return }
                    if sv { dl.delete(t.id); ui.say(tr("حُذفت من الجهاز")) } else { dl.add([t.id]) }
                } label: {
                    Group {
                        if busy { ProgressView().tint(c.gold) }
                        else if waiting { Ico(name: "clock", size: 20).foregroundStyle(c.faint) }
                        else { Ico(name: sv ? "checkmark.circle" : "arrow.down.circle", size: 20).foregroundStyle(c.gold) }
                    }.frame(width: 30, height: 30)
                }.buttonStyle(.plain).accessibilityLabel(sv ? tr("محفوظة على الجهاز") : tr("احفظ للاستماع دون إنترنت"))
                Button { more = t } label: { Ico(name: "ellipsis", size: 20).rotationEffect(.degrees(90)).foregroundStyle(c.faint).frame(width: 28, height: 30) }.buttonStyle(.plain).accessibilityLabel(tr("خيارات {0}", t.title))
                Ico(name: playing ? "pause.fill" : "play.fill", size: 20).foregroundStyle(playing ? c.onGold : c.gold).frame(width: 38, height: 38).background(Circle().fill(playing ? c.gold : .clear))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16).fill(on || isPicked ? c.gold.opacity(0.12) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { if select { if isPicked { picked.remove(t.id) } else { picked.insert(t.id) } } else if on { player.toggle() } else { player.play(t, in: all) } }
        .onLongPressGesture { select = true; picked.insert(t.id) }
        .padding(.horizontal, 10)
    }

    // the surah the repeat options act on: the one playing (from this reciter), else where you stopped, else the first
    private func repeatSheet(_ all: [Track], mine: Bool, last: Track?) -> some View {
        let target = (mine ? player.current : nil) ?? last ?? all[0]
        let cur = mine ? player.repeatMode : 0
        func ensure() { if !mine { player.play(target, in: all) } }
        return MenuSheet(title: tr("التكرار")) {
            MenuRow(icon: "xmark", title: tr("بدون تكرار"), sub: tr("تنتقل للسورة التالية تلقائيًا"), on: cur == 0 && player.repN == 0) { sheet = nil; player.setRepeat(0) }
            MenuRow(icon: "repeat.1", title: tr("تكرار السورة دائمًا"), sub: tr("تُعاد {0} حتى توقفها", target.title), on: cur == 2 && player.repN == 0) { sheet = nil; ensure(); player.setRepeat(2) }
            Text(tr("تكرار عددًا محددًا · للحفظ والمراجعة")).font(F.plex(12)).foregroundStyle(c.muted).padding(.horizontal, 20).padding(.top, 6)
            HStack(spacing: 8) { ForEach([3, 5, 7, 10], id: \.self) { n in Pill(title: tr("{0} مرات", n.ar), on: player.repN == n) { sheet = nil; ensure(); player.repeatTimes(n); ui.say(tr("كل سورة تُعاد {0} مرات ثم التالية", n.ar)) } } }.padding(.horizontal, 20)
            MenuRow(icon: "arrow.up.arrow.down", title: tr("تكرار نطاق من السور"), sub: tr("مثال: من الملك إلى الناس")) { sheet = "range" }
            MenuRow(icon: "infinity", title: tr("تكرار المصحف كله"), sub: tr("بعد آخر سورة يبدأ من الأولى"), on: cur == 1 && player.repN == 0) { sheet = nil; ensure(); player.setRepeat(1) }
        }
    }
    private func rangeSheet(_ all: [Track]) -> some View {
        let nums = all.map(\.surahNumber)
        func go(_ x: Int, _ y: Int) {
            let l = all.filter { (min(x, y)...max(x, y)).contains($0.surahNumber) }
            guard let f = l.first else { return }
            sheet = nil; player.play(f, in: l, fromStart: true); player.setRepeat(1)
            ui.say(tr("يتكرر من {0} إلى {1}", l.first!.surah, l.last!.surah))
        }
        func picker(_ label: String, _ v: Binding<Int>) -> some View {
            HStack {
                Text(label).font(F.plex(14)).foregroundStyle(c.muted).frame(width: 36, alignment: .leading)
                Button { if let i = nums.firstIndex(of: v.wrappedValue), i > 0 { v.wrappedValue = nums[i - 1] } } label: { Ico(name: "chevron.right", size: 20).foregroundStyle(c.gold) }.accessibilityLabel(tr("السابقة"))
                Text("\(v.wrappedValue.ar). \(Quran.surahs[v.wrappedValue - 1])").font(F.amiri(19)).foregroundStyle(c.text).frame(maxWidth: .infinity)
                Button { if let i = nums.firstIndex(of: v.wrappedValue), i + 1 < nums.count { v.wrappedValue = nums[i + 1] } } label: { Ico(name: "chevron.left", size: 20).foregroundStyle(c.gold) }.accessibilityLabel(tr("التالية"))
            }.padding(.horizontal, 20)
        }
        return MenuSheet(title: tr("تكرار نطاق من السور")) {
            Text(tr("جاهزة")).font(F.plex(12)).foregroundStyle(c.muted).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) {
                Pill(title: tr("جزء عمّ"), on: false) { go(78, 114) }; Pill(title: tr("جزء تبارك"), on: false) { go(67, 77) }
                Pill(title: tr("الزهراوان"), on: false) { go(2, 3) }; Pill(title: tr("المعوّذات"), on: false) { go(112, 114) }
            }.padding(.horizontal, 20) }
            Text(tr("أو اختر بنفسك")).font(F.plex(12)).foregroundStyle(c.muted).padding(.horizontal, 20).padding(.top, 6)
            picker(tr("من"), Binding(get: { nums.contains(ra) ? ra : nums.first ?? 1 }, set: { ra = $0 }))
            picker(tr("إلى"), Binding(get: { nums.contains(rb) ? rb : nums.last ?? 114 }, set: { rb = $0 }))
            GoldButton(title: tr("ابدأ التكرار"), icon: "repeat") { go(nums.contains(ra) ? ra : nums.first ?? 1, nums.contains(rb) ? rb : nums.last ?? 114) }.padding(20)
        }
    }
    private func downloadSheet(_ all: [Track], _ savedCount: Int) -> some View {
        let amma = all.filter { $0.surahNumber >= 78 }
        let mb = all.filter { saved($0.id) }.reduce(0.0) { s, t in s + Double(((try? FileManager.default.attributesOfItem(atPath: OfflineFiles.file(t.id).path))?[.size] as? Int64) ?? 0) / 1_048_576 }
        return MenuSheet(title: tr("تحميل للاستماع دون إنترنت")) {
            Text(tr("المحفوظ على جهازك: {0} من {1} سورة · {2} ميجا", savedCount.ar, all.count.ar, Int(mb).ar)).font(F.plex(12)).foregroundStyle(c.muted).padding(.horizontal, 20)
            if savedCount < all.count { MenuRow(icon: "arrow.down.circle", title: all.count >= 114 ? tr("تحميل القرآن الكريم كاملًا") : tr("تحميل كل السور"), sub: tr("{0} سورة · الحجم كبير، يُفضَّل الاتصال بشبكة Wi-Fi", (all.count - savedCount).ar)) { sheet = nil; dl.add(all.map(\.id)) } }
            if amma.count > 1 && amma.contains(where: { !saved($0.id) }) { MenuRow(icon: "arrow.down.circle", title: tr("تحميل جزء عمّ"), sub: tr("من سورة النبأ إلى سورة الناس")) { sheet = nil; dl.add(amma.map(\.id)) } }
            if all.count > 5 && all.prefix(5).contains(where: { !saved($0.id) }) { MenuRow(icon: "arrow.down.circle", title: tr("تحميل أول خمس سور"), sub: all.prefix(5).map(\.surah).joined(separator: tr("، "))) { sheet = nil; dl.add(all.prefix(5).map(\.id)) } }
            MenuRow(icon: "checklist", title: tr("اختيار سور معيّنة"), sub: tr("حدّد السور التي تريدها ثم اضغط «تحميل»")) { sheet = nil; select = true; picked = [] }
            if !dl.queue.isEmpty && !dl.running { MenuRow(icon: "arrow.down.circle", title: tr("استكمال الحفظ المتوقف"), sub: tr("{0} سورة متبقية", dl.queue.count.ar)) { sheet = nil; dl.run() } }
            if !dl.queue.isEmpty { MenuRow(icon: "xmark", title: tr("إلغاء الحفظ")) { sheet = nil; dl.cancel() } }
            if savedCount > 0 { MenuRow(icon: "trash", title: tr("حذف السور المحفوظة"), sub: tr("لتوفير مساحة على جهازك")) { sheet = nil; all.filter { saved($0.id) }.forEach { dl.delete($0.id) }; ui.say(tr("حُذفت السور المحفوظة")) } }
        }
    }
}

/// Entry card (home, recitations page, Quran tab): «القرآن الكريم كاملًا».
struct QuranFullBanner: View {
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    var body: some View {
        let recs = repo.quranRecs()
        if let r = recs.first {
            let n = recs.count
            let short = { (x: QuranRec) in repo.quranName(x).replacingOccurrences(of: "الشيخ ", with: "") }
            let cnt = n == 2 ? tr("مصحفان مرتّلان") : n <= 10 ? tr("{0} مصاحف مرتّلة", n.ar) : tr("{0} مصحفًا مرتّلًا", n.ar)
            Button { ui.path.append(.listen) } label: {
                HStack(spacing: 12) {
                    if n == 1 { RecAvatar(r: r, size: 56) }
                    else { HStack(spacing: -12) { ForEach(recs.prefix(n > 3 ? 2 : 3)) { x in RecAvatar(r: x, size: 40).overlay(Circle().stroke(c.surface, lineWidth: 2)) }
                        if n > 3 { Text("+\((n - 2).ar)").font(F.plex(13, .bold)).foregroundStyle(c.gold).frame(width: 40, height: 40).background(Circle().fill(c.gold.opacity(0.18))).overlay(Circle().stroke(c.surface, lineWidth: 2)) } }.environment(\.layoutDirection, .leftToRight) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("القرآن الكريم كاملًا")).font(F.amiri(19)).foregroundStyle(c.text)
                        Text(n > 1 ? tr("{0} · {1} و{2}{3}", cnt, short(recs[0]), short(recs[1]), n > 2 ? " وغيرهما" : "") : tr("بصوت {0} · ١١٤ سورة متتابعة", Repo.withSheikh(short(r)))).font(F.plex(12)).foregroundStyle(c.muted).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Ico(name: "play.fill", size: 20).foregroundStyle(c.onGold).frame(width: 42, height: 42).background(Circle().fill(c.gold))
                }.padding(14)
                .background(LinearGradient(colors: [c.gold.opacity(0.22), c.surface], startPoint: .topLeading, endPoint: .bottomTrailing)).clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(c.gold.opacity(0.4)))
            }.buttonStyle(Press())
        }
    }
}

/// A search box in the site's style.
struct SearchField: View {
    @Binding var text: String; let hint: String
    @Environment(\.pal) private var c
    var body: some View {
        HStack(spacing: 8) {
            SiteIcon(name: "search", size: 22, color: c.gold)
            TextField(hint, text: $text).font(F.plex(15)).autocorrectionDisabled()
            if !text.isEmpty { Button { text = "" } label: { SiteIcon(name: "close", size: 20, color: c.muted) }.accessibilityLabel(tr("مسح")) }
        }.padding(.horizontal, 14).padding(.vertical, 13).background(RoundedRectangle(cornerRadius: 18).fill(c.surface.opacity(0.45))).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.line))
    }
}

/// A bottom sheet with the site's look: the title, a close button and the ornament, then the rows.
struct MenuSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.pal) private var c
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHead(title: title)
                content
            }.padding(.bottom, 20)
        }.background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir)
    }
}
struct MenuRow: View {
    let icon: String, title: String; var sub: String? = nil; var on = false; var tint: Color? = nil; let action: () -> Void
    @Environment(\.pal) private var c
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Ico(name: icon, size: 21, color: tint ?? c.gold).frame(width: 38, height: 38).background(RoundedRectangle(cornerRadius: 12).fill(c.gold.opacity(0.10)))
                VStack(alignment: .leading, spacing: 2) { Text(title).font(F.plex(16)).foregroundStyle(tint ?? (on ? c.gold : c.text)); if let sub, !sub.isEmpty { Text(sub).font(F.plex(12.5)).foregroundStyle(c.muted).multilineTextAlignment(.leading) } }
                Spacer()
                if on { SiteIcon(name: "check", size: 20, color: c.gold) }
            }.padding(.horizontal, 22).padding(.vertical, 13).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
