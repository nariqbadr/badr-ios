import Foundation
import SwiftUI

/// Everything kept on the phone: favourites, history, positions, settings (UserDefaults).
@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    private let d = UserDefaults.standard

    @Published var theme: String { didSet { d.set(theme, forKey: "theme"); themeChosen = true; d.set(true, forKey: "themeChosen"); WidgetBridge.theme() } }
    private(set) var themeChosen: Bool
    @Published var name: String { didSet { d.set(name, forKey: "name") } }
    @Published var favs: [String] { didSet { d.set(favs, forKey: "favs") } }
    @Published var later: [String] { didSet { d.set(later, forKey: "later") } }
    @Published var history: [String] { didSet { d.set(history, forKey: "history") } }
    @Published var speed: Float { didSet { d.set(speed, forKey: "speed") } }
    @Published var ayahReciter: String { didSet { d.set(ayahReciter, forKey: "ayahReciter") } }
    /// «قوائمي»: the person's own playlists, in the order they were made
    @Published var playlists: [Playlist] { didSet { if let x = try? JSONEncoder().encode(playlists) { d.set(x, forKey: "playlists") } } }
    struct Playlist: Codable, Hashable, Identifiable { var name: String; var ids: [String]; var id: String { name } }
    func addToPlaylist(_ name: String, _ id: String) -> Bool {
        let n = String(name.trimmingCharacters(in: .whitespaces).prefix(40)); guard !n.isEmpty else { return false }
        if let i = playlists.firstIndex(where: { $0.name == n }) { if playlists[i].ids.contains(id) { return false }; playlists[i].ids.append(id) } else { playlists.append(Playlist(name: n, ids: [id])) }
        return true
    }
    let visitorId: String

    private init() {
        theme = d.string(forKey: "theme") ?? "dark"
        themeChosen = d.bool(forKey: "themeChosen")
        name = d.string(forKey: "name") ?? ""
        favs = d.stringArray(forKey: "favs") ?? []
        later = d.stringArray(forKey: "later") ?? []
        history = d.stringArray(forKey: "history") ?? []
        speed = d.object(forKey: "speed") as? Float ?? 1
        ayahReciter = d.string(forKey: "ayahReciter") ?? ""
        playlists = (d.data(forKey: "playlists")).flatMap { try? JSONDecoder().decode([Playlist].self, from: $0) } ?? []
        if let v = d.string(forKey: "visitor") { visitorId = v } else {
            let v = "ios-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20).lowercased()
            d.set(v, forKey: "visitor"); visitorId = v
        }
    }

    /// The dashboard's default theme, until the user picks one.
    func applyDefaultTheme(_ t: String) {
        if !themeChosen, Themes.all.contains(where: { $0.key == t }), theme != t { theme = t; themeChosen = false; d.set(false, forKey: "themeChosen") }
    }

    func toggleFav(_ id: String) { if let i = favs.firstIndex(of: id) { favs.remove(at: i) } else { favs.insert(id, at: 0) } }
    @discardableResult func toggleLater(_ id: String) -> Bool { if let i = later.firstIndex(of: id) { later.remove(at: i); return false }; later.insert(id, at: 0); return true }
    func addHistory(_ id: String) { history.removeAll { $0 == id }; history.insert(id, at: 0); if history.count > 100 { history = Array(history.prefix(100)) } }

    // playback position per recitation (resume where you stopped)
    func savePosition(_ id: String, _ sec: Double, _ dur: Double) {
        var p = d.dictionary(forKey: "positions") as? [String: Double] ?? [:]
        if dur > 0, sec > 10, sec < dur - 15 { p[id] = sec } else { p.removeValue(forKey: id) }
        d.set(p, forKey: "positions")
    }
    func position(_ id: String) -> Double { (d.dictionary(forKey: "positions") as? [String: Double])?[id] ?? 0 }

    func str(_ k: String, _ def: String = "") -> String { d.string(forKey: k) ?? def }
    func set(_ k: String, _ v: String) { d.set(v, forKey: k) }
    func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    func set(_ k: String, _ v: Bool) { d.set(v, forKey: k) }
    func double(_ k: String) -> Double? { d.object(forKey: k) as? Double }
    func set(_ k: String, _ v: Double) { d.set(v, forKey: k) }
}
