import SwiftUI

var SORTS: [(String, String)] { [("new", tr("الأحدث")), ("popular", tr("الأكثر استماعًا")), ("surah", tr("ترتيب المصحف")), ("order", tr("الترتيب")), ("az", tr("أبجدي"))] }
func sortTracks(_ l: [Track], _ mode: String, _ plays: [String: Int]) -> [Track] {
    switch mode {
    case "popular": return l.sorted { (plays[$0.id] ?? 0, $0.stamp) > (plays[$1.id] ?? 0, $1.stamp) }
    case "order": return l.sorted { $0.order < $1.order }
    case "az": return l.sorted { $0.title.compare($1.title, locale: Locale(identifier: "ar")) == .orderedAscending }
    case "surah": return l.sorted { ($0.surahNumber > 0 ? $0.surahNumber : 999, $0.ayahStart) < ($1.surahNumber > 0 ? $1.surahNumber : 999, $1.ayahStart) }
    default: return l.sorted { $0.stamp != $1.stamp ? $0.stamp > $1.stamp : $0.order > $1.order }
    }
}

/// «التلاوات» (like the Android app): الكل / صوتية / مرئية, the whole Quran, search, the reciters, sort, the list in periods.
struct RecitationsView: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var player: AudioPlayer
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var q = ""
    @State private var rec = ""
    @State private var sort = "new"
    @State private var kind = RecKind.value.isEmpty ? "all" : RecKind.value
    var body: some View {
        let all = repo.data?.recitations ?? []
        let vids = all.filter(\.isVideo).count
        let kv = vids > 0 && kind == "video", ka = kind == "all" || vids == 0
        let nq = QuranMeta.norm(q.trimmingCharacters(in: .whitespaces))
        let list = sortTracks(all.filter { ka || $0.isVideo == kv }.filter { rec.isEmpty || $0.reciterId == rec }
            .filter { nq.isEmpty || QuranMeta.norm("\($0.title) \($0.surah) \(repo.reciter($0.reciterId)?.name ?? "") \($0.tags.joined(separator: " ")) \($0.description) \($0.location)").contains(nq) }, sort, repo.data?.plays ?? [:])
        let audio = list.filter { !$0.isVideo }
        let grouped = sort == "new" && q.isEmpty && list.count > 6 && Set(list.map(ageGroup)).count > 1
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if vids > 0 { KindTabs(kind: kind, nAll: all.count, nAudio: all.count - vids, nVideo: vids) { kind = $0; RecKind.value = $0; rec = "" }.padding(.horizontal, 16).padding(.vertical, 6) }
                if !kv && repo.data?.site.sec("mushaf") != false { QuranFullBanner().padding(.horizontal, 16).padding(.vertical, 6) }
                // «المجموعات» (a year, a Ramadan, a mosque…), for the chosen reciter — as on the site and Android
                if !kv { let cols = repo.collections(rec); if !cols.isEmpty { CollectionsRow(cols: cols, showReciter: rec.isEmpty) } }
                SearchField(text: $q, hint: tr("ابحث بالسورة أو القارئ أو المكان")).padding(.horizontal, 16).padding(.vertical, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Pill(title: tr("الكل"), on: rec.isEmpty) { rec = "" }
                        ForEach((repo.data?.reciters ?? []).map { r in (r, all.filter { (ka || $0.isVideo == kv) && $0.reciterId == r.id }.count) }.filter { $0.1 > 0 }, id: \.0.id) { r, n in
                            Button { rec = rec == r.id ? "" : r.id } label: {
                                HStack(spacing: 7) {
                                    RemoteImage(raw: r.image).frame(width: 28, height: 28).clipShape(Circle())
                                    Text(nm(noSheikh(r.name))).font(F.plex(14, .semibold)).foregroundStyle(rec == r.id ? c.onGold : c.text).lineLimit(1)
                                    Text(n.ar).font(F.plex(11)).foregroundStyle(rec == r.id ? c.onGold.opacity(0.7) : c.faint)
                                }.padding(.leading, 5).padding(.trailing, 12).padding(.vertical, 4)
                                .background(Capsule().fill(rec == r.id ? c.gold : c.surface.opacity(0.7))).overlay(Capsule().stroke(rec == r.id ? .clear : c.line))
                            }.buttonStyle(Press())
                        }
                    }.padding(.horizontal, 16)
                }
                HStack {
                    Text(kv ? "\(list.count.ar) \(list.count == 1 ? "تلاوة مرئية" : "تلاوات مرئية")" : tr("{0} تلاوة", list.count.ar) + (rec.isEmpty ? tr(" من {0} قارئ", (repo.data?.reciters.count ?? 0).ar) : tr(" للشيخ {0}", noSheikh(repo.reciter(rec)?.name ?? ""))))
                        .font(F.plex(12.5)).foregroundStyle(c.muted)
                    Spacer()
                    OptMenu(label: "", value: sort, opts: SORTS) { sort = $0 }
                }.padding(.leading, 18).padding(.trailing, 12).padding(.top, 12).padding(.bottom, 4)
                if kv {
                    if list.isEmpty { Empty(text: q.isEmpty ? tr("لا توجد تلاوات مرئية بعد.") : tr("لا توجد نتائج لـ «{0}».", q.trimmingCharacters(in: .whitespaces)), icon: "film") }
                    else {
                        VideoHero(t: list[0]).padding(.horizontal, 16).padding(.vertical, 8)
                        let rest = Array(list.dropFirst())
                        ForEach(Array(stride(from: 0, to: rest.count, by: 2)), id: \.self) { i in
                            HStack(alignment: .top, spacing: 12) { VideoCard(t: rest[i]); if i + 1 < rest.count { VideoCard(t: rest[i + 1]) } else { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) } }.padding(.horizontal, 16).padding(.vertical, 8)
                        }
                    }
                } else {
                    if !audio.isEmpty {
                        HStack(spacing: 10) {
                            GoldButton(title: tr("تشغيل الكل"), icon: "play") { player.play(audio[0], in: audio) }
                            GhostButton(title: tr("عشوائي"), icon: "shuffle") { let sh = audio.shuffled(); player.play(sh[0], in: sh) }
                        }.padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    if list.isEmpty { Empty(text: repo.data == nil ? tr("جارٍ التحميل…") : q.isEmpty ? tr("لا توجد تلاوات بعد.") : tr("لا توجد نتائج لـ «{0}».", q.trimmingCharacters(in: .whitespaces)), icon: "search") }
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                        if grouped && (i == 0 || ageGroup(list[i - 1]) != ageGroup(t)) {
                            Text(ageGroup(t)).font(F.plex(14, .bold)).foregroundStyle(c.gold).padding(.horizontal, 20).padding(.top, i == 0 ? 6 : 18).padding(.bottom, 2)
                        }
                        TrackRow(t: t, list: audio)
                    }
                }
            }.padding(.bottom, 24)
        }
        .refreshable { await repo.refresh() }
        .animation(.easeOut(duration: 0.28), value: kind + rec)
        .task(id: q) { if q.trimmingCharacters(in: .whitespaces).count >= 2 { try? await Task.sleep(nanoseconds: 1_200_000_000); if !Task.isCancelled { Repo.shared.event("search", ["q": q.trimmingCharacters(in: .whitespaces)]) } } }
    }
}

