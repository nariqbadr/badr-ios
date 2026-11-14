import SwiftUI

private struct TabDef { let key: String, label: String, icon: String, sec: String? }
private let TAB_DEFS: [TabDef] = [
    TabDef(key: "home", label: "الرئيسية", icon: "home", sec: nil), TabDef(key: "recitations", label: "التلاوات", icon: "mic", sec: "recitations"),
    TabDef(key: "quran", label: "المصحف", icon: "book", sec: "mushaf"), TabDef(key: "adhkar", label: "الأذكار", icon: "beads", sec: "adhkar"),
    TabDef(key: "community", label: "المجتمع", icon: "chat", sec: "community"), TabDef(key: "library", label: "مكتبتي", icon: "library", sec: nil),
    TabDef(key: "fiqh", label: "الفقه", icon: "scroll", sec: "fiqh"), TabDef(key: "live", label: "البث", icon: "live", sec: "live"),
    TabDef(key: "timeline", label: "الخط الزمني", icon: "clock", sec: "timeline"), TabDef(key: "about", label: "عن الشيخ", icon: "user", sec: "about"),
    TabDef(key: "prayer", label: "الصلاة", icon: "clock", sec: "prayer"),
]

struct RootView: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var store: Store
    @Environment(\.pal) private var c
    /// screenshot runs in the simulator (CI): open this screen straight away, no intro or onboarding
    private static let shot = ProcessInfo.processInfo.environment["BZ_ROUTE"]
    @State private var intro = RootView.shot == nil
    @State private var onboard = RootView.shot == nil && !UserDefaults.standard.bool(forKey: "onboarded")

    private var tabs: [TabDef] {
        let s = repo.data?.site
        let chosen = (s?.tabs ?? ["home", "recitations", "quran", "adhkar", "community"]).compactMap { k in TAB_DEFS.first { $0.key == k } }
            .filter { t in t.sec == nil || s?.sec(t.sec!) != false }.prefix(5)
        return Array(chosen.isEmpty ? [TAB_DEFS[0]] : Array(chosen))
    }

    var body: some View {
        ZStack {
            Backdrop()
            NavigationStack(path: $ui.path) {
                VStack(spacing: 0) {
                    TopBar(home: ui.tab == "home", tab: true, title: TAB_DEFS.first { $0.key == ui.tab }?.label ?? "")
                    screen(ui.tab).frame(maxHeight: .infinity)
                }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { r in
                    VStack(spacing: 0) {
                        if !ui.videoFull { TopBar(home: false, tab: false, title: title(r)) }
                        pushed(r).frame(maxHeight: .infinity)
                    }.toolbar(.hidden, for: .navigationBar).background(Backdrop())
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if repo.offline { Text("بدون اتصال — نعرض آخر بيانات محفوظة").font(F.plex(11.5)).foregroundStyle(c.muted).frame(maxWidth: .infinity).padding(4).background(c.surface) }
                    if player.current != nil { MiniPlayer() }
                    bottomBar
                }
            }
            if ui.drawer { DrawerView() }
            if let t = ui.toast {
                VStack { Spacer(); Text(t).font(F.plex(14, .medium)).foregroundStyle(c.text).padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Capsule().fill(c.surface3)).overlay(Capsule().stroke(c.line)).padding(.bottom, 160) }.transition(.opacity).allowsHitTesting(false)
            }
            if let m = repo.data?.site.maintenance, m.on { Maintenance(title: m.title, message: m.message) }
            else if intro && repo.data?.site.introOn != false { IntroView { withAnimation(.easeOut(duration: 0.5)) { intro = false } } }
            else if onboard { Onboarding { withAnimation { onboard = false } } }
            else if let s = repo.data?.site, RootView.shot == nil { AppMessages(site: s) }
        }
        .fullScreenCover(isPresented: $ui.playerOpen) { PlayerView() }
        .fullScreenCover(item: $ui.adhan) { a in AdhanScreen(key: a.key) }
        .onOpenURL { u in
            // from the home-screen widgets: badr://prayer · badr://ayah/s/a · badr://player · badr://adhkar
            guard u.scheme == "badr" else { return }
            let p = [u.host ?? ""] + u.pathComponents.filter { $0 != "/" }
            ui.drawer = false; ui.sheet = nil
            switch p[0] {
            case "prayer": ui.go(.prayer)
            case "adhkar": ui.go(.adhkar)
            case "player": if player.current != nil { ui.playerOpen = true } else { ui.go(.recitations) }
            case "ayah": if p.count >= 3, let s = Int(p[1]), let a = Int(p[2]) { ui.tab = "quran"; ui.path = [.surah(s * 1000 + a)] }
            default: ui.go(.home)
            }
        }
        .sheet(item: $ui.menuFor) { t in TrackMenu(t: t).presentationDetents([.medium, .large]) }
        .sheet(item: $ui.sheet) { k in sheetView(k).presentationDetents([.large]) }
        .animation(.easeInOut(duration: 0.3), value: ui.drawer)
        .task { await repo.refresh(); if let t = repo.data?.site.defaultTheme { store.applyDefaultTheme(t) }; if let r = RootView.shot { openShot(r) } }
        .onChange(of: ui.tab) { t in Repo.shared.page = TAB_DEFS.first { $0.key == t }?.label ?? "الرئيسية"; Repo.shared.event("page", ["pageLabel": Repo.shared.page]) }
    }

    private func openShot(_ r: String) {
        let d = repo.data
        let firstAudio = d?.recitations.first { !$0.isVideo }
        switch r {
        case "readIndex": ui.path = [.readIndex]
        case "read": if let k = d?.readableTracks.keys.sorted().first { ui.path = [.read("track", k)] }
        case "maker": ui.path = [.maker(0, 0)]
        case "listen": ui.path = [.listen]
        case "mushaf": ui.path = [.mushaf]
        case "search": ui.path = [.search]
        case "surah": ui.path = [.surah(18)]
        case "watch": if let v = d?.recitations.first(where: { $0.isVideo }) { ui.path = [.watch(v.id)] }
        case "clip": if let v = d?.recitations.first(where: { $0.isVideo }) { ui.path = [.clip(v.id)] }
        case "reciter": if let r = d?.reciters.first { ui.path = [.reciter(r.id)] }
        case "player": if let t = firstAudio { player.play(t); ui.playerOpen = true }
        case "drawer": ui.drawer = true
        case "wird": ui.sheet = .wird
        case "ambient": ui.sheet = .ambient
        case "blocked": ui.path = [.blocked]
        case "widgets": ui.path = [.widgets]
        case "adhan": ui.adhan = AdhanKey(key: "fajr")
        default: if let t = Route.tab(r) { ui.go(t) }
        }
    }

    /// the bar's title for a screen opened on top of a tab (like the Android app's)
    private func title(_ r: Route) -> String {
        switch r {
        case .reciter(let id): return repo.reciter(id)?.name ?? "القارئ"
        case .surah(let n): return "سورة \(Quran.surahs[max(0, min(113, n - 1))])"
        case .mushaf: return "المصحف"
        case .search: return "البحث"
        case .qibla: return "اتجاه القبلة"
        case .compose: return "منشور جديد"
        case .user(let h): return "@" + h
        case .people: return "المجتمع"
        case .thread: return "المنشور"
        case .watch: return "تلاوة مرئية"
        case .listen: return "القرآن الكريم كاملًا"
        case .clip: return "اصنع مقطعًا"
        case .maker: return "صانع التصاميم"
        case .blocked: return "الحظر والكتم"
        case .readIndex, .read: return "اقرأ واستمع واحفظ"
        case .widgets: return "الويدجت"
        case .cm(let a): return a == "notifications" ? "الإشعارات" : a.hasPrefix("search") ? "استكشف" : "المجتمع"
        default: return ["recitations": "التلاوات", "quran": "القرآن الكريم", "adhkar": "الأذكار", "library": "مكتبتي", "prayer": "مواقيت الصلاة", "live": "البث المباشر", "fiqh": "دروس الفقه", "about": "عن الشيخ", "timeline": "الخط الزمني", "community": "المجتمع", "home": "الرئيسية"][r.tabKey ?? ""] ?? ""
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.key) { t in
                let sel = ui.tab == t.key && ui.path.isEmpty
                Button { ui.go(Route.tab(t.key) ?? .home) } label: { navItem(t.icon, t.label, sel) }.buttonStyle(Press(scale: 0.92))
            }
            Button { ui.drawer = true } label: { navItem("menu", "القائمة", false) }.buttonStyle(Press(scale: 0.92))
        }
        .padding(.horizontal, 4).padding(.vertical, 6)
        .background(LinearGradient(colors: [c.bg2.opacity(0.97), c.bg.opacity(0.99)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { LinearGradient(colors: [.clear, c.gold.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing).frame(height: 1.2) }
    }
    private func navItem(_ icon: String, _ label: String, _ sel: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Capsule().fill(c.gold.opacity(0.14)).scaleEffect(x: sel ? 1 : 0.5, y: 1).opacity(sel ? 1 : 0)
                SiteIcon(name: icon, size: 24, color: c.gold)
            }.frame(width: 52, height: 32)
            Text(label).font(F.plex(11, sel ? .bold : .medium)).foregroundStyle(sel ? c.gold : c.text.opacity(0.85)).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 4).contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: sel)
    }


    @ViewBuilder private func screen(_ k: String) -> some View {
        switch k {
        case "recitations": RecitationsView()
        case "quran": QuranView()
        case "adhkar": AdhkarView()
        case "community": CommunityView()
        case "library": LibraryView()
        case "fiqh": FiqhView()
        case "live": LiveView()
        case "about": AboutView()
        case "timeline": TimelineScreen()
        case "prayer": PrayerView()
        default: HomeView()
        }
    }
    @ViewBuilder private func pushed(_ r: Route) -> some View {
        switch r {
        case .reciter(let id): ReciterView(id: id)
        case .surah(let s): SurahView(s: s)
        case .mushaf: MushafView()
        case .search: SearchView()
        case .qibla: QiblaView()
        case .compose(let e): ComposeView(embed: e)
        case .user(let h): CommunityView(user: h)
        case .people(let h, let l): PeopleView(handle: h, list: l)
        case .thread(let id): ThreadView(id: id)
        case .watch(let id): WatchView(id: id)
        case .listen: ListenView().navigationTitle("القرآن الكريم كاملًا")
        case .clip(let id): ClipView(trackId: id)
        case .maker(let s, let a): MakerView(s0: s, a0: a)
        case .blocked: BlockedView()
        case .cm(let a): CommunityView(arg: a)
        case .widgets: WidgetsHelpView()
        case .readIndex: ReadIndexView()
        case .read(let a, let b): ReadView(a: a, b: b).id(a + "/" + b)
        default: screen(r.tabKey ?? "home")
        }
    }
    @ViewBuilder private func sheetView(_ k: SheetKind) -> some View {
        switch k {
        case .prayer: PrayerSettings()
        case .theme: ThemeSheet()
        case .wird: WirdSheet()
        case .ambient: AmbientSheet()
        case .name: NameSheet()
        case .notices: NoticesSheet()
        }
    }
}

