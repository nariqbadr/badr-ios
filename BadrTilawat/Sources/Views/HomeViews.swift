import SwiftUI

struct HomeView: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var store: Store
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var prayers: Prayers
    @Environment(\.pal) private var c
    @State private var annClosed = UserDefaults.standard.string(forKey: "annClosed") ?? ""

    var body: some View {
        let d = repo.data
        let s = d?.site
        let all = d?.sortedTracks ?? []
        ScrollView {
            LazyVStack(spacing: 0) {
                banner(s)
                if s?.liveOn == true && s?.live["showOnHome"].bool(true) == true { LiveCard().padding(.horizontal, 16).padding(.top, 8).reveal() }
                hero(s, all).reveal(0.05)
                if s?.sec("prayer") != false { PrayerBand().padding(.horizontal, 16).padding(.top, 14).reveal(0.1) }
                if s?.sec("ayah") != false { AyahOfDay().padding(.horizontal, 16).padding(.top, 14).reveal(0.15) }
                if s?.sec("recitations") != false {
                    SectionHead(title: "أحدث التلاوات", action: "عرض الكل") { ui.go(.recitations) }
                    ForEach(all.prefix(7)) { t in TrackRow(t: t, list: all) }
                    let weekly = (d?.weekly ?? []).compactMap { w in repo.track(w.id).map { ($0, w.count) } }.prefix(5)
                    if s?.feat("weeklyPopular") != false && !weekly.isEmpty {
                        SectionHead(title: "الأكثر استماعًا هذا الأسبوع")
                        Panel(pad: 4) { ForEach(Array(weekly.enumerated()), id: \.offset) { i, w in TrackRow(t: w.0, list: weekly.map { $0.0 }, rank: i + 1, count: w.1) } }.padding(.horizontal, 12)
                    }
                }
                if s?.sec("reciters") != false, let rs = d?.reciters, !rs.isEmpty {
                    SectionHead(title: "القرّاء")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(rs) { r in
                                Button { ui.path.append(.reciter(r.id)) } label: {
                                    VStack(spacing: 6) {
                                        RemoteImage(raw: r.image).frame(width: 96, height: 120).clipShape(ArchShape()).overlay(ArchShape().stroke(c.gold.opacity(0.5)))
                                        Text(r.name).font(F.plex(12, .medium)).foregroundStyle(c.text).lineLimit(2).multilineTextAlignment(.center).frame(width: 100)
                                    }
                                }.buttonStyle(Press())
                            }
                        }.padding(.horizontal, 16)
                    }
                }
                if s?.sec("dua") != false { DuaCard().padding(16) }
                Text(s?.footer["about"].str ?? "").font(F.plex(12.5)).foregroundStyle(c.muted).multilineTextAlignment(.center).padding(.horizontal, 30).padding(.top, 10)
                if let cr = s?.footer["credit"].str, !cr.isEmpty { Text("إعداد وتطوير: \(cr)").font(F.plex(11.5)).foregroundStyle(c.faint).padding(.top, 6).padding(.bottom, 30) }
            }
        }
        .refreshable { await repo.refresh() }
    }

    @ViewBuilder private func banner(_ s: Site?) -> some View {
        let n = s?.notice
        let appBanner = n?.enabled == true && n?.style == "banner"
        let text = appBanner ? [n!.title, n!.text].filter { !$0.isEmpty }.joined(separator: " — ") : (s?.announcement ?? "")
        let link = appBanner ? n!.link : (s?.announcementLink ?? "")
        if !text.isEmpty && annClosed != String(text.prefix(80)) {
            HStack(spacing: 10) {
                Image(systemName: "megaphone.fill")
                Text(text).font(F.plex(14, .medium)).frame(maxWidth: .infinity, alignment: .leading)
                if !link.isEmpty, let u = URL(string: link) { Link("التفاصيل", destination: u).font(F.plex(13, .bold)) }
                Button { annClosed = String(text.prefix(80)); UserDefaults.standard.set(annClosed, forKey: "annClosed") } label: { Image(systemName: "xmark") }
            }.foregroundStyle(c.onGold).padding(12).background(RoundedRectangle(cornerRadius: 18).fill(c.goldGradient)).padding(.horizontal, 16).padding(.top, 8)
        }
    }

    @ViewBuilder private func hero(_ s: Site?, _ all: [Track]) -> some View {
        let r = repo.data?.reciters.first { $0.id == s?.featuredReciterId } ?? repo.data?.reciters.first
        VStack(spacing: 12) {
            Button { ui.sheet = .name } label: {
                HStack(spacing: 6) { Text(greeting() + (store.name.isEmpty ? "" : "، \(store.name)")).font(F.plex(13, .semibold)).foregroundStyle(c.text); Text(store.name.isEmpty ? "عرّفنا باسمك" : "تغيير").font(F.plex(12)).foregroundStyle(c.gold) }
                    .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(c.surface.opacity(0.6))).overlay(Capsule().stroke(c.line))
            }.buttonStyle(.plain)
            if let r {
                Button { ui.path.append(.reciter(r.id)) } label: {
                    RemoteImage(raw: r.image).frame(width: 220, height: 270).clipShape(ArchShape()).overlay(ArchShape().stroke(c.gold.opacity(0.6), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                }.buttonStyle(Press())
            }
            if let sub = s?.subtitle, !sub.isEmpty { Text(sub).font(F.plex(13, .semibold)).foregroundStyle(c.gold) }
            Text((s?.heroTitle ?? "").replacingOccurrences(of: " | ", with: "\n")).font(F.amiri(32)).foregroundStyle(c.text).multilineTextAlignment(.center)
            if let ht = s?.heroText, !ht.isEmpty { Text(ht).font(F.plex(14.5)).foregroundStyle(c.muted).multilineTextAlignment(.center).padding(.horizontal, 22) }
            HStack(spacing: 10) {
                GoldButton(title: "استمع الآن", icon: "play.fill") { if let t = all.first { player.play(t, in: all) } }
                GhostButton(title: "كل التلاوات", icon: "headphones") { ui.go(.recitations) }
            }.padding(.top, 4)
        }.padding(.top, 18)
    }
    private func greeting() -> String { let h = Calendar.current.component(.hour, from: Date()); return h < 12 ? "صباح الخير" : "مساء الخير" }
}