/// «الكل / صوتية / مرئية».
struct KindTabs: View {
    let kind: String; let nAll: Int, nAudio: Int, nVideo: Int; let pick: (String) -> Void
    @Environment(\.pal) private var c
    var body: some View {
        HStack(spacing: 4) {
            ForEach([("all", tr("الكل"), nAll), ("audio", tr("صوتية"), nAudio), ("video", tr("مرئية"), nVideo)], id: \.0) { k, l, n in
                let on = k == kind
                Button { pick(k) } label: {
                    HStack(spacing: 5) {
                        if k == "audio" { Ico(name: "headphones", size: 19.2).foregroundStyle(on ? c.onGold : c.muted) }
                        if k == "video" { SiteIcon(name: "film", size: 19, color: on ? c.onGold : c.muted) }
                        Text(l).font(F.plex(15, .semibold)).foregroundStyle(on ? c.onGold : c.muted)
                        Text(n.ar).font(F.plex(12)).foregroundStyle((on ? c.onGold : c.muted).opacity(0.75))
                    }.frame(maxWidth: .infinity).frame(height: 42).background(RoundedRectangle(cornerRadius: 12).fill(on ? AnyShapeStyle(c.goldBrushV) : AnyShapeStyle(Color.clear)))
                }.buttonStyle(.plain)
            }
        }.padding(5).background(RoundedRectangle(cornerRadius: 16).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 16).stroke(c.line))
    }
}