/// The app bar like the site and the Android app: the emblem and «بدر التلاوات» (gold) on tabs, or back + the title;
/// then search, the notices bell (red dot when there is something new) and the theme.
struct TopBar: View {
    let home: Bool; let tab: Bool; let title: String
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var store: Store
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let unseen = !(repo.data?.notices ?? []).isEmpty && Set((repo.data?.notices ?? []).map(\.id)) != Set(store.str("seenNotices").split(separator: ",").map(String.init))
        HStack(spacing: 0) {
            if !tab {
                Button { if !ui.path.isEmpty { ui.path.removeLast() } else { dismiss() } } label: { Ico(name: "arrow.right", size: 24.0).foregroundStyle(c.text).frame(width: 48, height: 48) }.accessibilityLabel("رجوع")
            } else {
                Image("Logo").resizable().scaledToFit().frame(width: 38, height: 38).padding(.leading, 6).padding(.trailing, 8)
            }
            if home { Text("بدر التلاوات").font(F.amiri(22)).foregroundStyle(c.goldBrushV) }
            else { Text(title).font(F.amiri(21)).foregroundStyle(c.text).lineLimit(1) }
            Spacer(minLength: 4)
            barButton("search", "بحث") { ui.path.append(.search) }
            barButton("bell", "التنبيهات") { store.set("seenNotices", (repo.data?.notices ?? []).map(\.id).joined(separator: ",")); store.objectWillChange.send(); ui.sheet = .notices }
                .overlay(alignment: .topTrailing) { if unseen { Circle().fill(c.danger).frame(width: 8, height: 8).offset(x: -12, y: 12) } }
            barButton("palette", "المظهر") { ui.sheet = .theme }
        }
        .padding(.horizontal, 8).frame(height: 58)
        .background(c.bg.opacity(home ? 0 : 0.92).ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { if !home { LinearGradient(colors: [.clear, c.gold.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing).frame(height: 1) } }
    }
    private func barButton(_ icon: String, _ label: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { SiteIcon(name: icon, size: 24, color: c.text).frame(width: 48, height: 48) }.buttonStyle(Press(scale: 0.9)).accessibilityLabel(label)
    }
}

/// The side menu, as on the site: four quick tiles, then the sections in groups; the current page is highlighted.
struct DrawerView: View {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    @State private var shown = false
    private struct Item: Identifiable { let id: String, label: String, icon: String, sec: String?; var feat: String? = nil; let action: () -> Void }
    var body: some View {
        let s = repo.data?.site
        func ok(_ it: Item) -> Bool { (it.sec == nil || s?.sec(it.sec!) != false) && (it.feat == nil || s?.j["features"][it.feat!].bool(true) != false) && (it.id != "live" || s?.liveOn != false) && (it.id != "listen" || !repo.quranRecs().isEmpty) }
        let quick: [Item] = [
            Item(id: "home", label: "الرئيسية", icon: "home", sec: nil) { ui.go(.home) }, Item(id: "recitations", label: "التلاوات", icon: "mic", sec: "recitations") { ui.go(.recitations) },
            Item(id: "quran", label: "المصحف", icon: "book", sec: "mushaf") { ui.go(.quran) }, Item(id: "prayer", label: "الصلاة", icon: "clock", sec: "prayer") { ui.go(.prayer) },
        ].filter(ok)
        let push: (Route) -> Void = { r in ui.drawer = false; ui.path.append(r) }
        let sheet: (SheetKind) -> Void = { k in ui.drawer = false; ui.sheet = k }
        let groups: [(String, [Item])] = [
            ("القرآن والتلاوات", [Item(id: "listen", label: "القرآن الكريم كاملًا", icon: "play", sec: "mushaf") { push(.listen) }, Item(id: "library", label: "مكتبتي", icon: "library", sec: nil) { ui.go(.library) },
                                  Item(id: "wird", label: "الورد اليومي", icon: "calendar", sec: "mushaf") { sheet(.wird) }, Item(id: "ambient", label: "أصوات هادئة للاستماع", icon: "rain", sec: nil) { sheet(.ambient) }]),
            ("الصلاة والأذكار", [Item(id: "prayer2", label: "مواقيت الصلاة والأذان", icon: "clock", sec: "prayer") { ui.go(.prayer) }, Item(id: "qibla", label: "اتجاه القبلة", icon: "compass", sec: nil, feat: "qibla") { push(.qibla) },
                                 Item(id: "adhkar", label: "الأذكار", icon: "beads", sec: "adhkar") { ui.go(.adhkar) }]),
            ("تعلّم وشارك", [Item(id: "maker", label: "صمّم آية للمشاركة", icon: "image", sec: "maker") { push(.maker(0, 0)) }, Item(id: "live", label: "البث المباشر", icon: "live", sec: "live") { ui.go(.live) },
                             Item(id: "fiqh", label: "دروس الفقه", icon: "scroll", sec: "fiqh") { ui.go(.fiqh) }, Item(id: "community", label: "المجتمع", icon: "chat", sec: "community") { ui.go(.community) }]),
            ("عن الشيخ", [Item(id: "about", label: "عن الشيخ", icon: "user", sec: "about") { ui.go(.about) }, Item(id: "timeline", label: "الخط الزمني", icon: "clock", sec: "timeline") { ui.go(.timeline) }]),
            ("الإعدادات", [Item(id: "theme", label: "المظهر", icon: "palette", sec: nil) { sheet(.theme) }, Item(id: "name", label: "اسمك في التطبيق", icon: "user", sec: nil, feat: "greeting") { sheet(.name) },
                           Item(id: "widgets", label: "الويدجت على الشاشة الرئيسية", icon: "image", sec: nil) { push(.widgets) }]),
        ].map { ($0.0, $0.1.filter(ok)) }.filter { !$0.1.isEmpty }
        func sel(_ id: String) -> Bool { ui.path.isEmpty && (ui.tab == id || (id == "prayer2" && ui.tab == "prayer")) }
        return ZStack(alignment: .leading) {
            Color.black.opacity(shown ? 0.55 : 0).ignoresSafeArea().onTapGesture { close() }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image("Logo").resizable().scaledToFit().frame(width: 34, height: 34)
                    Text("بدر التلاوات").font(F.plex(16, .bold)).foregroundStyle(c.goldBrushV)
                    Spacer()
                    Button { close() } label: { SiteIcon(name: "close", size: 22, color: c.muted).frame(width: 44, height: 44) }.accessibilityLabel("إغلاق")
                }.padding(.leading, 18).padding(.trailing, 8).padding(.top, 8).padding(.bottom, 4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            ForEach(quick) { it in
                                let on = sel(it.id)
                                Button(action: it.action) {
                                    VStack(spacing: 6) { SiteIcon(name: it.icon, size: 22, color: c.gold); Text(it.label).font(F.plex(12, on ? .bold : .medium)).foregroundStyle(on ? c.gold : c.text).lineLimit(1) }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(RoundedRectangle(cornerRadius: 16).fill(on ? c.gold.opacity(0.14) : c.surface)).overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? c.gold.opacity(0.5) : c.lineSoft))
                                }.buttonStyle(Press(scale: 0.95))
                            }
                        }.padding(.top, 4).padding(.bottom, 6)
                        ForEach(groups, id: \.0) { title, items in
                            Text(title).font(F.plex(12.5, .semibold)).foregroundStyle(c.muted).padding(.leading, 6).padding(.top, 14).padding(.bottom, 6)
                            VStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                                    if i > 0 { Rectangle().fill(c.lineSoft).frame(height: 1).padding(.leading, 52) }
                                    Button(action: it.action) {
                                        HStack(spacing: 14) {
                                            SiteIcon(name: it.icon, size: 22, color: c.gold)
                                            Text(it.label).font(F.plex(15.5, .medium)).foregroundStyle(sel(it.id) ? c.gold : c.text).lineLimit(1)
                                            Spacer()
                                            Ico(name: "chevron.left", size: 15.6).foregroundStyle(c.faint)
                                        }.padding(.horizontal, 14).padding(.vertical, 13).background(sel(it.id) ? c.gold.opacity(0.1) : .clear).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }.background(RoundedRectangle(cornerRadius: 18).fill(c.surface)).clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.lineSoft))
                        }
                        Link("سياسة الخصوصية", destination: URL(string: Repo.site + "privacy")!).font(F.plex(12)).foregroundStyle(c.faint).padding(.leading, 8).padding(.top, 16).padding(.bottom, 12)
                    }.padding(.horizontal, 14).padding(.vertical, 4)
                }
            }
            .frame(maxWidth: min(390, UIScreen.main.bounds.width * 0.84), maxHeight: .infinity, alignment: .top)
            .background(c.bg2.ignoresSafeArea())
            .overlay(alignment: .trailing) { Rectangle().fill(c.line).frame(width: 1).ignoresSafeArea() }
            .offset(x: shown ? 0 : -UIScreen.main.bounds.width)   // mirrored in right-to-left: off the right edge
        }
        .onAppear { withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.34)) { shown = true } }
    }
    private func close() { withAnimation(.easeIn(duration: 0.24)) { shown = false }; DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { ui.drawer = false } }
}

struct Maintenance: View {
    let title: String, message: String
    @Environment(\.pal) private var c
    var body: some View {
        ZStack { Backdrop()
            VStack(spacing: 14) {
                Image("Logo").resizable().scaledToFit().frame(width: 90)
                Text(title.isEmpty ? "نجري بعض التحديثات" : title).font(F.amiri(28)).foregroundStyle(c.text)
                Text(message).font(F.plex(16)).foregroundStyle(c.muted).multilineTextAlignment(.center)
            }.padding(32)
        }
    }
}
