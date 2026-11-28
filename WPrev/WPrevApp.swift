import SwiftUI
import WidgetKit

/// Tests only (never shipped): draws the widgets' views to pictures, so they can be seen without a home screen.
@main
struct WPrevApp: App {
    var body: some Scene { WindowGroup { Shots() } }
}

private struct Frame<V: View>: View {
    let w: CGFloat, h: CGFloat, bg: Color, radius: CGFloat; let v: V
    var body: some View {
        v.padding(radius > 20 ? 16 : 6).frame(width: w, height: h).background(bg).clipShape(RoundedRectangle(cornerRadius: radius))
            .environment(\.layoutDirection, .rightToLeft)
    }
}

struct Shots: View {
    @State private var done = false
    var body: some View {
        Text(done ? "done" : "drawing").task { await draw(); done = true }
    }
    @MainActor private func draw() async {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let p = WPal.current
        let now = Date()
        // a day in Ramadan and one at Eid, to see those faces too
        let inRam = Hj.cal.date(from: DateComponents(year: 1448, month: 9, day: 12)) ?? now
        let inEid = Hj.cal.date(from: DateComponents(year: 1448, month: 10, day: 1)) ?? now
        func save<V: View>(_ name: String, _ v: V) {
            let r = ImageRenderer(content: v); r.scale = 3
            if let img = r.uiImage, let d = img.pngData() { try? d.write(to: dir.appendingPathComponent(name + ".png")) }
        }
        let accBg = Color(white: 0.15)
        save("ram-small", Frame(w: 170, h: 170, bg: p.bg, radius: 22, v: RamadanSmall(s: Hj.season(now), p: p, maghrib: nil, at: now)))
        save("ram-medium", Frame(w: 364, h: 170, bg: p.bg, radius: 22, v: RamadanMedium(s: Hj.season(now), p: p, maghrib: nil, at: now)))
        save("ram-small-in", Frame(w: 170, h: 170, bg: p.bg, radius: 22, v: RamadanSmall(s: Hj.season(inRam), p: p, maghrib: nil, at: inRam)))
        save("ram-medium-in", Frame(w: 364, h: 170, bg: p.bg, radius: 22, v: RamadanMedium(s: Hj.season(inRam), p: p, maghrib: nil, at: inRam)))
        save("ram-medium-eid", Frame(w: 364, h: 170, bg: p.bg, radius: 22, v: RamadanMedium(s: Hj.season(inEid), p: p, maghrib: nil, at: inEid)))
        save("day-lock", Frame(w: 170, h: 76, bg: accBg, radius: 12, v: DayRect(e: DayEntry(date: now)).foregroundStyle(.white)))
        save("ram-lock", Frame(w: 170, h: 76, bg: accBg, radius: 12, v: RamadanView(e: RamadanEntry(date: now)).foregroundStyle(.white)))
        save("day-small", Frame(w: 170, h: 170, bg: p.bg, radius: 22, v: DaySmall(e: DayEntry(date: now))))
        save("day-large", Frame(w: 364, h: 382, bg: p.bg, radius: 22, v: DayLarge(e: DayEntry(date: now))))
        try? "ok".write(to: dir.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
    }
}