/// The first video, large.
struct VideoHero: View {
    let t: Track
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    var body: some View {
        let r = Repo.shared.reciter(t.reciterId)
        Button { ui.openWatch(t.id) } label: {
            ZStack {
                RemoteImage(raw: t.cover.isEmpty ? r?.image : t.cover)
                LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0), .init(color: .clear, location: 0.45), .init(color: Color(hex: 0xEB050C0A), location: 1)], startPoint: .top, endPoint: .bottom)
                SiteIcon(name: "play", size: 26, color: .white).frame(width: 62, height: 62).background(Circle().fill(.white.opacity(0.16))).overlay(Circle().stroke(.white.opacity(0.38))).offset(y: -14)
                VStack(alignment: .leading, spacing: 0) {
                    HStack { if isNewTrack(t) { Text(tr("جديد")).font(F.plex(11, .bold)).foregroundStyle(c.onGold).padding(.horizontal, 10).padding(.vertical, 2).background(Capsule().fill(c.goldBrush)) }; Spacer()
                        if !t.durationText.isEmpty { Text(t.durationText).font(F.plex(11, .semibold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.7))) } }
                    Spacer()
                    Text(t.title).font(F.amiri(25)).foregroundStyle(Color(hex: 0xFFFFF7E6)).lineLimit(1)
                    Text([nm(r?.name), t.location].filter { !$0.isEmpty }.joined(separator: " · ")).font(F.plex(12.5)).foregroundStyle(Color(hex: 0xC7ECE4D2)).lineLimit(1)
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }
            .aspectRatio(16 / 8.6, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(c.line))
        }.buttonStyle(Press(scale: 0.98))
    }
}

struct ReciterView: View {
    let id: String
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.pal) private var c
    @State private var sort = "new"
    var body: some View {
        if let r = repo.reciter(id) {
            let list = sortTracks((repo.data?.recitations ?? []).filter { $0.reciterId == id }, sort, repo.data?.plays ?? [:])
            let audio = list.filter { !$0.isVideo }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        ArchImg(raw: r.image).frame(width: 190, height: 246)
                            .background(RadialGradient(colors: [c.gold.opacity(0.18), .clear], center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 190))
                        Text(nm(r.name)).font(F.amiri(28)).foregroundStyle(c.text).multilineTextAlignment(.center).padding(.top, 14)
                        Ornament().padding(.vertical, 4)
                        Text(r.bio.isEmpty ? tr("{0} تلاوة متاحة للاستماع والتنزيل.", list.count.ar) : r.bio).font(F.plex(14)).foregroundStyle(c.muted).multilineTextAlignment(.center)
                        HStack(spacing: 10) {
                            GoldButton(title: tr("تشغيل"), icon: "play") { if let t = audio.first { player.play(t, in: audio) } }
                            GhostButton(title: tr("عشوائي"), icon: "shuffle") { if !audio.isEmpty { let sh = audio.shuffled(); player.play(sh[0], in: sh) } }
                            Chip(text: nil, icon: "share") { share(tr("تلاوات {0}\n{1}reciter/{2}", r.name, Repo.site, Repo.enc(r.id))) }
                        }.padding(.top, 16)
                    }.frame(maxWidth: .infinity).padding(20)
                    let cols = repo.collections(id)
                    if !cols.isEmpty { CollectionsRow(cols: cols, showReciter: false) }
                    HStack { Text(tr("{0} تلاوة", list.count.ar)).font(F.plex(12.5)).foregroundStyle(c.muted); Spacer(); OptMenu(label: "", value: sort, opts: SORTS) { sort = $0 } }.padding(.leading, 18).padding(.trailing, 12).padding(.bottom, 4)
                    if list.isEmpty { Empty(text: tr("لا توجد تلاوات منشورة لهذا القارئ بعد.")) }
                    ForEach(list) { t in TrackRow(t: t, list: audio, showReciter: false) }
                    let others = (repo.data?.reciters ?? []).filter { $0.id != id }
                    if !others.isEmpty { SectionHead(title: tr("قرّاء آخرون")); ReciterRow(rs: others) }
                }.padding(.bottom, 24)
            }
        } else { Empty(text: tr("القارئ غير موجود")) }
    }
}

