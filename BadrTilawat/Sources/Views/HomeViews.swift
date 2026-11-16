import Network
import SwiftUI
import WebKit

struct HomeView: View {
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @EnvironmentObject var store: Store
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.pal) private var c
    @State private var annClosed = UserDefaults.standard.string(forKey: "annClosed") ?? ""

    var body: some View {
        let d = repo.data
        let s = d?.site
        let all = d?.sortedTracks ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                banner(s)
                if s?.liveOn == true && s?.live["showOnHome"].bool(true) == true { LiveStage().reveal() }
                QuickHead()
                if s?.sec("prayer") != false { PrayerBand().padding(.top, 12).reveal(0.05) }
                QuickTiles()
                ResumeCard(all: all)
                if s?.sec("recitations") != false {
                    let vids = all.filter(\.isVideo)
                    if !vids.isEmpty {
                        SectionHead(title: tr("تلاوات مرئية"), action: tr("عرض الكل"), kicker: "\(vids.count.ar) \(vids.count == 1 ? "تلاوة" : "تلاوات")") { RecKind.value = "video"; ui.go(.recitations) }
                        ScrollView(.horizontal, showsIndicators: false) { HStack(alignment: .top, spacing: 12) { ForEach(vids.prefix(10)) { t in VideoCard(t: t).frame(width: 250) } }.padding(.horizontal, 16) }
                    }
                    SectionHead(title: tr("أحدث التلاوات"), action: tr("عرض الكل"), kicker: tr("{0} تلاوة", all.count.ar)) { ui.go(.recitations) }
                    ScrollView(.horizontal, showsIndicators: false) { HStack(alignment: .top, spacing: 12) { ForEach(all.prefix(10)) { t in TrackCard(t: t, list: all).frame(width: 150) } }.padding(.horizontal, 16) }
                    let w1 = (d?.weekly ?? []).compactMap { w in repo.track(w.id).map { ($0, w.count) } }
                    let weekly = Array((w1.isEmpty ? all.filter { (d?.plays[$0.id] ?? 0) > 0 }.sorted { (d?.plays[$0.id] ?? 0) > (d?.plays[$1.id] ?? 0) }.prefix(5).map { ($0, d?.plays[$0.id] ?? 0) } : w1).prefix(5))
                    if s?.feat("weeklyPopular") != false && !weekly.isEmpty {
                        SectionHead(title: tr("الأكثر استماعًا هذا الأسبوع"))
                        Panel(pad: 4, lattice: false) { ForEach(Array(weekly.enumerated()), id: \.offset) { i, w in TrackRow(t: w.0, list: weekly.map { $0.0 }, rank: i + 1, count: w.1) } }.padding(.horizontal, 12)
                    }
                }
                if s?.sec("reciters") != false, let rs = d?.reciters, !rs.isEmpty {
                    SectionHead(title: tr("القرّاء"), kicker: tr("{0} قارئ", rs.count.ar))
                    ReciterRow(rs: rs)
                }
                if s?.sec("ayah") != false { AyahOfDay().padding(.horizontal, 16).padding(.vertical, 8).reveal() }
                if s?.sec("dua") != false { DuaCard() }
                SectionHead(title: tr("استكشف أيضًا"))
                ExploreTiles()
                HomeFooter()
            }.padding(.bottom, 28)
        }
        .refreshable { await repo.refresh() }
    }

    @ViewBuilder private func banner(_ s: Site?) -> some View {
        let n = s?.notice
        let appBanner = n?.enabled == true && n?.style == "banner"
        let text = appBanner ? [n!.title, n!.text].filter { !$0.isEmpty }.joined(separator: " — ") : (s?.announcement ?? "")
        let link = appBanner ? n!.link : (s?.announcementLink ?? "")
        if !text.isEmpty && annClosed != String(text.prefix(80)) {
            HStack(spacing: 8) {
                Ico(name: "megaphone.fill", size: 20).foregroundStyle(c.onGold)
                Text(text).font(F.plex(14, .medium)).foregroundStyle(c.onGold).frame(maxWidth: .infinity, alignment: .leading)
                if !link.isEmpty, let u = URL(string: link) { Link(appBanner && !(n?.linkLabel.isEmpty ?? true) ? n!.linkLabel : tr("التفاصيل"), destination: u).font(F.plex(14, .bold)).foregroundStyle(c.onGold) }
                Button { annClosed = String(text.prefix(80)); UserDefaults.standard.set(annClosed, forKey: "annClosed") } label: { SiteIcon(name: "close", size: 22, color: c.onGold).frame(width: 40, height: 40) }.accessibilityLabel(tr("إغلاق"))
            }.padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 18).fill(c.goldBrush)).padding(.horizontal, 16).padding(.vertical, 6)
        }
    }
}

/// «تلاوات مرئية» → the recitations list opens on its videos.
enum RecKind { @MainActor static var value = "all" }

