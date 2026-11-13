import SwiftUI

let SORTS: [(String, String)] = [("new", "الأحدث"), ("popular", "الأكثر استماعًا"), ("surah", "ترتيب المصحف"), ("order", "الترتيب"), ("az", "أبجدي")]
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
    @EnvironmentObject var ui: UIState
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
                SearchField(text: $q, hint: "ابحث بالسورة أو القارئ أو المكان").padding(.horizontal, 16).padding(.vertical, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Pill(title: "الكل", on: rec.isEmpty) { rec = "" }
                        ForEach((repo.data?.reciters ?? []).map { r in (r, all.filter { (ka || $0.isVideo == kv) && $0.reciterId == r.id }.count) }.filter { $0.1 > 0 }, id: \.0.id) { r, n in
                            Button { rec = rec == r.id ? "" : r.id } label: {
                                HStack(spacing: 7) {
                                    RemoteImage(raw: r.image).frame(width: 28, height: 28).clipShape(Circle())
                                    Text(noSheikh(r.name)).font(F.plex(14, .semibold)).foregroundStyle(rec == r.id ? c.onGold : c.text).lineLimit(1)
                                    Text(n.ar).font(F.plex(11)).foregroundStyle(rec == r.id ? c.onGold.opacity(0.7) : c.faint)
                                }.padding(.leading, 5).padding(.trailing, 12).padding(.vertical, 4)
                                .background(Capsule().fill(rec == r.id ? c.gold : c.surface.opacity(0.7))).overlay(Capsule().stroke(rec == r.id ? .clear : c.line))
                            }.buttonStyle(Press())
                        }
                    }.padding(.horizontal, 16)
                }
                HStack {
                    Text(kv ? "\(list.count.ar) \(list.count == 1 ? "تلاوة مرئية" : "تلاوات مرئية")" : "\(list.count.ar) تلاوة" + (rec.isEmpty ? " من \((repo.data?.reciters.count ?? 0).ar) قارئ" : " للشيخ \(noSheikh(repo.reciter(rec)?.name ?? ""))"))
                        .font(F.plex(12.5)).foregroundStyle(c.muted)
                    Spacer()
                    OptMenu(label: "", value: sort, opts: SORTS) { sort = $0 }
                }.padding(.leading, 18).padding(.trailing, 12).padding(.top, 12).padding(.bottom, 4)
                if kv {
                    if list.isEmpty { Empty(text: q.isEmpty ? "لا توجد تلاوات مرئية بعد." : "لا توجد نتائج لـ «\(q.trimmingCharacters(in: .whitespaces))».", icon: "film") }
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
                            GoldButton(title: "تشغيل الكل", icon: "play") { player.play(audio[0], in: audio) }
                            GhostButton(title: "عشوائي", icon: "shuffle") { let sh = audio.shuffled(); player.play(sh[0], in: sh) }
                        }.padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    if list.isEmpty { Empty(text: repo.data == nil ? "جارٍ التحميل…" : q.isEmpty ? "لا توجد تلاوات بعد." : "لا توجد نتائج لـ «\(q.trimmingCharacters(in: .whitespaces))».", icon: "search") }
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
            ForEach([("all", "الكل", nAll), ("audio", "صوتية", nAudio), ("video", "مرئية", nVideo)], id: \.0) { k, l, n in
                let on = k == kind
                Button { pick(k) } label: {
                    HStack(spacing: 5) {
                        if k == "audio" { Image(systemName: "headphones").font(.system(size: 16)).foregroundStyle(on ? c.onGold : c.muted) }
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
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    var body: some View {
        let r = Repo.shared.reciter(t.reciterId)
        Button { ui.path.append(.watch(t.id)) } label: {
            ZStack {
                RemoteImage(raw: t.cover.isEmpty ? r?.image : t.cover)
                LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0), .init(color: .clear, location: 0.45), .init(color: Color(hex: 0xEB050C0A), location: 1)], startPoint: .top, endPoint: .bottom)
                SiteIcon(name: "play", size: 26, color: .white).frame(width: 62, height: 62).background(Circle().fill(.white.opacity(0.16))).overlay(Circle().stroke(.white.opacity(0.38))).offset(y: -14)
                VStack(alignment: .leading, spacing: 0) {
                    HStack { if isNewTrack(t) { Text("جديد").font(F.plex(11, .bold)).foregroundStyle(c.onGold).padding(.horizontal, 10).padding(.vertical, 2).background(Capsule().fill(c.goldBrush)) }; Spacer()
                        if !t.durationText.isEmpty { Text(t.durationText).font(F.plex(11, .semibold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.7))) } }
                    Spacer()
                    Text(t.title).font(F.amiri(25)).foregroundStyle(Color(hex: 0xFFFFF7E6)).lineLimit(1)
                    Text([r?.name ?? "", t.location].filter { !$0.isEmpty }.joined(separator: " · ")).font(F.plex(12.5)).foregroundStyle(Color(hex: 0xC7ECE4D2)).lineLimit(1)
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
                        Text(r.name).font(F.amiri(28)).foregroundStyle(c.text).multilineTextAlignment(.center).padding(.top, 14)
                        Ornament().padding(.vertical, 4)
                        Text(r.bio.isEmpty ? "\(list.count.ar) تلاوة متاحة للاستماع والتنزيل." : r.bio).font(F.plex(14)).foregroundStyle(c.muted).multilineTextAlignment(.center)
                        HStack(spacing: 10) {
                            GoldButton(title: "تشغيل", icon: "play") { if let t = audio.first { player.play(t, in: audio) } }
                            GhostButton(title: "عشوائي", icon: "shuffle") { if !audio.isEmpty { let sh = audio.shuffled(); player.play(sh[0], in: sh) } }
                            Chip(text: nil, icon: "share") { share("تلاوات \(r.name)\n\(Repo.site)reciter/\(Repo.enc(r.id))") }
                        }.padding(.top, 16)
                    }.frame(maxWidth: .infinity).padding(20)
                    HStack { Text("\(list.count.ar) تلاوة").font(F.plex(12.5)).foregroundStyle(c.muted); Spacer(); OptMenu(label: "", value: sort, opts: SORTS) { sort = $0 } }.padding(.leading, 18).padding(.trailing, 12).padding(.bottom, 4)
                    if list.isEmpty { Empty(text: "لا توجد تلاوات منشورة لهذا القارئ بعد.") }
                    ForEach(list) { t in TrackRow(t: t, list: audio, showReciter: false) }
                    let others = (repo.data?.reciters ?? []).filter { $0.id != id }
                    if !others.isEmpty { SectionHead(title: "قرّاء آخرون"); ReciterRow(rs: others) }
                }.padding(.bottom, 24)
            }
        } else { Empty(text: "القارئ غير موجود") }
    }
}