struct LibraryView: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var store: Store
    @EnvironmentObject var player: AudioPlayer
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var tab = "favs"
    @State private var openList: String?
    @State private var newName = ""
    @State private var askDelete: String?
    var body: some View {
        let s = repo.data?.site
        let tabs = [("favs", tr("المفضلة")), ("later", tr("استمع لاحقًا")), ("recent", tr("السجل")), ("offline", tr("بدون إنترنت")), ("queue", tr("قائمة الانتظار")), ("playlists", tr("قوائمي"))]
            .filter { k, _ in s?.j["features"][["later": "listenLater", "recent": "recentlyPlayed", "offline": "offline", "playlists": "playlists"][k] ?? "_"].bool(true) ?? true }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(tabs, id: \.0) { k, l in Pill(title: l, on: tab == k) { tab = k; openList = nil } } }.padding(16) }
                switch tab {
                case "queue": queue
                case "playlists": lists
                default: plain
                }
            }.padding(.bottom, 20)
        }
        .confirmationDialog(tr("حذف القائمة «{0}»؟", askDelete ?? ""), isPresented: Binding(get: { askDelete != nil }, set: { if !$0 { askDelete = nil } }), titleVisibility: .visible) {
            Button(tr("حذف"), role: .destructive) { store.playlists.removeAll { $0.name == askDelete }; openList = nil; askDelete = nil }
        }
    }
    @ViewBuilder private var plain: some View {
        let ids: [String] = tab == "favs" ? store.favs : tab == "later" ? store.later : tab == "recent" ? store.history : Array(Set(OfflineFiles.ids + VideoFiles.ids))
        let list = ids.compactMap { repo.track($0) }
        if list.isEmpty {
            Empty(text: tab == "favs" ? tr("اضغط على القلب بجانب أي تلاوة لتظهر هنا.") : tab == "later" ? tr("أضف تلاوات لتسمعها لاحقًا من «خيارات أخرى».") : tab == "recent" ? tr("لم تستمع لأي تلاوة بعد.") : tr("احفظ تلاوة من «خيارات أخرى» لتسمعها بدون إنترنت."), icon: tab == "favs" ? "heart" : tab == "later" ? "clock" : tab == "recent" ? "clock.arrow.circlepath" : "arrow.down.circle")
            GhostButton(title: tr("تصفّح التلاوات"), icon: "headphones") { ui.go(.recitations) }.frame(maxWidth: .infinity)
        } else {
            if tab == "offline" { Text(String(format: tr("المساحة المستخدمة: %.1f ميجابايت"), usedMb())).font(F.plex(12)).foregroundStyle(c.muted).padding(.horizontal, 18).padding(.bottom, 6) }
            HStack {
                let audio = list.filter { !$0.isVideo }
                if !audio.isEmpty { playAll(audio) }
                if tab == "recent" { Button(tr("مسح السجل")) { store.history = [] }.font(F.plex(13)).foregroundStyle(c.muted) }
            }.padding(.horizontal, 16).padding(.bottom, 8)
            ForEach(list) { t in TrackRow(t: t, list: list) }
        }
    }
    @ViewBuilder private var queue: some View {
        let up = player.queue.indices.filter { $0 > player.index }
        if up.isEmpty { Empty(text: tr("قائمة الانتظار فارغة. أضف تلاوات من «خيارات أخرى»."), icon: "text.append") }
        else {
            HStack(spacing: 8) {
                Button { player.playAt(up[0]) } label: { Label(tr("تشغيل التالي"), systemImage: "play.fill").font(F.plex(13, .bold)).foregroundStyle(c.onGold).padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(c.gold)) }
                Button { player.clearUpcoming() } label: { Label(tr("مسح القائمة"), systemImage: "trash").font(F.plex(13)).foregroundStyle(c.muted) }
            }.padding(.horizontal, 16).padding(.bottom, 8)
            ForEach(up, id: \.self) { i in
                HStack(spacing: 4) {
                    TrackRow(t: player.queue[i], list: [player.queue[i]])
                    Button { player.move(i, max(player.index + 1, i - 1)) } label: { Ico(name: "arrow.up", size: 20).foregroundStyle(c.muted).frame(width: 34, height: 40) }.accessibilityLabel(tr("تحريك لأعلى"))
                    Button { player.remove(at: i) } label: { Ico(name: "xmark", size: 20).foregroundStyle(c.muted).frame(width: 34, height: 40) }.accessibilityLabel(tr("إزالة")).padding(.trailing, 8)
                }
            }
        }
    }
    @ViewBuilder private var lists: some View {
        if let n = openList, let pl = store.playlists.first(where: { $0.name == n }) {
            let items = pl.ids.compactMap { repo.track($0) }
            HStack(spacing: 8) {
                Pill(title: tr("كل القوائم"), on: false) { openList = nil }
                if !items.isEmpty { playAll(items.filter { !$0.isVideo }) }
                Button { askDelete = n } label: { Label(tr("حذف القائمة"), systemImage: "trash").font(F.plex(13)).foregroundStyle(c.danger) }
            }.padding(.horizontal, 16)
            Text(n).font(F.amiri(24)).foregroundStyle(c.text).padding(.horizontal, 16).padding(.vertical, 8)
            if items.isEmpty { Empty(text: tr("القائمة فارغة — أضف إليها من «خيارات أخرى» بجانب أي تلاوة."), icon: "music.note.list") }
            ForEach(items) { t in
                HStack(spacing: 4) {
                    TrackRow(t: t, list: items)
                    Button { if let i = store.playlists.firstIndex(where: { $0.name == n }) { store.playlists[i].ids.removeAll { $0 == t.id } } } label: { Ico(name: "xmark", size: 20).foregroundStyle(c.muted).frame(width: 34, height: 40) }.accessibilityLabel(tr("إزالة من القائمة")).padding(.trailing, 8)
                }
            }
        } else {
            HStack(spacing: 8) {
                TextField(tr("اسم قائمة جديدة"), text: Binding(get: { newName }, set: { newName = String($0.prefix(40)) })).font(F.plex(15)).padding(12).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                GoldButton(title: tr("إنشاء"), icon: "plus") {
                    let n = newName.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
                    if !store.playlists.contains(where: { $0.name == n }) { store.playlists.append(.init(name: n, ids: [])) }; newName = ""
                }
            }.padding(.horizontal, 16).padding(.bottom, 8)
            if store.playlists.isEmpty { Empty(text: tr("أنشئ قائمة تشغيل خاصة بك، ثم أضف إليها من «خيارات أخرى» بجانب أي تلاوة."), icon: "music.note.list") }
            ForEach(store.playlists) { p in
                Button { openList = p.name } label: {
                    HStack(spacing: 12) {
                        Ico(name: "music.note.list", size: 20).foregroundStyle(c.gold)
                        VStack(alignment: .leading, spacing: 2) { Text(p.name).font(F.plex(15, .semibold)).foregroundStyle(c.text); Text(tr("{0} تلاوة", p.ids.count.ar)).font(F.plex(12)).foregroundStyle(c.muted) }
                        Spacer(); Ico(name: "chevron.left", size: 20).foregroundStyle(c.faint)
                    }.padding(14).background(RoundedRectangle(cornerRadius: 16).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 16).stroke(c.lineSoft))
                }.buttonStyle(Press()).padding(.horizontal, 16).padding(.vertical, 4)
            }
        }
    }
    private func playAll(_ l: [Track]) -> some View {
        Button { if let f = l.first { player.play(f, in: l) } } label: { Label(tr("تشغيل الكل"), systemImage: "play.fill").font(F.plex(13, .bold)).foregroundStyle(c.onGold).padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(c.gold)) }
    }
    private func usedMb() -> Double {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: OfflineFiles.dir, includingPropertiesForKeys: nil)) ?? []) + ((try? fm.contentsOfDirectory(at: VideoFiles.dir, includingPropertiesForKeys: nil)) ?? [])
        return files.reduce(0.0) { $0 + Double(((try? fm.attributesOfItem(atPath: $1.path))?[.size] as? Int) ?? 0) } / 1_048_576
    }
}