/// Greeting and the date / city, as on the site's home.
struct QuickHead: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var store: Store
    @EnvironmentObject var prayers: Prayers
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    var body: some View {
        let h = Calendar.current.component(.hour, from: Date())
        let g = (4...11).contains(h) ? tr("صباح الخير") : (12...16).contains(h) ? tr("طاب يومك") : tr("مساء الخير")
        let greet = repo.data?.site.feat("greeting") != false
        Button { if greet { ui.sheet = .name } } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    Text(greet && !store.name.isEmpty ? tr("{0} يا {1}", g, store.name) : tr("{0}، أهلًا بك", g)).font(F.amiri(24)).foregroundStyle(c.text).lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
                    // a hint that the name can be written (or changed), as on the site
                    if greet {
                        HStack(spacing: 4) {
                            Ico(name: "pencil", size: 13, color: c.gold)
                            Text(store.name.isEmpty ? tr("عرّفنا باسمك") : tr("تغيير")).font(F.plex(11.5, .medium)).foregroundStyle(c.gold)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(c.gold.opacity(0.12))).overlay(Capsule().stroke(c.gold.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .fixedSize()
                    }
                }
                Text([Prayers.hijri(), String(prayers.place.split(separator: tr("،")).first ?? "")].filter { !$0.isEmpty }.joined(separator: " · ")).font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).padding(.horizontal, 16).padding(.top, 14)
    }
}

/// The home shortcuts: full rows of four; the person can pick their own (4 or 8, in their order), as on the site.
struct QuickTiles: View {
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @AppStorage("homeTiles") private var mineRaw = ""
    @State private var edit = false
    @State private var pick: [String] = []
    struct T: Hashable { let icon: String, title: String, go: String, sec: String? }
    private var all: [T] {
        let s = repo.data?.site
        return [T(icon: "mic", title: tr("التلاوات"), go: "recitations", sec: "recitations"), T(icon: "play", title: tr("القرآن كاملًا"), go: "listen", sec: "mushaf"),
                T(icon: "book", title: tr("المصحف"), go: "quran", sec: "mushaf"), T(icon: "beads", title: tr("الأذكار"), go: "adhkar", sec: "adhkar"),
                T(icon: "clock", title: tr("الصلاة"), go: "prayer", sec: "prayer"), T(icon: "compass", title: tr("القبلة"), go: "qibla", sec: nil),
                T(icon: "image", title: tr("صمّم آية"), go: "maker", sec: "maker"), T(icon: "library", title: tr("مكتبتي"), go: "library", sec: nil),
                T(icon: "chat", title: tr("المجتمع"), go: "community", sec: "community"), T(icon: "live", title: tr("البث المباشر"), go: "live", sec: "live"),
                T(icon: "scroll", title: tr("دروس الفقه"), go: "fiqh", sec: "fiqh"), T(icon: "clock", title: tr("الخط الزمني"), go: "timeline", sec: "timeline"),
                T(icon: "user", title: tr("عن الشيخ"), go: "about", sec: "about")]
            .filter { $0.sec == nil || s?.sec($0.sec!) != false }.filter { $0.go != "listen" || !repo.quranRecs().isEmpty }.filter { $0.go != "live" || s?.liveOn != false }
    }
    private var tiles: [T] {
        let mine = mineRaw.split(separator: ",").map(String.init)
        if !mine.isEmpty {
            var chosen = mine.compactMap { k in all.first { $0.go == k } }
            for t in all where !chosen.contains(t) && chosen.count % 4 != 0 { chosen.append(t) }
            return Array(chosen.prefix(8))
        }
        let l = all.filter { $0.go != "about" }
        let n = l.count >= 8 ? 8 : (l.count / 4) * 4
        return n == 0 ? l : Array(l.prefix(n))
    }
    var body: some View {
        VStack(spacing: 10) {
            grid(tiles) { t in tile(t, 38, 20, 11.5) { open(t.go) } }.padding(.horizontal, 16).padding(.top, 14)
            Button { pick = tiles.map(\.go); edit = true } label: {
                HStack(spacing: 6) { Ico(name: "slider.horizontal.3", size: 15.6).foregroundStyle(c.gold); Text(tr("تخصيص الاختصارات")).font(F.plex(12.5)).foregroundStyle(c.muted) }
                    .padding(.horizontal, 12).padding(.vertical, 6).overlay(Capsule().stroke(c.lineSoft))
            }.buttonStyle(Press())
        }
        .bzSheet(isPresented: $edit) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SheetHead(title: tr("تخصيص الاختصارات"))
                    Text(tr("اختر ٤ أو ٨ اختصارات بالترتيب الذي تفضّله، ليبقى الشكل متساويًا.")).font(F.plex(14)).foregroundStyle(c.muted).padding(.horizontal, 20)
                    grid(all) { t in
                        let i = pick.firstIndex(of: t.go)
                        tile(t, 34, 18, 11, on: i != nil) { if let i { pick.remove(at: i) } else if pick.count < 8 { pick.append(t.go) } }
                            .overlay(alignment: .topLeading) { if let i { Text((i + 1).ar).font(F.plex(10.5, .bold)).foregroundStyle(c.onGold).frame(width: 18, height: 18).background(Circle().fill(c.gold)).padding(5) } }
                    }.padding(.horizontal, 16).padding(.vertical, 10)
                    let ok = pick.count == 4 || pick.count == 8
                    HStack(spacing: 10) {
                        GoldButton(title: ok ? tr("حفظ") : tr("اخترت {0} — اختر ٤ أو ٨", pick.count.ar)) { if ok { mineRaw = pick.joined(separator: ","); edit = false } }
                        GhostButton(title: tr("استعادة الافتراضي")) { mineRaw = ""; edit = false }
                    }.padding(.horizontal, 16)
                }.padding(.bottom, 20)
            }.background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir).presentationDetents([.large])
        }
    }
    private func grid(_ l: [T], @ViewBuilder _ cell: @escaping (T) -> some View) -> some View {
        let rows = stride(from: 0, to: l.count, by: 4).map { Array(l[$0..<min(l.count, $0 + 4)]) }
        return VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 8) { ForEach(rows[r], id: \.self) { cell($0) }; ForEach(0..<(4 - rows[r].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) } }
            }
        }
    }
    private func tile(_ t: T, _ box: CGFloat, _ ic: CGFloat, _ fs: CGFloat, on: Bool = false, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            VStack(spacing: 7) {
                SiteIcon(name: t.icon, size: ic, color: c.gold).frame(width: box, height: box).background(RoundedRectangle(cornerRadius: 12).fill(c.gold.opacity(0.14)))
                Text(t.title).font(F.plex(fs, .medium)).foregroundStyle(c.text).lineLimit(1).minimumScaleFactor(0.8)
            }.frame(maxWidth: .infinity).padding(.top, 12).padding(.bottom, 10)
            .background(RoundedRectangle(cornerRadius: 16).fill(on ? c.gold.opacity(0.1) : c.surface)).overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? c.gold : c.lineSoft))
        }.buttonStyle(Press(scale: 0.95))
    }
    private func open(_ go: String) {
        switch go {
        case "listen": ui.path.append(.listen)
        case "qibla": ui.path.append(.qibla)
        case "maker": ui.path.append(.maker(0, 0))
        default: if let r = Route.tab(go) { ui.go(r) }
        }
    }
}

