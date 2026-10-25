import SwiftUI

private struct TabDef { let key: String, label: String, icon: String, sec: String? }
private let TAB_DEFS: [TabDef] = [
    TabDef(key: "home", label: "الرئيسية", icon: "house", sec: nil), TabDef(key: "recitations", label: "التلاوات", icon: "mic", sec: "recitations"),
    TabDef(key: "quran", label: "المصحف", icon: "book", sec: "mushaf"), TabDef(key: "adhkar", label: "الأذكار", icon: "circle.hexagongrid", sec: "adhkar"),
    TabDef(key: "community", label: "المجتمع", icon: "bubble.left", sec: "community"), TabDef(key: "library", label: "مكتبتي", icon: "books.vertical", sec: nil),
    TabDef(key: "fiqh", label: "الفقه", icon: "text.book.closed", sec: "fiqh"), TabDef(key: "live", label: "البث", icon: "dot.radiowaves.left.and.right", sec: "live"),
    TabDef(key: "timeline", label: "الخط الزمني", icon: "clock", sec: "timeline"), TabDef(key: "about", label: "عن الشيخ", icon: "person", sec: "about"),
    TabDef(key: "prayer", label: "الصلاة", icon: "clock.badge.checkmark", sec: "prayer"),
]

struct RootView: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var store: Store
    @Environment(\.pal) private var c
    @State private var intro = true
    @State private var onboard = !UserDefaults.standard.bool(forKey: "onboarded")

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
                screen(ui.tab)
                    .navigationDestination(for: Route.self) { r in pushed(r) }
                    .toolbar { topBar }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(c.bg.opacity(0.92), for: .navigationBar)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if repo.offline { Text("بدون اتصال — نعرض آخر بيانات محفوظة").font(F.plex(11.5)).foregroundStyle(c.muted).frame(maxWidth: .infinity).padding(4).background(c.surface) }
                    if player.current != nil { MiniPlayer() }
                    bottomBar
                }
            }
            if ui.drawer { DrawerView().transition(.move(edge: .trailing)) }
            if let t = ui.toast {
                VStack { Spacer(); Text(t).font(F.plex(14, .medium)).foregroundStyle(c.text).padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Capsule().fill(c.surface3)).overlay(Capsule().stroke(c.line)).padding(.bottom, 160) }.transition(.opacity).allowsHitTesting(false)
            }
            if let m = repo.data?.site.maintenance, m.on { Maintenance(title: m.title, message: m.message) }
            else if intro && repo.data?.site.introOn != false { IntroView { withAnimation(.easeOut(duration: 0.5)) { intro = false } } }
            else if onboard { Onboarding { withAnimation { onboard = false } } }
            else if let s = repo.data?.site { AppMessages(site: s) }
        }
        .fullScreenCover(isPresented: $ui.playerOpen) { PlayerView() }
        .sheet(item: $ui.menuFor) { t in TrackMenu(t: t).presentationDetents([.medium, .large]) }
        .sheet(item: $ui.sheet) { k in sheetView(k).presentationDetents([.large]) }
        .animation(.easeInOut(duration: 0.3), value: ui.drawer)
        .task { await repo.refresh(); if let t = repo.data?.site.defaultTheme { store.applyDefaultTheme(t) } }
        .onChange(of: ui.tab) { t in Repo.shared.page = TAB_DEFS.first { $0.key == t }?.label ?? "الرئيسية"; Repo.shared.event("page", ["pageLabel": Repo.shared.page]) }
    }

    @ToolbarContentBuilder private var topBar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                Image("Logo").resizable().scaledToFit().frame(width: 30, height: 30)
                Text(ui.tab == "home" ? "بدر التلاوات" : (TAB_DEFS.first { $0.key == ui.tab }?.label ?? "")).font(F.amiri(20)).foregroundStyle(ui.tab == "home" ? c.gold : c.text)
                Spacer()
            }.frame(maxWidth: .infinity)
        }
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button { ui.path.append(.search) } label: { Image(systemName: "magnifyingglass") }
            Button { ui.sheet = .theme } label: { Image(systemName: "paintpalette") }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.key) { t in
                let sel = ui.tab == t.key && ui.path.isEmpty
                Button { ui.go(Route.tab(t.key) ?? .home) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 19, weight: .medium)).foregroundStyle(c.gold).frame(width: 52, height: 30)
                            .background(Capsule().fill(c.gold.opacity(sel ? 0.16 : 0)))
                        Text(t.label).font(F.plex(10.5, sel ? .bold : .medium)).foregroundStyle(sel ? c.gold : c.text.opacity(0.85)).lineLimit(1)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(Press())
            }
            Button { ui.drawer = true } label: {
                VStack(spacing: 3) { Image(systemName: "line.3.horizontal").font(.system(size: 19, weight: .medium)).foregroundStyle(c.gold).frame(width: 52, height: 30); Text("القائمة").font(F.plex(10.5, .medium)).foregroundStyle(c.text.opacity(0.85)) }.frame(maxWidth: .infinity)
            }.buttonStyle(Press())
        }
        .padding(.top, 6).padding(.bottom, 2)
        .background(LinearGradient(colors: [c.bg2.opacity(0.97), c.bg], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { LinearGradient(colors: [.clear, c.gold.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing).frame(height: 1) }
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
        case .thread(let id): ThreadView(id: id)
        default: screen(r.tabKey ?? "home")
        }
    }
    @ViewBuilder private func sheetView(_ k: SheetKind) -> some View {
        switch k {
        case .prayer: PrayerSettings()
        case .theme: ThemeSheet()
        case .name: NameSheet()
        case .notices: NoticesSheet()
        }
    }
}