struct DuaCard: View {
    @Environment(\.pal) private var c
    var body: some View {
        let i = (Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0) % Quran.duas.count
        Panel {
            Text("دعاء اليوم").font(F.plex(13, .semibold)).foregroundStyle(c.gold)
            Text(Quran.duas[i]).font(F.amiri(21, bold: false)).foregroundStyle(c.text).padding(.top, 6)
            Button { share(Quran.duas[i]) } label: { Label("مشاركة", systemImage: "square.and.arrow.up").font(F.plex(13)).foregroundStyle(c.gold) }.padding(.top, 8)
        }
    }
}

/// «آية اليوم» with play, reciter choice, repeat and «انشرها في المجتمع».
struct AyahOfDay: View {
    @EnvironmentObject var ayah: AyahPlayer
    @EnvironmentObject var store: Store
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var ref = Quran.daily(Int64(Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 1))
    @State private var text: String?
    @State private var repeatN = 1
    var rv: String { store.ayahReciter.isEmpty ? (repo.data?.site.dailyReciter ?? "yasser") : store.ayahReciter }
    var body: some View {
        let (s, a) = ref
        let mine = ayah.key?.hasPrefix("\(s):\(a)|") == true
        Panel {
            HStack { Text("آية اليوم").font(F.plex(13, .semibold)).foregroundStyle(c.gold); Spacer(); Text("سورة \(Quran.surahs[s - 1]) · \(a.ar)").font(F.plex(12)).foregroundStyle(c.muted) }
            Text(text.map { "﴿\($0)﴾" } ?? "…").font(F.quran(23)).foregroundStyle(c.text).lineSpacing(10).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 14)
            HStack(spacing: 10) {
                Button { if mine && ayah.playing { ayah.stop() } else { ayah.play(rv, s, a, repeat: repeatN) } } label: {
                    Image(systemName: mine && ayah.playing ? "pause.fill" : "play.fill").foregroundStyle(c.onGold).frame(width: 46, height: 46).background(Circle().fill(c.gold))
                }
                Menu {
                    ForEach(ayah.options(s, a), id: \.self) { o in Button(o.label + (o.ok ? "" : " (غير متاحة)")) { store.ayahReciter = o.value } }
                } label: { Text(ayah.label(rv, s, a).isEmpty ? "القارئ" : ayah.label(rv, s, a)).font(F.plex(13)).foregroundStyle(c.text).lineLimit(1).padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().fill(c.surface2)) }
                Menu { ForEach([1, 3, 5, 10, 0], id: \.self) { n in Button(n == 0 ? "تكرار مستمر" : "\(n.ar) مرات") { repeatN = n } } } label: {
                    Image(systemName: "repeat").foregroundStyle(repeatN != 1 ? c.gold : c.muted).padding(8)
                }
                Spacer()
            }
            if mine && !ayah.status.isEmpty { Text(ayah.status).font(F.plex(12)).foregroundStyle(c.muted).padding(.top, 4) }
            HStack(spacing: 14) {
                Button { Task { await newAyah() } } label: { Label("آية أخرى", systemImage: "arrow.triangle.2.circlepath") }
                Button { share("﴿\(text ?? "")﴾ [سورة \(Quran.surahs[s - 1]): \(a)]") } label: { Label("مشاركة", systemImage: "square.and.arrow.up") }
                if repo.data?.site.sec("community") != false { Button { ui.path.append(.compose("ayah:\(s):\(a)|\(rv)")) } label: { Label("انشرها في المجتمع", systemImage: "bubble.left") } }
            }.font(F.plex(12.5)).foregroundStyle(c.gold).padding(.top, 10)
        }
        .task(id: "\(s):\(a)") { text = await load(s, a) }
    }
    private func load(_ s: Int, _ a: Int) async -> String {
        var t = (await repo.surahText(s))?[safe: a - 1] ?? ""
        if a == 1 && s != 1, let r = t.range(of: "^بِسْمِ\\s+ٱللَّهِ\\s+ٱلرَّحْمَٰنِ\\s+ٱلرَّحِيمِ\\s*", options: .regularExpression) { t.removeSubrange(r) }
        return t
    }
    private func newAyah() async { ayah.stop(); ref = Quran.random() }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