/// «تابع الاستماع»: the last recitation left half-way.
struct ResumeCard: View {
    let all: [Track]
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var store: Store
    @Environment(\.pal) private var c
    var body: some View {
        if repo.data?.site.feat("rememberPosition") != false, let (t, pos) = last {
            Panel(pad: 12, lattice: false) {
                HStack(spacing: 12) {
                    RemoteImage(raw: t.cover.isEmpty ? repo.reciter(t.reciterId)?.image : t.cover).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr("تابع الاستماع")).font(F.plex(12.5, .medium)).foregroundStyle(c.gold)
                        Text(t.title).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(1)
                        Text(tr("توقفت عند {0}{1}", Fmt.dur(Int(pos.0)).isEmpty ? "0:00" : Fmt.dur(Int(pos.0)), pos.1 > 0 ? " من \(Fmt.dur(Int(pos.1)))" : "")).font(F.plex(12.5)).foregroundStyle(c.muted)
                        if pos.1 > 0 { ProgressView(value: min(1, pos.0 / pos.1)).tint(c.gold).padding(.top, 6) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    PlayCircle(playing: false, size: 44) { play(t) }
                }
            }
            .contentShape(Rectangle()).onTapGesture { play(t) }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }
    private var last: (Track, (Double, Double))? {
        let p = UserDefaults.standard.dictionary(forKey: "positions") as? [String: Double] ?? [:]
        for id in store.history { if id != player.current?.id, let s = p[id], s > 0, let t = repo.track(id) { return (t, (s, Double(t.durationSec))) } }
        return nil
    }
    private func play(_ t: Track) { player.play(t, in: all.filter { $0.reciterId == t.reciterId && !$0.isVideo }) }
}

/// The reciters in their mihrab arches, swiped sideways.
struct ReciterRow: View {
    let rs: [Reciter]; var active = ""
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(rs) { r in
                    Button { ui.path.append(.reciter(r.id)) } label: {
                        VStack(spacing: 0) {
                            ArchImg(raw: r.image).frame(width: 116, height: 150)
                            Text(nm(r.name)).font(F.plex(14, .semibold)).foregroundStyle(r.id == active ? c.gold : c.text).lineLimit(2).multilineTextAlignment(.center).padding(.top, 8)
                            Text(tr("{0} تلاوة", (repo.data?.recitations.filter { $0.reciterId == r.id }.count ?? 0).ar)).font(F.plex(11)).foregroundStyle(c.muted)
                        }.frame(width: 116)
                    }.buttonStyle(Press())
                }
            }.padding(.horizontal, 16)
        }
    }
}

