import Foundation
import WidgetKit
import UIKit
import SwiftUI

/// Shares with the home-screen widgets (App Group): the prayer times ahead, the ayahs of the coming days, what is playing, the theme.
@MainActor
enum WidgetBridge {
    static let group = "group.com.bawazirquran.app"
    private static var d: UserDefaults? { UserDefaults(suiteName: group) }
    private struct Prayer: Codable { let key: String; let name: String; let at: Double; var iq: Double? = nil }
    private struct WirdW: Codable { let on: Bool; let from: Int; let to: Int; let surah: String; let percent: Int; let khatmas: Int; let done: Bool }
    private struct Ayah: Codable { let day: String; let s: Int; let a: Int; let surah: String; let text: String }
    private struct Now: Codable { let title: String; let sub: String; let playing: Bool; let art: String }
    private struct Pal: Codable { let bg: String, surface: String, text: String, muted: String, gold: String, onGold: String; let dark: Bool }
    private struct PalOpt: Codable { let key: String; let name: String; let pal: Pal }
    private struct TrackOpt: Codable { let id: String; let title: String; let sub: String }
    private static func put<T: Encodable>(_ k: String, _ v: T) { if let x = try? JSONEncoder().encode(v) { d?.set(x, forKey: k) } }

    /// everything (when the app opens)
    /// the daily wird, for its widget
    static func wird() {
        let (f, t) = Wird.range
        put("w_wird", WirdW(on: Wird.on, from: f, to: t, surah: Quran.surahs[Wird.surahOfPage(f) - 1], percent: Wird.percent, khatmas: Wird.khatmas, done: Wird.doneToday))
        WidgetCenter.shared.reloadTimelines(ofKind: "wird")
    }
    static func refreshAll() {
        prayers(); theme(); now(); tracks(); wird()
        Task.detached(priority: .utility) {
            MushafData.load()
            await MainActor.run { ayahs(); WidgetCenter.shared.reloadAllTimelines() }
        }
    }
    static func prayers() {
        let p = Prayers.shared, cal = Calendar.current
        var out: [Prayer] = []
        for k in 0..<3 { if let day = cal.date(byAdding: .day, value: k, to: Date()) {
            for x in p.forDay(day) { out.append(Prayer(key: x.key, name: x.key == "dhuhr" && cal.component(.weekday, from: x.time) == 6 ? tr("الجمعة") : x.name, at: x.time.timeIntervalSince1970, iq: p.iqamaAt(x)?.timeIntervalSince1970)) }
        } }
        put("w_prayers", out); d?.set(p.place, forKey: "w_place")
        for k in ["prayer", "day", "ramadan"] { WidgetCenter.shared.reloadTimelines(ofKind: k) }
    }
    /// the ayah of each of the next 7 days (the same one «آية اليوم» shows)
    static func ayahs() {
        guard MushafData.loaded else { return }
        let cal = Calendar.current, f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let out: [Ayah] = (0..<7).compactMap { k in
            guard let day = cal.date(byAdding: .day, value: k, to: Date()) else { return nil }
            let (s, a) = cal.component(.weekday, from: day) == 6 ? (33, 56) : Quran.daily(Int64(cal.ordinality(of: .day, in: .era, for: day) ?? 1))
            return Ayah(day: f.string(from: day), s: s, a: a, surah: Quran.surahs[s - 1], text: MushafData.text(MushafData.gid(s, a)))
        }
        put("w_ayahs", out)
        // short ones for the lock screen (a few words between the ornate brackets)
        let short: [Ayah] = (0..<7).compactMap { k in
            guard let day = cal.date(byAdding: .day, value: k, to: Date()) else { return nil }
            var seed = Int64(cal.ordinality(of: .day, in: .era, for: day) ?? 1) * 31 + 7
            for _ in 0..<60 {
                let (s, a) = Quran.daily(seed); let t = MushafData.text(MushafData.gid(s, a))
                if (10...58).contains(t.count) { return Ayah(day: f.string(from: day), s: s, a: a, surah: Quran.surahs[s - 1], text: t) }
                seed += 101
            }
            return nil
        }
        put("w_short", short)
        WidgetCenter.shared.reloadTimelines(ofKind: "ayah")
    }
    static func theme() {
        let p = Themes.get(Store.shared.theme)
        func hex(_ c: Color) -> String { var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a); return String(format: "%02X%02X%02X%02X", Int(a * 255), Int(r * 255), Int(g * 255), Int(b * 255)) }
        func pal(_ p: Palette) -> Pal { Pal(bg: hex(p.bg), surface: hex(p.surface), text: hex(p.text), muted: hex(p.muted), gold: hex(p.gold), onGold: hex(p.onGold), dark: p.dark) }
        put("w_pal", pal(p))
        // every palette, so each widget can be given its own colour
        put("w_pals", Themes.all.map { PalOpt(key: $0.key, name: tr($0.name), pal: pal($0)) })
        WidgetCenter.shared.reloadAllTimelines()
    }
    /// the recitations to choose from in the player widget (audio ones, as the site lists them)
    static func tracks() {
        guard let d = Repo.shared.data else { return }
        put("w_tracks", d.recitations.filter { !$0.isVideo }.prefix(400).map { TrackOpt(id: $0.id, title: $0.title, sub: Repo.shared.reciter($0.reciterId)?.name ?? "") })
    }
    private static var lastNow = ""
    private static var lastArt = ""
    static func now() {
        let pl = AudioPlayer.shared
        guard let t = pl.current ?? Store.shared.history.first.flatMap({ Repo.shared.track($0) }) else { return }
        let sub = Repo.shared.reciter(t.reciterId)?.shown ?? ""
        let key = "\(t.id)|\(pl.playing)"
        if key == lastNow { return }
        lastNow = key
        put("w_now", Now(title: t.title, sub: sub, playing: pl.playing, art: t.cover))
        let art = t.cover.isEmpty ? (Repo.shared.reciter(t.reciterId)?.image ?? "") : t.cover
        if art != lastArt, let u = Repo.media(art) {
            lastArt = art
            Task { if let i = await ImageCache.shared.load(u), let small = i.preparingThumbnail(of: CGSize(width: 120, height: 120)), let j = small.jpegData(compressionQuality: 0.8) { d?.set(j, forKey: "w_art"); WidgetCenter.shared.reloadTimelines(ofKind: "player") } }
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "player")
    }
}