struct LibraryView: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var store: Store
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var tab = "favs"
    @State private var openList: String?
    @State private var newName = ""
    @State private var askDelete: String?
    var body: some View {
        let s = repo.data?.site
        let tabs = [("favs", "المفضلة"), ("later", "استمع لاحقًا"), ("recent", "السجل"), ("offline", "بدون إنترنت"), ("queue", "قائمة الانتظار"), ("playlists", "قوائمي")]
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
        .confirmationDialog("حذف القائمة «\(askDelete ?? "")»؟", isPresented: Binding(get: { askDelete != nil }, set: { if !$0 { askDelete = nil } }), titleVisibility: .visible) {
            Button("حذف", role: .destructive) { store.playlists.removeAll { $0.name == askDelete }; openList = nil; askDelete = nil }
        }
    }
    @ViewBuilder private var plain: some View {
        let ids: [String] = tab == "favs" ? store.favs : tab == "later" ? store.later : tab == "recent" ? store.history : Array(Set(OfflineFiles.ids + VideoFiles.ids))
        let list = ids.compactMap { repo.track($0) }
        if list.isEmpty {
            Empty(text: tab == "favs" ? "اضغط على القلب بجانب أي تلاوة لتظهر هنا." : tab == "later" ? "أضف تلاوات لتسمعها لاحقًا من «خيارات أخرى»." : tab == "recent" ? "لم تستمع لأي تلاوة بعد." : "احفظ تلاوة من «خيارات أخرى» لتسمعها بدون إنترنت.", icon: tab == "favs" ? "heart" : tab == "later" ? "clock" : tab == "recent" ? "clock.arrow.circlepath" : "arrow.down.circle")
            GhostButton(title: "تصفّح التلاوات", icon: "headphones") { ui.go(.recitations) }.frame(maxWidth: .infinity)
        } else {
            if tab == "offline" { Text(String(format: "المساحة المستخدمة: %.1f ميجابايت", usedMb())).font(F.plex(12)).foregroundStyle(c.muted).padding(.horizontal, 18).padding(.bottom, 6) }
            HStack {
                let audio = list.filter { !$0.isVideo }
                if !audio.isEmpty { playAll(audio) }
                if tab == "recent" { Button("مسح السجل") { store.history = [] }.font(F.plex(13)).foregroundStyle(c.muted) }
            }.padding(.horizontal, 16).padding(.bottom, 8)
            ForEach(list) { t in TrackRow(t: t, list: list) }
        }
    }
    @ViewBuilder private var queue: some View {
        let up = player.queue.indices.filter { $0 > player.index }
        if up.isEmpty { Empty(text: "قائمة الانتظار فارغة. أضف تلاوات من «خيارات أخرى».", icon: "text.append") }
        else {
            HStack(spacing: 8) {
                Button { player.playAt(up[0]) } label: { Label("تشغيل التالي", systemImage: "play.fill").font(F.plex(13, .bold)).foregroundStyle(c.onGold).padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(c.gold)) }
                Button { player.clearUpcoming() } label: { Label("مسح القائمة", systemImage: "trash").font(F.plex(13)).foregroundStyle(c.muted) }
            }.padding(.horizontal, 16).padding(.bottom, 8)
            ForEach(up, id: \.self) { i in
                HStack(spacing: 4) {
                    TrackRow(t: player.queue[i], list: [player.queue[i]])
                    Button { player.move(i, max(player.index + 1, i - 1)) } label: { Image(systemName: "arrow.up").foregroundStyle(c.muted).frame(width: 34, height: 40) }.accessibilityLabel("تحريك لأعلى")
                    Button { player.remove(at: i) } label: { Image(systemName: "xmark").foregroundStyle(c.muted).frame(width: 34, height: 40) }.accessibilityLabel("إزالة").padding(.trailing, 8)
                }
            }
        }
    }
    @ViewBuilder private var lists: some View {
        if let n = openList, let pl = store.playlists.first(where: { $0.name == n }) {
            let items = pl.ids.compactMap { repo.track($0) }
            HStack(spacing: 8) {
                Pill(title: "كل القوائم", on: false) { openList = nil }
                if !items.isEmpty { playAll(items.filter { !$0.isVideo }) }
                Button { askDelete = n } label: { Label("حذف القائمة", systemImage: "trash").font(F.plex(13)).foregroundStyle(c.danger) }
            }.padding(.horizontal, 16)
            Text(n).font(F.amiri(24)).foregroundStyle(c.text).padding(.horizontal, 16).padding(.vertical, 8)
            if items.isEmpty { Empty(text: "القائمة فارغة — أضف إليها من «خيارات أخرى» بجانب أي تلاوة.", icon: "music.note.list") }
            ForEach(items) { t in
                HStack(spacing: 4) {
                    TrackRow(t: t, list: items)
                    Button { if let i = store.playlists.firstIndex(where: { $0.name == n }) { store.playlists[i].ids.removeAll { $0 == t.id } } } label: { Image(systemName: "xmark").foregroundStyle(c.muted).frame(width: 34, height: 40) }.accessibilityLabel("إزالة من القائمة").padding(.trailing, 8)
                }
            }
        } else {
            HStack(spacing: 8) {
                TextField("اسم قائمة جديدة", text: Binding(get: { newName }, set: { newName = String($0.prefix(40)) })).font(F.plex(15)).padding(12).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                GoldButton(title: "إنشاء", icon: "plus") {
                    let n = newName.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
                    if !store.playlists.contains(where: { $0.name == n }) { store.playlists.append(.init(name: n, ids: [])) }; newName = ""
                }
            }.padding(.horizontal, 16).padding(.bottom, 8)
            if store.playlists.isEmpty { Empty(text: "أنشئ قائمة تشغيل خاصة بك، ثم أضف إليها من «خيارات أخرى» بجانب أي تلاوة.", icon: "music.note.list") }
            ForEach(store.playlists) { p in
                Button { openList = p.name } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note.list").foregroundStyle(c.gold)
                        VStack(alignment: .leading, spacing: 2) { Text(p.name).font(F.plex(15, .semibold)).foregroundStyle(c.text); Text("\(p.ids.count.ar) تلاوة").font(F.plex(12)).foregroundStyle(c.muted) }
                        Spacer(); Image(systemName: "chevron.left").foregroundStyle(c.faint)
                    }.padding(14).background(RoundedRectangle(cornerRadius: 16).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 16).stroke(c.lineSoft))
                }.buttonStyle(Press()).padding(.horizontal, 16).padding(.vertical, 4)
            }
        }
    }
    private func playAll(_ l: [Track]) -> some View {
        Button { if let f = l.first { player.play(f, in: l) } } label: { Label("تشغيل الكل", systemImage: "play.fill").font(F.plex(13, .bold)).foregroundStyle(c.onGold).padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(c.gold)) }
    }
    private func usedMb() -> Double {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: OfflineFiles.dir, includingPropertiesForKeys: nil)) ?? []) + ((try? fm.contentsOfDirectory(at: VideoFiles.dir, includingPropertiesForKeys: nil)) ?? [])
        return files.reduce(0.0) { $0 + Double(((try? fm.attributesOfItem(atPath: $1.path))?[.size] as? Int) ?? 0) } / 1_048_576
    }
}

