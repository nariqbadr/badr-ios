import SwiftUI
import UserNotifications

@main
struct BadrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var repo = Repo.shared
    @StateObject private var store = Store.shared
    @StateObject private var player = AudioPlayer.shared
    @StateObject private var ayah = AyahPlayer.shared
    @StateObject private var prayers = Prayers.shared
    @StateObject private var ui = UIState()
    @StateObject private var cm = Community.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(repo).environmentObject(store).environmentObject(player).environmentObject(ayah)
                .environmentObject(prayers).environmentObject(ui).environmentObject(cm)
                .environment(\.pal, Themes.get(store.theme))
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(Themes.get(store.theme).dark ? .dark : .light)
                .tint(Themes.get(store.theme).gold)
        }
        .onChange(of: phase) { p in
            if p == .active {
                Task { await repo.refresh(); if let t = repo.data?.site.defaultTheme { store.applyDefaultTheme(t) } }
                Repo.shared.event("heartbeat"); prayers.schedule()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Repo.shared.event("view")
        Task { @MainActor in
            while true {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                if UIApplication.shared.applicationState == .active || AudioPlayer.shared.playing { Repo.shared.event("heartbeat") }
            }
        }
        return true
    }
    // show the adhan alert (with its sound) even while the app is open
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .list] }
}

/// Shared UI state: the open menus, sheets and the selected tab.
@MainActor
final class UIState: ObservableObject {
    @Published var tab = "home"
    @Published var path: [Route] = []
    @Published var drawer = false
    @Published var playerOpen = false
    @Published var menuFor: Track?
    @Published var sheet: SheetKind?
    @Published var toast: String?
    private var toastTask: Task<Void, Never>?

    func go(_ r: Route) {
        if let t = r.tabKey { tab = t; path = [] } else { path.append(r) }
        drawer = false
    }
    func say(_ s: String) {
        toastTask?.cancel(); withAnimation { toast = s }
        toastTask = Task { try? await Task.sleep(nanoseconds: 2_600_000_000); if !Task.isCancelled { withAnimation { toast = nil } } }
    }
}

enum SheetKind: String, Identifiable { case prayer, theme, name, notices; var id: String { rawValue } }

enum Route: Hashable {
    case home, recitations, quran, adhkar, community, library, fiqh, live, about, timeline, prayer, search, qibla
    case reciter(String), surah(Int), mushaf, compose(String), user(String), people(String, String), thread(Int)
    var tabKey: String? {
        switch self { case .home: return "home"; case .recitations: return "recitations"; case .quran: return "quran"; case .adhkar: return "adhkar"; case .community: return "community"
        case .library: return "library"; case .fiqh: return "fiqh"; case .live: return "live"; case .about: return "about"; case .timeline: return "timeline"; case .prayer: return "prayer"; default: return nil }
    }
    static func tab(_ k: String) -> Route? {
        ["home": .home, "recitations": .recitations, "quran": .quran, "adhkar": .adhkar, "community": .community, "library": .library,
         "fiqh": .fiqh, "live": .live, "about": .about, "timeline": .timeline, "prayer": .prayer][k]
    }
}
