import SwiftUI

struct RecitationsView: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.pal) private var c
    @State private var q = ""
    @State private var reciter = ""
    @State private var sort = "new"
    @State private var kind = ""
    var body: some View {
        let all0 = repo.data?.sortedTracks ?? []
        let hasVideo = all0.contains { $0.isVideo }
        let all = all0.filter { kind.isEmpty || (kind == "video") == $0.isVideo }
        let list = filtered(all)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                QuranFullBanner().padding(.horizontal, 16).padding(.top, 12)
                SearchField(text: $q, hint: "ابحث بالسورة أو القارئ أو المكان").padding(16)
                if hasVideo {
                    HStack(spacing: 8) {
                        Pill(title: "الكل", on: kind.isEmpty) { kind = "" }
                        Pill(title: "صوتية", on: kind == "audio") { kind = "audio" }
                        Pill(title: "مرئية", on: kind == "video") { kind = "video" }
                    }.padding(.horizontal, 16).padding(.bottom, 10)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Pill(title: "الكل", on: reciter.isEmpty) { reciter = "" }
                        ForEach(repo.data?.reciters ?? []) { r in Pill(title: r.name, on: reciter == r.id) { reciter = r.id } }
                    }.padding(.horizontal, 16)
                }
                HStack(spacing: 10) {
                    Menu { Button("الأحدث أولًا") { sort = "new" }; Button("الأقدم أولًا") { sort = "old" }; Button("الأكثر استماعًا") { sort = "top" }; Button("بالترتيب الأبجدي") { sort = "az" } } label: {
                        Label(["new": "الأحدث أولًا", "old": "الأقدم أولًا", "top": "الأكثر استماعًا", "az": "أبجديًا"][sort] ?? "", systemImage: "arrow.up.arrow.down").font(F.plex(13)).foregroundStyle(c.text)
                            .padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().fill(c.surface.opacity(0.7)))
                    }
                    Text("\(list.count.ar) تلاوة").font(F.plex(12.5)).foregroundStyle(c.muted)
                    Spacer()
                    Button { let a = list.filter { !$0.isVideo }; if let t = a.first { player.play(t, in: a) } } label: { Label("تشغيل الكل", systemImage: "play.fill").font(F.plex(13, .bold)).foregroundStyle(c.onGold).padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(c.gold)) }
                }.padding(16)
                if list.isEmpty { Empty(text: "لا توجد تلاوات مطابقة.") }
                ForEach(list) { t in TrackRow(t: t, list: list) }
            }.padding(.bottom, 20)
        }
        .refreshable { await repo.refresh() }
        .onChange(of: q) { v in if v.count >= 2 { Repo.shared.event("search", ["q": v]) } }
    }
    private func filtered(_ all: [Track]) -> [Track] {
        var l = all.filter { reciter.isEmpty || $0.reciterId == reciter }
        let s = q.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { l = l.filter { "\($0.title) \($0.surah) \($0.location) \(repo.reciter($0.reciterId)?.name ?? "") \($0.tags.joined(separator: " "))".contains(s) } }
        switch sort {
        case "old": l.reverse()
        case "top": let p = repo.data?.plays ?? [:]; l.sort { (p[$0.id] ?? 0) > (p[$1.id] ?? 0) }
        case "az": l.sort { $0.title < $1.title }
        default: break
        }
        return l
    }
}

struct ReciterView: View {
    let id: String
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.pal) private var c
    var body: some View {
        let r = repo.reciter(id)
        let list = (repo.data?.sortedTracks ?? []).filter { $0.reciterId == id }
        ScrollView {
            LazyVStack(spacing: 0) {
                RemoteImage(raw: r?.image).frame(width: 200, height: 250).clipShape(ArchShape()).overlay(ArchShape().stroke(c.gold.opacity(0.6), lineWidth: 1.5)).padding(.top, 20)
                Text(r?.name ?? "").font(F.amiri(28)).foregroundStyle(c.text).padding(.top, 12)
                Text("\(list.count.ar) تلاوة").font(F.plex(13)).foregroundStyle(c.gold)
                if let b = r?.bio, !b.isEmpty { Text(b).font(F.plex(14)).foregroundStyle(c.muted).multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 8) }
                HStack { GoldButton(title: "تشغيل الكل", icon: "play.fill") { if let t = list.first { player.play(t, in: list) } }
                         GhostButton(title: "عشوائي", icon: "shuffle") { if let t = list.randomElement() { player.shuffle = true; player.play(t, in: list) } } }.padding(14)
                ForEach(list) { t in TrackRow(t: t, list: list) }
            }.padding(.bottom, 20)
        }
        .background(Backdrop())
        .navigationTitle(r?.name ?? "").navigationBarTitleDisplayMode(.inline)
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