/// One search for everything: reciters, recitations, fiqh lessons and surahs (like the Android app).
struct SearchView: View {
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var q = ""
    @FocusState private var focus: Bool
    var body: some View {
        let n = QuranMeta.norm(q.trimmingCharacters(in: .whitespaces))
        let d = repo.data
        let rs = n.isEmpty ? [] : Array((d?.reciters ?? []).filter { QuranMeta.norm($0.name).contains(n) }.prefix(5))
        let ts = n.isEmpty ? [] : Array((d?.recitations ?? []).filter { QuranMeta.norm("\($0.title) \($0.surah) \(repo.reciter($0.reciterId)?.name ?? "") \($0.tags.joined(separator: " ")) \($0.location)").contains(n) }.prefix(15))
        let fs = n.isEmpty ? [] : Array((d?.fiqh ?? []).filter { QuranMeta.norm($0.title).contains(n) }.prefix(5))
        let sn = n.replacingOccurrences(of: "^سوره", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let ss = n.isEmpty ? [] : Array(Quran.surahs.indices.filter { QuranMeta.norm(Quran.surahs[$0]).contains(sn) || "\($0 + 1)" == n }.prefix(4))
        VStack(spacing: 0) {
            SearchField(text: $q, hint: tr("ابحث باسم السورة أو القارئ أو عنوان الدرس")).focused($focus).padding(16)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if n.isEmpty { Empty(text: tr("ابحث باسم السورة أو القارئ أو عنوان الدرس."), icon: "search") }
                    else if rs.isEmpty && ts.isEmpty && fs.isEmpty && ss.isEmpty { Empty(text: tr("لا نتائج لـ «{0}».", q.trimmingCharacters(in: .whitespaces)), icon: "search") }
                    if !rs.isEmpty {
                        SectionHead(title: tr("القرّاء"))
                        ForEach(rs) { r in
                            Button { ui.path.append(.reciter(r.id)) } label: {
                                HStack(spacing: 12) {
                                    RemoteImage(raw: r.image).frame(width: 52, height: 52).clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 1) { Text(nm(r.name)).font(F.plex(14, .semibold)).foregroundStyle(c.text); Text(tr("{0} تلاوة", (d?.recitations.filter { $0.reciterId == r.id }.count ?? 0).ar)).font(F.plex(12.5)).foregroundStyle(c.muted) }
                                    Spacer()
                                }.padding(.horizontal, 18).padding(.vertical, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    if !ss.isEmpty && d?.site.sec("mushaf") != false {
                        SectionHead(title: tr("القرآن الكريم"))
                        ForEach(ss, id: \.self) { i in
                            HStack(spacing: 12) {
                                SurahMedal(n: i + 1, size: 46)
                                VStack(alignment: .leading, spacing: 1) { Text(tr("سورة {0}", Quran.surahs[i])).font(F.plex(14, .semibold)).foregroundStyle(c.text); Text(tr("{0} آية — صفحة {1}", Quran.ayahs[i].ar, Quran.surahPage[i].ar)).font(F.plex(12.5)).foregroundStyle(c.muted) }
                                Spacer()
                                Chip(text: tr("المصحف"), icon: "book") { UserDefaults.standard.set(Quran.surahPage[i], forKey: "mushafPage"); ui.path.append(.mushaf) }
                            }.padding(.horizontal, 18).padding(.vertical, 8).contentShape(Rectangle()).onTapGesture { ui.path.append(.surah(i + 1)) }
                        }
                    }
                    if !ts.isEmpty { SectionHead(title: tr("التلاوات")); ForEach(ts) { TrackRow(t: $0, list: ts) } }
                    if !fs.isEmpty {
                        SectionHead(title: tr("دروس الفقه"))
                        ForEach(fs) { f in
                            Button { ui.go(.fiqh) } label: {
                                HStack(spacing: 12) {
                                    RemoteImage(raw: ytId(f.video).map { "https://i.ytimg.com/vi/\($0)/default.jpg" }).frame(width: 72, height: 52).clipShape(RoundedRectangle(cornerRadius: 14))
                                    VStack(alignment: .leading, spacing: 1) { Text(f.title).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(2); Text(f.teacher).font(F.plex(12.5)).foregroundStyle(c.muted) }
                                    Spacer()
                                }.padding(.horizontal, 18).padding(.vertical, 8)
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(.bottom, 24)
            }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focus = true } }
        .task(id: q) { if q.trimmingCharacters(in: .whitespaces).count >= 2 { try? await Task.sleep(nanoseconds: 1_200_000_000); if !Task.isCancelled { Repo.shared.event("search", ["q": q.trimmingCharacters(in: .whitespaces)]) } } }
    }
}


// MARK: - «المجموعات»
extension Repo {
    /// the collections that have recitations (for one reciter when [rid] is given): the featured first, then the dashboard's order
    func collections(_ rid: String = "") -> [TrackCollection] {
        guard let d = data else { return [] }
        let l = d.site.collections.filter { c in d.recitations.contains { $0.collection == c.id && (rid.isEmpty || $0.reciterId == rid) } }
        return l.filter(\.featured) + l.filter { !$0.featured }
    }
    func collection(_ id: String?) -> TrackCollection? { data?.site.collections.first { $0.id == id } }
    func collectionTracks(_ id: String) -> [Track] { (data?.recitations ?? []).filter { $0.collection == id } }
}
private func colIcon(_ k: String) -> String { ["moon", "book", "mic", "heart", "bookmark"].contains(k) ? k : "calendar" }
private func colHours(_ s: Int) -> String { let h = s / 3600, m = Int((Double(s % 3600) / 60).rounded()); return h > 0 ? (h == 1 ? tr("ساعة") : h == 2 ? tr("ساعتان") : tr("{0} ساعات", h.ar)) : m > 0 ? tr("{0} دقيقة", m.ar) : "" }

/// The collections as a row of cards (the featured one framed in gold), each opening its page.
struct CollectionsRow: View {
    let cols: [TrackCollection]; let showReciter: Bool
    @EnvironmentObject var repo: Repo
    /* UI actions only */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: tr("المجموعات"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(cols) { col in
                        let l = repo.collectionTracks(col.id)
                        let who = showReciter ? (repo.reciter(col.reciterId).map { nm(noSheikh($0.name)) } ?? col.desc) : col.desc
                        let sub = [who, tr("{0} تلاوة", l.count.ar)].filter { !$0.isEmpty }.joined(separator: " · ")
                        Button { ui.path.append(.collection(col.id)) } label: {
                            ZStack(alignment: .topTrailing) {
                                VStack(alignment: .leading, spacing: 0) {
                                    // the cover from the dashboard, in place of the icon
                                    if !col.cover.isEmpty { RemoteImage(raw: col.cover).frame(width: 172, height: 108) }
                                    VStack(alignment: .leading, spacing: 2) {
                                        if col.cover.isEmpty { SiteIcon(name: colIcon(col.icon), size: 20, color: c.gold).frame(width: 38, height: 38).background(RoundedRectangle(cornerRadius: 12).fill(c.gold.opacity(0.14))).padding(.bottom, 8) }
                                        Text(col.name).font(F.plex(15, .bold)).foregroundStyle(c.text).lineLimit(2).multilineTextAlignment(.leading)
                                        Text(sub).font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(1)
                                    }.frame(width: 144, alignment: .leading).padding(14)
                                }
                                if l.contains(where: isNewTrack) { Text(tr("جديد")).font(F.plex(11, .bold)).foregroundStyle(c.onGold).padding(.horizontal, 8).padding(.vertical, 1).background(Capsule().fill(c.goldBrush)).padding(10) }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18)).background(RoundedRectangle(cornerRadius: 18).fill(col.featured ? c.surface2 : c.surface))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(col.featured ? c.gold : c.lineSoft, lineWidth: col.featured ? 1.5 : 1))
                        }.buttonStyle(Press())
                    }
                }.padding(.horizontal, 16).padding(.vertical, 2)
            }
        }
    }
}