/// «استكشف أيضًا»: two tiles a row.
struct ExploreTiles: View {
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @ObservedObject private var amb = Ambient.shared
    @Environment(\.pal) private var c
    var body: some View {
        let s = repo.data?.site
        let tiles: [(String, String, String, String, String?)] = [
            ("waveform", tr("اقرأ واستمع واحفظ"), tr("الآيات تضيء مع الصوت"), "read", "mushaf"), ("live", tr("البث المباشر"), tr("من المسجد الحرام"), "live", "live"),
            ("graduationcap", tr("دروس الفقه"), tr("الفقه الشافعي"), "fiqh", "fiqh"), ("chat", tr("المجتمع"), tr("شارك وتابع"), "community", "community"),
            ("clock", tr("الخط الزمني"), tr("التلاوات والمناسبات"), "timeline", "timeline"), ("user", tr("عن الشيخ"), tr("السيرة والمحطات"), "about", "about"),
            ("wave", amb.current.isEmpty ? tr("أصوات هادئة") : tr("أصوات هادئة (تعمل)"), tr("مطر، رياح، أمواج"), "#ambient", nil),
        ].filter { $0.4 == nil || (s?.sec($0.4!) != false && ($0.3 != "live" || s?.liveOn != false)) }
        let rows = stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0..<min(tiles.count, $0 + 2)]) }
        VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(rows[r], id: \.1) { t in
                        Button { go(t.3) } label: {
                            HStack(spacing: 10) {
                                Ico(name: t.0, size: 22, color: c.gold).frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 13).fill(c.gold.opacity(0.13)))
                                VStack(alignment: .leading, spacing: 1) { Text(t.1).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(1); Text(t.2).font(F.plex(11)).foregroundStyle(c.muted).lineLimit(1) }
                                Spacer(minLength: 0)
                            }.padding(12).frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 20).fill(LinearGradient(colors: [c.surface2, c.surface], startPoint: .topLeading, endPoint: .bottomTrailing))).overlay(RoundedRectangle(cornerRadius: 20).stroke(c.line))
                        }.buttonStyle(Press())
                    }
                    if rows[r].count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
            }
        }.padding(.horizontal, 12)
    }
    private func go(_ g: String) {
        switch g {
        case "#ambient": ui.sheet = .ambient
        case "read": ui.path.append(.readIndex)
        default: if let r = Route.tab(g) { ui.go(r) }
        }
    }
}

/// The site's footer: its title, about text, the contact chips and the credit.
struct HomeFooter: View {
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    var body: some View {
        let s = repo.data?.site, f = s?.footer
        VStack(spacing: 0) {
            Ornament(width: 200)
            Text(s?.title ?? "").font(F.amiri(24)).foregroundStyle(c.text).multilineTextAlignment(.center).padding(.top, 10)
            if let a = f?["about"].str, !a.isEmpty { Text(a).font(F.plex(12.5)).foregroundStyle(c.muted).multilineTextAlignment(.center).padding(.top, 4) }
            FlowLayout(spacing: 8) {
                if let e = f?["email"].str, !e.isEmpty { Chip(text: tr("البريد"), icon: "mail") { open("mailto:\(e)") } }
                if let u = f?["instagram"].str, !u.isEmpty { Chip(text: "Instagram", icon: "insta") { open(u) } }
                if let u = f?["youtube"].str, !u.isEmpty { Chip(text: "YouTube", icon: "yt") { open(u) } }
                if let u = f?["telegram"].str, !u.isEmpty { Chip(text: "Telegram", icon: "send") { open(u) } }
                if let u = f?["whatsapp"].str, !u.isEmpty { Chip(text: tr("واتساب"), icon: "chat") { open(u.hasPrefix("http") ? u : "https://wa.me/" + u.filter(\.isNumber)) } }
                if let u = f?["x"].str, !u.isEmpty { Chip(text: "X", icon: "number") { open(u) } }
            }.padding(.top, 12)
            if let cr = f?["credit"].str, !cr.isEmpty { Text(tr("إعداد وتطوير: {0}", cr)).font(F.plex(11)).foregroundStyle(c.faint).padding(.top, 14) }
        }.frame(maxWidth: .infinity).padding(.top, 18).padding(.horizontal, 24)
    }
    private func open(_ s: String) { if let u = URL(string: s) { UIApplication.shared.open(u) } }
}

struct DuaCard: View {
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var i = Int(Date().timeIntervalSince1970 / 86400) % Quran.duas.count
    var body: some View {
        Panel(pad: 22) {
            Text(tr("دعاء اليوم")).font(F.amiri(22)).foregroundStyle(c.gold)
            Ornament(width: 110).padding(.vertical, 6)
            Text(Quran.duas[i]).font(F.amiri(22, bold: false)).foregroundStyle(c.text).lineSpacing(14).id(i).transition(.opacity)
            HStack(spacing: 8) {
                Chip(text: tr("دعاء آخر"), icon: "refresh") { withAnimation(.easeOut(duration: 0.4)) { i = (i + 1) % Quran.duas.count } }
                Chip(text: tr("نسخ"), icon: "copy") { UIPasteboard.general.string = Quran.duas[i]; ui.say(tr("نُسخ الدعاء")) }
            }.padding(.top, 12)
        }.padding(.horizontal, 16).padding(.vertical, 14)
    }
}

/// A video recitation as a 16:9 card.
struct VideoCard: View {
    let t: Track
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    var body: some View {
        let r = Repo.shared.reciter(t.reciterId), top = t.video?.q.first?.h ?? 0
        Button { ui.openWatch(t.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RemoteImage(raw: t.cover.isEmpty ? r?.image : t.cover)
                    VStack {
                        HStack { Spacer(); if top >= 720 { Text(top >= 1080 ? "1080p" : "HD").font(F.plex(10, .semibold)).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(.black.opacity(0.55))).overlay(Capsule().stroke(.white.opacity(0.28))) } }
                        Spacer()
                        HStack { if !t.durationText.isEmpty { Text(t.durationText).font(F.plex(11, .semibold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.7))) }; Spacer() }
                    }.padding(8)
                }
                .aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(c.line))
                Text(t.title).font(F.plex(13, .semibold)).foregroundStyle(c.text).lineLimit(2).multilineTextAlignment(.leading).padding(.top, 7)
                HStack(spacing: 5) {
                    RemoteImage(raw: r?.image).frame(width: 18, height: 18).clipShape(Circle())
                    Text(nm((r?.name ?? "").replacingOccurrences(of: "الشيخ ", with: ""))).font(F.plex(11)).foregroundStyle(c.muted).lineLimit(1)
                    if !relAgo(t).isEmpty { Text("· " + relAgo(t)).font(F.plex(11)).foregroundStyle(c.faint) }
                }.padding(.top, 3)
            }
        }.buttonStyle(Press(scale: 0.98))
    }
}

