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
    @StateObject private var lang = Lang.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView().modifier(AutoTrHost())
                .environmentObject(repo).environmentObject(store).environmentObject(player).environmentObject(ayah)
                .environmentObject(prayers).environmentObject(ui).environmentObject(cm).environmentObject(lang)
                .environment(\.pal, Themes.get(store.theme))
                .environment(\.layoutDirection, lang.direction)
                .environment(\.locale, L.locale)
                // a new language draws the whole app again in it
                .id(lang.code)
                .preferredColorScheme(Themes.get(store.theme).dark ? .dark : .light)
                .tint(Themes.get(store.theme).gold)
        }
        .onChange(of: phase) { p in
            if p == .active {
                Task { await repo.refresh(); if let t = repo.data?.site.defaultTheme { store.applyDefaultTheme(t) } }
                Repo.shared.event("heartbeat")
                // the rest waits a moment: coming back (or returning from the floating video) answers at once
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    Haram.schedule()
                    await Adhan.prepare(); prayers.schedule()
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    WidgetBridge.refreshAll()
                }
                // the Mushaf's pages read ahead in the background: it opens at once
                Task.detached(priority: .utility) { MushafData.load() }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// portrait, except while a video is in full screen
    static var orientation: UIInterfaceOrientationMask = .portrait
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { AppDelegate.orientation }
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
    // the adhan while the app is open: the full-screen adhan plays the whole adhan instead of the 30 s sound
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // the test from the settings: shown as it arrives, with the adhan's own sound (the settings sheet stays open)
        if notification.request.identifier == "adhan-test" || notification.request.identifier == "iqama-test" { return [.banner, .sound, .list] }
        if let k = notification.request.content.userInfo["adhan"] as? String {
            await MainActor.run { UIState.shared?.adhan = AdhanKey(key: k); AdhanPlayer.shared.play(fajr: k == "fajr") }
            return [.banner, .list]
        }
        return [.banner, .sound, .list]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        await MainActor.run {
            // a tap on the adhan notification: the whole adhan plays at once — the 30 s the notification sounded are not
            // the whole adhan (it opened the adhan screen only, and play had to be pressed)
            if let k = info["adhan"] as? String {
                // exactly as «تشغيل الأذان» on its screen; opened from a closed app the screen comes once the app is drawn
                Task { @MainActor in
                    for _ in 0..<30 where UIState.shared == nil { try? await Task.sleep(nanoseconds: 100_000_000) }
                    UIState.shared?.adhan = AdhanKey(key: k)
                    if !AdhanPlayer.shared.playing { AdhanPlayer.shared.play(fajr: k == "fajr") }
                }
            }
            else if let k = info["iqama"] as? String { UIState.shared?.adhan = AdhanKey(key: k, iqama: true) }
            else if info["open"] as? String == "wird" { UIState.shared?.sheet = .wird }
            else if info["open"] as? String == "mosques", mosquesOn { UIState.shared?.path = [.mosques] }
            else if let o = info["open"] as? String, o.hasPrefix("live/") { UIState.shared?.path = [.liveAt(String(o.dropFirst(5)))] }
        }
    }
}

/// Shared UI state: the open menus, sheets and the selected tab.
@MainActor
final class UIState: ObservableObject {
    /// a video recitation: from another video's page it takes that page's place (it piled up page over page before)
    func openWatch(_ id: String) {
        if case .watch = path.last { path[path.count - 1] = .watch(id) } else { path.append(.watch(id)) }
    }
    @Published var tab = "home"
    @Published var path: [Route] = []
    @Published var drawer = false
    @Published var playerOpen = false
    @Published var menuFor: Track?
    @Published var sheet: SheetKind?
    @Published var toast: String?
    /// the full-screen adhan (from its notification, or «تجربة»)
    @Published var adhan: AdhanKey?
    /// a video in full screen: the app bar is hidden
    @Published var videoFull = false
    private var toastTask: Task<Void, Never>?
    /// for code outside the views (the video engine, downloads)
    static var shared: UIState?
    init() { UIState.shared = self }

    func go(_ r: Route) {
        if let t = r.tabKey { tab = t; path = [] } else { path.append(r) }
        drawer = false
    }
    func say(_ s: String) {
        toastTask?.cancel(); withAnimation { toast = s }
        toastTask = Task { try? await Task.sleep(nanoseconds: 2_600_000_000); if !Task.isCancelled { withAnimation { toast = nil } } }
    }
}

enum SheetKind: String, Identifiable { case prayer, theme, name, notices, wird, ambient, lang; var id: String { rawValue } }

enum Route: Hashable {
    case home, recitations, quran, adhkar, community, library, fiqh, live, about, timeline, prayer, search, qibla
    case reciter(String), collection(String), surah(Int), mushaf, compose(String), user(String), people(String, String), thread(Int)
    case watch(String), clip(String), listen, maker(Int, Int), blocked, readIndex, read(String, String), cm(String), widgets
    case imams(String), imamAlerts, liveAt(String), mosques
    var tabKey: String? {
        switch self { case .home: return "home"; case .recitations: return "recitations"; case .quran: return "quran"; case .adhkar: return "adhkar"; case .community: return "community"
        case .library: return "library"; case .fiqh: return "fiqh"; case .live: return "live"; case .about: return "about"; case .timeline: return "timeline"; case .prayer: return "prayer"; default: return nil }
    }
    /// a link to the site → the matching screen (/recitations/, /track/x, /reciter/x, /quran/18 …)
    @MainActor static func fromSite(_ u: String) -> Route? {
        guard let url = URL(string: u) else { return nil }
        let p = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        switch p.first ?? "" {
        case "": return .home
        case "track": return p.count > 1 ? (Repo.shared.track(p[1])?.isVideo == true ? .watch(p[1]) : .recitations) : .recitations
        case "reciter": return p.count > 1 ? .reciter(p[1]) : .recitations
        case "collection": return p.count > 1 ? .collection(p[1]) : .recitations
        case "quran", "surah": return p.count > 1 ? Int(p[1]).map { .surah($0) } ?? .quran : .quran
        case "mushaf": return .mushaf
        case "community": return p.count > 2 && p[1] == "p" ? Int(p[2]).map { .thread($0) } : .community
        case "read": return .readIndex
        case "maker": return .maker(0, 0)
        case "mosques": return mosquesOn ? .mosques : tab("prayer")
        default: return tab(p[0])
        }
    }
    static func tab(_ k: String) -> Route? {
        ["home": .home, "recitations": .recitations, "quran": .quran, "adhkar": .adhkar, "community": .community, "library": .library,
         "fiqh": .fiqh, "live": .live, "about": .about, "timeline": .timeline, "prayer": .prayer][k]
    }
}

/// The app bar is drawn by the app (like the Android app), so the system bar is hidden: keep the swipe-back gesture.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() { super.viewDidLoad(); interactivePopGestureRecognizer?.delegate = self }
    public func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { viewControllers.count > 1 }
}