/// The site's side menu: every section with its icon in the theme's accent colour.
struct DrawerView: View {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    private struct Item: Identifiable { let id: String, label: String, icon: String, sec: String?, action: () -> Void }
    var body: some View {
        let s = repo.data?.site
        let items: [Item] = [
            Item(id: "home", label: "الرئيسية", icon: "house", sec: nil) { ui.go(.home) },
            Item(id: "recitations", label: "التلاوات", icon: "mic", sec: "recitations") { ui.go(.recitations) },
            Item(id: "quran", label: "المصحف", icon: "book", sec: "mushaf") { ui.go(.quran) },
            Item(id: "adhkar", label: "الأذكار", icon: "circle.hexagongrid", sec: "adhkar") { ui.go(.adhkar) },
            Item(id: "fiqh", label: "دروس الفقه", icon: "text.book.closed", sec: "fiqh") { ui.go(.fiqh) },
            Item(id: "live", label: "البث المباشر", icon: "dot.radiowaves.left.and.right", sec: "live") { ui.go(.live) },
            Item(id: "timeline", label: "الخط الزمني", icon: "clock", sec: "timeline") { ui.go(.timeline) },
            Item(id: "community", label: "المجتمع", icon: "bubble.left", sec: "community") { ui.go(.community) },
            Item(id: "about", label: "عن الشيخ", icon: "person", sec: "about") { ui.go(.about) },
            Item(id: "name", label: "اسمك في التطبيق", icon: "person.text.rectangle", sec: nil) { ui.drawer = false; ui.sheet = .name },
            Item(id: "library", label: "مكتبتي", icon: "books.vertical", sec: nil) { ui.go(.library) },
            Item(id: "prayer", label: "مواقيت الصلاة", icon: "clock.badge.checkmark", sec: "prayer") { ui.go(.prayer) },
            Item(id: "qibla", label: "اتجاه القبلة", icon: "location.north.circle", sec: nil) { ui.drawer = false; ui.path.append(.qibla) },
        ].filter { $0.sec == nil || s?.sec($0.sec!) != false }
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { ui.drawer = false }
            VStack(alignment: .leading, spacing: 0) {
                HStack { Text("القائمة").font(F.plex(17, .bold)); Spacer(); Button { ui.drawer = false } label: { Image(systemName: "xmark").foregroundStyle(c.muted) } }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(items) { it in
                            let sel = ui.tab == it.id && ui.path.isEmpty
                            Button(action: it.action) {
                                HStack(spacing: 16) { Image(systemName: it.icon).font(.system(size: 20)).foregroundStyle(c.gold).frame(width: 26); Text(it.label).font(F.plex(17, .medium)).foregroundStyle(sel ? c.gold : c.text); Spacer() }
                                    .padding(.horizontal, 16).padding(.vertical, 14).background(RoundedRectangle(cornerRadius: 16).fill(c.gold.opacity(sel ? 0.1 : 0)))
                            }.buttonStyle(Press())
                        }
                        Link("سياسة الخصوصية", destination: URL(string: Repo.site + "privacy")!).font(F.plex(12)).foregroundStyle(c.faint).padding(16)
                    }.padding(.horizontal, 12)
                }
            }
            .frame(width: min(UIScreen.main.bounds.width * 0.8, 380)).frame(maxHeight: .infinity)
            .background(c.bg2.ignoresSafeArea())
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
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