/// «آية اليوم» (like the site): the ayah, play with a seek bar, every reciter with his photo, repeat, and the actions.
struct AyahOfDay: View {
    @EnvironmentObject var ayah: AyahPlayer
    @EnvironmentObject var store: Store
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    /// a new ayah each time the app is opened (and when it comes back after a while); on Friday always
    /// ﴿إن الله وملائكته يصلون على النبي﴾ — kept for the whole visit, even if the home page is made again
    static func newRef() -> (Int, Int) { Calendar.current.component(.weekday, from: Date()) == 6 ? (33, 56) : Quran.daily(Int64.random(in: 1...Int64(Int32.max))) }
    nonisolated(unsafe) static var shown = newRef()
    nonisolated(unsafe) static var leftAt = Date()
    @State private var ref = AyahOfDay.shown
    @State private var text: String?
    @State private var repeatN = 1
    @State private var tafsir = false
    @State private var picking = false
    var rv: String {
        let opts = ayah.options(1, 1).map(\.value)
        let p = store.ayahReciter.isEmpty ? (repo.data?.site.dailyReciter ?? "yasser") : store.ayahReciter
        return opts.contains(p) ? p : (opts.contains("yasser") ? "yasser" : opts.first ?? "yasser")
    }
    var body: some View {
        let (s, a) = ref
        let mine = ayah.key?.hasPrefix("\(s):\(a)|") == true
        let cite = tr("﴿{0}﴾ [سورة {1}: {2}]", text ?? "", Quran.surahs[s - 1], a)
        Panel(pad: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(tr("آية اليوم")).font(F.amiri(22)).foregroundStyle(c.gold)
                    Text(tr("سورة {0} — الآية {1}", Quran.surahs[s - 1], a.ar)).font(F.plex(12.5)).foregroundStyle(c.muted)
                }
                Spacer()
                Chip(text: nil, icon: "refresh") { newAyah() }
            }
            Ornament().frame(maxWidth: .infinity).padding(.vertical, 6)
            Group {
                if let t = text { Text("﴿\(t)﴾").font(F.quran(25)).foregroundStyle(c.text).lineSpacing(18).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 8) }
                else { RoundedRectangle(cornerRadius: 14).fill(c.surface2).frame(height: 90).padding(.vertical, 10) }
            }.animation(.easeOut(duration: 0.45), value: text)
            HStack(spacing: 12) {
                PlayCircle(playing: mine && ayah.playing, size: 58) { if mine && ayah.playing { ayah.stop() } else { ayah.play(rv, s, a, repeat: repeatN) } }
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: mine ? ayah.progress : 0).tint(c.gold).padding(.vertical, 10)
                    Text(mine ? ayah.status : tr("اختر القارئ واضغط تشغيل")).font(F.plex(11)).foregroundStyle(c.muted).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.top, 6)
            ReciterPhotos(opts: ayah.options(s, a).map { RecChoice(value: $0.value, label: $0.label, img: repo.recImg($0.value, $0.label)) }, value: rv) { store.ayahReciter = $0; ayah.stop() }.padding(.top, 10)
            OptMenu(label: tr("التكرار"), value: repeatN, opts: [(1, tr("مرة")), (3, tr("٣ مرات")), (5, tr("٥ مرات")), (10, tr("١٠ مرات")), (0, tr("مستمر"))]) { repeatN = $0; ayah.stop() }.padding(.top, 10)
            FlowLayout(spacing: 8) {
                Chip(text: tr("اختر آية"), icon: "book") { picking = true }
                Chip(text: tr("آية أخرى"), icon: "refresh") { newAyah() }
                Chip(text: nil, icon: "copy") { UIPasteboard.general.string = cite; ui.say(tr("نُسخت الآية")) }
                Chip(text: tr("التفسير"), icon: "scroll") { tafsir = true }
                if repo.data?.site.sec("maker") != false { Chip(text: tr("صمّمها"), icon: "image") { ui.path.append(.maker(s, a)) } }
                if repo.data?.site.sec("community") != false { Chip(text: tr("انشرها في المجتمع"), icon: "chat") { ui.path.append(.compose("ayah:\(s):\(a)|\(rv)")) } }
                Chip(text: tr("مشاركة"), icon: "share") { share("\(cite)\n\(Repo.site)") }
            }.padding(.top, 12)
        }
        .task(id: "\(s):\(a)") { text = nil; text = await load(s, a) }
        .onChange(of: s * 1000 + a) { _ in AyahOfDay.shown = ref }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in AyahOfDay.leftAt = Date() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            if Date().timeIntervalSince(AyahOfDay.leftAt) > 600, ayah.key == nil { AyahOfDay.shown = AyahOfDay.newRef(); ref = AyahOfDay.shown }
        }
        .bzSheet(isPresented: $tafsir) { TafsirSheet(s: s, a: a, text: text ?? "").presentationDetents([.medium, .large]) }
        .bzSheet(isPresented: $picking) { AyahPickSheet(s0: s, a0: a) { s2, a2 in picking = false; ayah.stop(); ref = (s2, a2) }.presentationDetents([.medium, .large]) }
    }
    private func load(_ s: Int, _ a: Int) async -> String { ayahClean(s, a, (await repo.surahText(s))?[safe: a - 1] ?? "") }
    private func newAyah() {
        ayah.stop()
        Task { for _ in 0..<5 { let r = Quran.random(); if let t = (await repo.surahText(r.0))?[safe: r.1 - 1], t.count <= 230 { ref = r; return } }; ref = (13, 28) }
    }
}