/// A collection's page: its name, reciter, count and length; «تشغيل الكل», «حفظ الكل»; the recitations in mushaf order.
struct CollectionView: View {
    let id: String
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var player: AudioPlayer
    @ObservedObject private var dl = DownloadProgress.shared
    /* UI actions only */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var f = "mushaf"
    @State private var savedTick = 0
    var body: some View {
        if let col = repo.collection(id) {
            let all = repo.collectionTracks(id)
            let r = repo.reciter(col.reciterId)
            let _ = savedTick
            let saved = Set(all.filter { OfflineFiles.local($0.id) != nil }.map(\.id))
            let prayer = all.contains { $0.tags.contains("في الصلاة") }
            let base = f == "prayer" ? all.filter { $0.tags.contains("في الصلاة") } : f == "saved" ? all.filter { saved.contains($0.id) } : all
            let list = f == "new" ? base.sorted { $0.stamp > $1.stamp } : base.sorted { ($0.surahNumber > 0 ? $0.surahNumber : 999, $0.stamp) < ($1.surahNumber > 0 ? $1.surahNumber : 999, $1.stamp) }
            let audio = list.filter { !$0.isVideo }
            let todo = all.filter { !$0.isVideo && $0.downloadable && !saved.contains($0.id) }
            let busy = all.contains { dl.of($0.id) != nil }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                    if !col.cover.isEmpty { RemoteImage(raw: col.cover).frame(maxWidth: .infinity).aspectRatio(16 / 7, contentMode: .fit) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("مجموعة")).font(F.plex(12.5, .semibold)).foregroundStyle(c.gold)
                        Text(col.name).font(F.amiri(32)).foregroundStyle(c.text)
                        Text([r.map { nm($0.name) } ?? col.desc, tr("{0} تلاوة", all.count.ar), colHours(all.reduce(0) { $0 + $1.durationSec })].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(F.plex(14)).foregroundStyle(c.muted).padding(.bottom, 14)
                        HStack(spacing: 8) {
                            GoldButton(title: tr("تشغيل الكل"), icon: "play") { if let t = audio.first { player.play(t, in: audio) } }
                            if repo.data?.site.feat("offline") != false && repo.data?.site.allowDownloads != false {
                                GhostButton(title: busy ? tr("جارٍ الحفظ…") : todo.isEmpty ? tr("محفوظة كلها") : tr("حفظ الكل"), icon: "download") {
                                    guard !todo.isEmpty, !busy else { return }
                                    Task { for t in todo { _ = await OfflineFiles.save(t); savedTick += 1 }; ui.say(tr("حُفظت — يمكنك سماعها بدون إنترنت")) }
                                }
                            }
                            Chip(text: nil, icon: "share") { share(tr("{0}\n{1}collection/{2}", col.name, Repo.site, Repo.enc(col.id))) }
                        }
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .background(RoundedRectangle(cornerRadius: 22).fill(c.surface2)).overlay(RoundedRectangle(cornerRadius: 22).stroke(c.line))
                    .padding(16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Pill(title: tr("بترتيب المصحف"), on: f == "mushaf") { f = "mushaf" }
                            Pill(title: tr("الأحدث"), on: f == "new") { f = "new" }
                            if prayer { Pill(title: tr("في الصلاة"), on: f == "prayer") { f = "prayer" } }
                            if !saved.isEmpty { Pill(title: tr("المحفوظة"), on: f == "saved") { f = "saved" } }
                        }.padding(.horizontal, 16)
                    }.padding(.bottom, 6)
                    if list.isEmpty { Empty(text: tr("لا توجد تلاوات هنا.")) }
                    ForEach(list) { t in TrackRow(t: t, list: audio, showReciter: r == nil, inCol: true) }
                }.padding(.bottom, 24)
            }
        } else { Empty(text: tr("المجموعة غير موجودة")) }
    }
}