struct SearchView: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var q = ""
    var body: some View {
        let s = q.trimmingCharacters(in: .whitespaces)
        let tracks = s.count < 2 ? [] : (repo.data?.sortedTracks ?? []).filter { "\($0.title) \($0.surah) \(repo.reciter($0.reciterId)?.name ?? "")".contains(s) }
        let surahs = s.isEmpty ? [] : Quran.surahs.enumerated().filter { $0.element.contains(s) || "\($0.offset + 1)" == s }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                TextField("ابحث في التلاوات والسور…", text: $q).font(F.plex(16)).padding(14).background(RoundedRectangle(cornerRadius: 16).fill(c.surface)).padding(16)
                if !surahs.isEmpty { SectionHead(title: "السور")
                    ForEach(surahs, id: \.offset) { i, n in Button { ui.path.append(.surah(i + 1)) } label: { HStack { Text("سورة \(n)").font(F.plex(15)); Spacer(); Text((i + 1).ar).foregroundStyle(c.gold) }.padding(.horizontal, 20).padding(.vertical, 10) }.buttonStyle(.plain) } }
                if !tracks.isEmpty { SectionHead(title: "التلاوات"); ForEach(tracks) { TrackRow(t: $0, list: tracks) } }
                if s.count >= 2 && tracks.isEmpty && surahs.isEmpty { Empty(text: "لا توجد نتائج.", icon: "magnifyingglass") }
            }
        }
        .background(Backdrop()).navigationTitle("البحث").navigationBarTitleDisplayMode(.inline)
        .onChange(of: q) { v in if v.count >= 2 { Repo.shared.event("search", ["q": v]) } }
    }
}