/// One reciter to choose: the value as stored, the name shown, his photo (blank: the first letter instead).
struct RecChoice: Hashable { let value: String, label: String, img: String }
private func initial(_ n: String) -> String { String(n.replacingOccurrences(of: "^\\s*(الشيخ|القارئ|الإمام|فضيلة)\\s+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces).prefix(1)) }
/// A reciter's photo in a circle, or the first letter of his name.
struct Avatar2: View {
    let img: String?; let name: String; let size: CGFloat; var ring = false
    @Environment(\.pal) private var c
    var body: some View {
        ZStack {
            Circle().fill(c.surface3)
            if let img, !img.isEmpty { RemoteImage(raw: img).clipShape(Circle()) } else { Text(initial(name).isEmpty ? tr("؟") : initial(name)).font(F.amiri(size * 0.38)).foregroundStyle(c.text) }
        }
        .frame(width: ring ? size - 6 : size, height: ring ? size - 6 : size).padding(ring ? 3 : 0)
        .overlay(Circle().stroke(ring ? c.gold : c.lineSoft, lineWidth: ring ? 2 : 1))
    }
}
/// Every reciter side by side with his photo; the chosen one has a ring.
struct ReciterPhotos: View {
    let opts: [RecChoice]; let value: String; var label = tr("بصوت"); let pick: (String) -> Void
    @Environment(\.pal) private var c
    var body: some View {
        let list = opts.enumerated().sorted { ($0.element.img.isEmpty ? 1 : 0, $0.offset) < ($1.element.img.isEmpty ? 1 : 0, $1.offset) }.map(\.element).filter { !$0.value.isEmpty }
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(label).font(F.plex(12.5, .medium)).foregroundStyle(c.muted); Spacer(); Text(list.first { $0.value == value }?.label ?? "").font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(1) }
            ScrollViewReader { sp in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(list, id: \.value) { o in
                            Button { pick(o.value) } label: {
                                VStack(spacing: 5) {
                                    Avatar2(img: o.img, name: o.label, size: 56, ring: o.value == value)
                                    Text(noSheikh(o.label)).font(F.plex(12, o.value == value ? .bold : .regular)).foregroundStyle(o.value == value ? c.text : c.muted).lineLimit(2).multilineTextAlignment(.center)
                                }.frame(width: 74).padding(.vertical, 4)
                            }.buttonStyle(.plain).id(o.value)
                        }
                    }
                }.onAppear { sp.scrollTo(value, anchor: .center) }
            }
        }
    }
}

/// The tafsir of one ayah (الميسر / الجلالين / English).
struct TafsirSheet: View {
    let s: Int, a: Int, text: String
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @AppStorage("tafsirEd") private var ed = L.quran[L.code]?.0 ?? "ar.muyassar"
    @State private var t: String?
    static var editions: [(String, String)] { let base = [("ar.muyassar", "التفسير الميسّر"), ("ar.jalalayn", "الجلالين"), ("en.sahih", "English")]; if let q = L.quran[L.code], q.0 != "en.sahih" { return [(q.0, q.1)] + base }; return base }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SheetHead(title: tr("تفسير سورة {0} — الآية {1}", Quran.surahs[s - 1], a.ar))
                Seg(items: TafsirSheet.editions.map(\.1), selected: TafsirSheet.editions.firstIndex { $0.0 == ed } ?? 0) { ed = TafsirSheet.editions[$0].0 }.padding(.horizontal, 20)
                Text("﴿\(text)﴾").font(F.quran(21)).foregroundStyle(c.text).lineSpacing(14).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.horizontal, 20)
                if let t { Text(t).font(!ed.hasPrefix("ar.") ? F.plex(16) : F.amiri(18, bold: false)).foregroundStyle(c.text).lineSpacing(10).environment(\.layoutDirection, !ed.hasPrefix("ar.") ? (["ur.jalandhry", "fa.khorramdel"].contains(ed) ? .rightToLeft : .leftToRight) : .rightToLeft).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20) }
                else { ProgressView().tint(c.gold).frame(maxWidth: .infinity).padding(30) }
                HStack(spacing: 8) { Chip(text: tr("نسخ"), icon: "copy") { UIPasteboard.general.string = "﴿\(text)﴾\n\(t ?? "")"; ui.say(tr("نُسخ التفسير")) } }.padding(.horizontal, 20)
            }.padding(.bottom, 20)
        }
        .background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir)
        .task(id: ed) { t = nil; let m = await repo.tafsir(s, edition: ed); t = m[a] ?? tr("تعذّر تحميل التفسير الآن.") }
    }
}