/// Prayer strip on the home screen: next prayer + countdown.
struct PrayerBand: View {
    @EnvironmentObject var prayers: Prayers
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let list = prayers.forDay(); let next = prayers.next()
            Panel(pad: 14) {
                HStack {
                    Button { ui.sheet = .prayer } label: { Label(prayers.place.isEmpty ? "حدّد مدينتك" : prayers.place, systemImage: "mappin.and.ellipse").font(F.plex(13.5, .semibold)).foregroundStyle(c.text).lineLimit(1) }
                    Spacer(); Text(Prayers.hijri()).font(F.plex(11.5)).foregroundStyle(c.muted)
                }
                if let n = next {
                    let left = max(0, Int(n.time.timeIntervalSince(ctx.date)))
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(n.name) بعد").font(F.plex(13)).foregroundStyle(c.muted)
                        Text(String(format: "%02d:%02d:%02d", left / 3600, left % 3600 / 60, left % 60)).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(c.gold).monospacedDigit()
                    }.padding(.top, 8)
                }
                HStack(spacing: 0) {
                    ForEach(list) { p in
                        let on = p.key == next?.key && p.time == next?.time
                        VStack(spacing: 3) { Text(p.name).font(F.plex(11.5, on ? .bold : .regular)); Text(Fmt.time(p.time)).font(F.plex(12, .semibold)) }
                            .foregroundStyle(on ? c.onGold : c.text).frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 12).fill(on ? AnyShapeStyle(c.goldGradient) : AnyShapeStyle(Color.clear)))
                    }
                }.padding(.top, 10)
            }
            .onTapGesture { ui.go(.prayer) }
        }
        .id(prayers.rev)
    }
}

struct LiveCard: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    var body: some View {
        let l = repo.data?.site.live
        Button { ui.go(.live) } label: {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(raw: ytId(l?["url"].str ?? "").map { "https://i.ytimg.com/vi/\($0)/hqdefault.jpg" }).frame(height: 190)
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) { Circle().fill(.red).frame(width: 8, height: 8); Text("مباشر").font(F.plex(12, .bold)) }
                        Text(l?["title"].str ?? "البث المباشر").font(F.amiri(21))
                    }
                    Spacer()
                    Image(systemName: "play.fill").foregroundStyle(c.onGold).frame(width: 44, height: 44).background(Circle().fill(c.gold))
                }.foregroundStyle(.white).padding(14)
            }.clipShape(RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(Press())
    }
}

func ytId(_ url: String) -> String? {
    let pats = ["youtu\\.be/([\\w-]{6,})", "youtube\\.com/(?:watch\\?v=|embed/|live/|shorts/)([\\w-]{6,})", "[?&]v=([\\w-]{6,})"]
    for p in pats {
        if let r = try? NSRegularExpression(pattern: p), let m = r.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)), let g = Range(m.range(at: 1), in: url) { return String(url[g]) }
    }
    return nil
}