/// Choosing an ayah: the surah, then the ayah number.
struct AyahPickSheet: View {
    let s0: Int, a0: Int; let pick: (Int, Int) -> Void
    @Environment(\.pal) private var c
    @State private var s = 1
    @State private var a = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetHead(title: tr("اختر آية"))
            HStack(spacing: 8) {
                OptMenu(label: tr("السورة"), value: s, opts: (1...114).map { ($0, "\($0.ar) \(Quran.surahs[$0 - 1])") }) { s = $0; a = 1 }
                OptMenu(label: tr("الآية"), value: a, opts: (1...Quran.ayahs[s - 1]).map { ($0, $0.ar) }) { a = $0 }
            }.padding(.horizontal, 20)
            GoldButton(title: tr("عرض الآية"), icon: "check") { pick(s, a) }.padding(.horizontal, 20)
            Spacer()
        }
        .background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir)
        .onAppear { s = s0; a = a0 }
    }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

/// Prayer strip on the home screen (like the site): the city and the hijri date, the day's times, the time left to the next.
struct PrayerBand: View {
    @EnvironmentObject var prayers: Prayers
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let list = prayers.forDay(); let next = prayers.next()
            Panel(pad: 16) {
                HStack {
                    Button { ui.sheet = .prayer } label: {
                        HStack(spacing: 4) {
                            SiteIcon(name: "pin", size: 18, color: c.gold)
                            Text(prayers.place.isEmpty ? tr("حدّد مدينتك") : prayers.place).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(1)
                            SiteIcon(name: "chev-d", size: 18, color: c.muted)
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)
                    Spacer()
                    Text(Prayers.hijri()).font(F.plex(12.5, .medium)).foregroundStyle(c.muted)
                }
                HStack(spacing: 0) {
                    ForEach(list) { p in
                        let on = p.key == next?.key && p.time == next?.time, sun = p.key == "sunrise"
                        VStack(spacing: 2) {
                            Text(p.key == "dhuhr" && Calendar.current.component(.weekday, from: p.time) == 6 ? tr("الجمعة") : p.name).font(F.plex(12, .medium)).foregroundStyle(on ? c.onGold : sun ? c.faint : c.muted)
                            Text(hm(p.time)).font(F.plex(15, .bold)).foregroundStyle(on ? c.onGold : sun ? c.faint : c.text)
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 14).fill(on ? AnyShapeStyle(c.goldBrush) : AnyShapeStyle(Color.clear))).padding(.horizontal, 2)
                    }
                }.padding(.vertical, 12)
                if let n = next {
                    let left = max(0, Int(n.time.timeIntervalSince(ctx.date)))
                    Button { ui.go(.prayer) } label: {
                        HStack {
                            Text(tr("المتبقي على {0}", n.name)).font(F.plex(14)).foregroundStyle(c.muted)
                            Spacer()
                            Text(String(format: "%02d:%02d:%02d", left / 3600, left % 3600 / 60, left % 60)).font(F.plex(22, .medium)).foregroundStyle(c.gold).monospacedDigit().environment(\.layoutDirection, .leftToRight)
                        }.padding(.horizontal, 14).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 16).fill(c.bg2.opacity(0.6)))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .id(prayers.rev)
    }
    private func hm(_ d: Date) -> String { let f = DateFormatter(); f.locale = L.locale; f.dateFormat = "h:mm"; return f.string(from: d) }
}

/// The live stream on the home page (like the site): plays by itself without sound; a button turns the sound on;
/// the next prayer's countdown in the corner; a tap opens the live page.
struct LiveStage: View {
    @Environment(\.tabActive) private var active
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @Environment(\.scenePhase) private var phase
    @State private var sound = false
    @State private var poster = true
    @State private var pulse = false
    @State private var mosque = Haram.chosen
    @State private var started = false
    @StateObject private var ctl = LiveCtl()
    @ObservedObject private var net = Net.shared
    var body: some View {
        let l = repo.data?.site.live
        let src = Haram.src(mosque)
        let auto = l?["autoplayHome"].bool(true) ?? true
        ZStack {
            c.surface3
            // the video player is made only once the opening has gone (making it is heavy and made the logo stutter)
            if auto && started && !src.embed.isEmpty { LiveEmbed(id: src.embed, ctl: ctl).id("\(mosque)-\(net.back)") }
            RemoteImage(raw: src.poster).opacity(poster || !auto ? 1 : 0).animation(.easeOut(duration: 0.6), value: poster)
            LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.5), .init(color: .black.opacity(0.8), location: 1)], startPoint: .top, endPoint: .bottom)
                .contentShape(Rectangle()).onTapGesture { ui.path.append(.liveAt(mosque)) }
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) { Circle().fill(Color(hex: 0xFFE5484D)).frame(width: 8, height: 8).opacity(pulse ? 1 : 0.35); Text(tr("مباشر")).font(F.plex(12, .bold)).foregroundStyle(.white) }
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Color(hex: 0xCC000000)))
                        MosqueChips(mosque: $mosque, onDark: true).onChange(of: mosque) { _ in poster = true; DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { poster = false } }
                    }
                    Spacer()
                    if l?["showPrayer"].bool(true) != false {
                        TimelineView(.periodic(from: .now, by: 1)) { tl in HaramStateBox(st: Haram.state(mosque, tl.date)).frame(maxWidth: 170) }
                    }
                }.padding(12)
                Spacer()
                HStack(alignment: .center, spacing: 12) {
                    SiteIcon(name: "play", size: 28, color: c.onGold).frame(width: 46, height: 46).background(Circle().fill(c.goldBrush))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(src.title).font(F.plex(16, .semibold)).foregroundStyle(.white).lineLimit(1)
                        // who leads the prayer: from a while before the adhan (the dashboard's «before», 0 = always), with its time, until the prayer ends
                        TimelineView(.periodic(from: .now, by: 30)) { tl in
                            if let n = Haram.next(mosque, tl.date), let p = n.imam {
                                let left = n.at.timeIntervalSince(tl.date), bm = Haram.beforeMin, during = left <= 0
                                let name = n.key == "jumuah" ? tr("الجمعة") : Haram.prayerName(n.key)
                                if during || bm == 0 || left <= Double(bm * 60) {
                                    Text(during ? tr("يؤم صلاة {0} الآن: الشيخ {1}", name, p.name) : tr("يؤم صلاة {0} الساعة {1}: الشيخ {2}", name, Haram.clock(n.at), p.name))
                                        .font(F.plex(12.5)).foregroundStyle(Color(hex: 0xFFE3C88D)).lineLimit(1)
                                } else { Text(Haram.mosque(mosque).city).font(F.plex(12.5)).foregroundStyle(.white.opacity(0.8)) }
                            } else { Text(Haram.mosque(mosque).city).font(F.plex(12.5)).foregroundStyle(.white.opacity(0.8)) }
                        }
                    }
                    Spacer()
                    if auto {
                        Button {
                            sound.toggle()
                            if sound { AdhanPlayer.shared.stop(); AudioPlayer.shared.pause(); AyahPlayer.shared.stop(); ctl.js("cmd('unMute');cmd('setVolume',[100]);cmd('playVideo')") } else { ctl.js("cmd('mute')") }
                        } label: { SiteIcon(name: sound ? "volume" : "mute", size: 20, color: .white).frame(width: 42, height: 42).background(Circle().fill(Color(hex: 0xAA000000))) }
                            .accessibilityLabel(sound ? tr("كتم الصوت") : tr("تشغيل الصوت"))
                    }
                }.padding(14).allowsHitTesting(true)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(c.line))
        .padding(.horizontal, 16).padding(.vertical, 8)
        .onAppear { mosque = Haram.chosen; withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true }; DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { poster = false } }
        .onChange(of: phase) { p in ctl.js(p == .active && active ? "cmd('playVideo')" : "cmd('pauseVideo')") }
        .onChange(of: active) { a in ctl.js(a && phase == .active ? "cmd('playVideo')" : "cmd('pauseVideo')"); if a && !started { DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { started = true } } }
        .onAppear { if active && !started { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { started = true } } }
        .onDisappear { ctl.js("cmd('pauseVideo')") }
    }
}

/// Talks to the muted YouTube player inside the live card.
/// Whether the phone is online: the live stream starts again by itself when the connection comes back.
@MainActor
final class Net: ObservableObject {
    static let shared = Net()
    @Published private(set) var back = 0   // goes up each time the connection returns
    private let mon = NWPathMonitor()
    private var online = true
    private init() {
        mon.pathUpdateHandler = { p in
            let on = p.status == .satisfied
            Task { @MainActor in let s = Net.shared; if on && !s.online { s.back += 1 }; s.online = on }
        }
        mon.start(queue: DispatchQueue(label: "net"))
    }
}

final class LiveCtl: ObservableObject { weak var web: WKWebView?; func js(_ s: String) { web?.evaluateJavaScript(s) } }
struct LiveEmbed: UIViewRepresentable {
    let id: String; let ctl: LiveCtl
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration(); cfg.allowsInlineMediaPlayback = true; cfg.mediaTypesRequiringUserActionForPlayback = []
        let w = WKWebView(frame: .zero, configuration: cfg); w.isOpaque = false; w.backgroundColor = .black; w.scrollView.isScrollEnabled = false; w.isUserInteractionEnabled = false
        ctl.web = w
        let html = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;background:#000;height:100%;overflow:hidden}iframe{border:0;width:100%;height:100%;pointer-events:none}</style></head>
        <body><iframe id="p" src="https://www.youtube.com/embed/\(id)\(id.contains("?") ? "&" : "?")playsinline=1&autoplay=1&mute=1&controls=0&rel=0&modestbranding=1&enablejsapi=1" allow="autoplay; encrypted-media"></iframe>
        <script>function cmd(f,a){document.getElementById('p').contentWindow.postMessage(JSON.stringify({event:'command',func:f,args:a||[]}),'*')}</script></body></html>
        """
        w.loadHTMLString(html, baseURL: URL(string: Repo.site))
        return w
    }
    func updateUIView(_ w: WKWebView, context: Context) {}
}

func ytId(_ url: String) -> String? {
    let pats = ["youtu\\.be/([\\w-]{6,})", "youtube\\.com/(?:watch\\?v=|embed/|live/|shorts/)([\\w-]{6,})", "[?&]v=([\\w-]{6,})"]
    for p in pats {
        if let r = try? NSRegularExpression(pattern: p), let m = r.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)), let g = Range(m.range(at: 1), in: url) { return String(url[g]) }
    }
    return nil
}
