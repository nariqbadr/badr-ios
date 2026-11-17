import SwiftUI
import WebKit

/// YouTube player (live stream, fiqh lessons).
struct YouTube: UIViewRepresentable {
    let id: String
    var autoplay = false
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration(); cfg.allowsInlineMediaPlayback = true; cfg.mediaTypesRequiringUserActionForPlayback = []
        let w = WKWebView(frame: .zero, configuration: cfg); w.isOpaque = false; w.backgroundColor = .black; w.scrollView.isScrollEnabled = false
        return w
    }
    func updateUIView(_ w: WKWebView, context: Context) {
        let html = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;background:#000;height:100%}iframe{border:0;width:100%;height:100%}</style></head>
        <body><iframe src="https://www.youtube.com/embed/\(id)\(id.contains("?") ? "&" : "?")playsinline=1&autoplay=\(autoplay ? 1 : 0)&rel=0" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe></body></html>
        """
        if context.coordinator.loaded != id { context.coordinator.loaded = id; w.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com")) }
    }
    func makeCoordinator() -> Coord { Coord() }
    final class Coord { var loaded = "" }
}

/// «البث المباشر»: the live stream from the Haram, with sound, reload and open-in-YouTube (like the Android app).
struct LiveView: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var prayers: Prayers
    @Environment(\.pal) private var c
    @StateObject private var ctl = LiveCtl()
    @State private var sound = true
    @State private var key = 0
    var body: some View {
        let l = repo.data?.site.live
        let id = ytId(l?["url"].str ?? "") ?? "eC4LfEVxvKg"
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LiveEmbedFull(id: id, ctl: ctl).id(key).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(c.line))
                Text(l?["title"].str.isEmpty == false ? l!["title"].str : tr("البث المباشر من المسجد الحرام")).font(F.amiri(22)).foregroundStyle(c.text)
                if let n = prayers.next() {
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        let left = max(0, Int(n.time.timeIntervalSince(tl.date)))
                        HStack(spacing: 6) {
                            SiteIcon(name: "clock", size: 18, color: c.gold)
                            Text(tr("{0} بعد ", n.name)).font(F.plex(14)).foregroundStyle(c.muted)
                            Text(String(format: "%02d:%02d:%02d", left / 3600, left % 3600 / 60, left % 60)).font(F.plex(14, .bold)).foregroundStyle(c.gold).monospacedDigit().environment(\.layoutDirection, .leftToRight)
                        }.padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(c.surface)).overlay(Capsule().stroke(c.line))
                    }
                }
                HStack(spacing: 8) {
                    Chip(text: sound ? tr("كتم الصوت") : tr("تشغيل الصوت"), icon: sound ? "mute" : "volume") { sound.toggle(); if sound { AdhanPlayer.shared.stop() }; ctl.js(sound ? "cmd('unMute');cmd('setVolume',[100]);cmd('playVideo')" : "cmd('mute')") }
                    Chip(text: tr("إعادة تحميل"), icon: "refresh") { key += 1 }
                    Chip(text: "YouTube", icon: "external") { if let u = URL(string: l?["url"].str.isEmpty == false ? l!["url"].str : "https://www.youtube.com/live/\(id)") { UIApplication.shared.open(u) } }
                }
                Text(tr("لملء الشاشة اضغط زر التكبير داخل المشغّل.")).font(F.plex(12.5)).foregroundStyle(c.faint)
            }.padding(16)
        }
        .onAppear { AudioPlayer.shared.pause(); AyahPlayer.shared.stop() }
    }
}
/// The live player with its own controls (sound on).
struct LiveEmbedFull: UIViewRepresentable {
    let id: String; let ctl: LiveCtl
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration(); cfg.allowsInlineMediaPlayback = true; cfg.mediaTypesRequiringUserActionForPlayback = []
        let w = WKWebView(frame: .zero, configuration: cfg); w.isOpaque = false; w.backgroundColor = .black; w.scrollView.isScrollEnabled = false
        ctl.web = w
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style></head>
        <body><iframe id="f" src="https://www.youtube.com/embed/\(id)\(id.contains("?") ? "&" : "?")autoplay=1&mute=0&playsinline=1&rel=0&modestbranding=1&enablejsapi=1" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
        <script>function cmd(f,a){document.getElementById('f').contentWindow.postMessage(JSON.stringify({event:'command',func:f,args:a||[]}),'*')}</script></body></html>
        """
        w.loadHTMLString(html, baseURL: URL(string: Repo.site))
        return w
    }
    func updateUIView(_ w: WKWebView, context: Context) {}
}

/// «دروس الفقه»: lessons with YouTube thumbnails; plays inside the app.
struct FiqhView: View {
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    @State private var open: String?
    var body: some View {
        let list = repo.data?.fiqh ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !list.isEmpty { Text(tr("{0} درسًا في الفقه الشافعي", list.count.ar)).font(F.plex(14)).foregroundStyle(c.muted) }
                if list.isEmpty { Empty(text: tr("لا توجد دروس منشورة حاليًا."), icon: "graduationcap") }
                ForEach(list) { f in
                    let yid = ytId(f.video)
                    Panel(pad: 0, lattice: false) {
                        ZStack {
                            Color.black
                            if open == f.id, let yid { YouTube(id: yid, autoplay: true) }
                            else {
                                RemoteImage(raw: yid.map { "https://i.ytimg.com/vi/\($0)/hqdefault.jpg" })
                                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                                SiteIcon(name: "play", size: 36, color: c.onGold).frame(width: 62, height: 62).background(Circle().fill(c.goldBrush))
                            }
                        }
                        .aspectRatio(16 / 9, contentMode: .fit).contentShape(Rectangle()).onTapGesture { AudioPlayer.shared.pause(); open = f.id }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).font(F.plex(16, .semibold)).foregroundStyle(c.text)
                            if !f.teacher.isEmpty { Text(f.teacher).font(F.plex(12.5)).foregroundStyle(c.gold) }
                            if !f.description.isEmpty { Text(f.description).font(F.plex(12.5)).foregroundStyle(c.muted).padding(.top, 4) }
                        }.padding(16)
                    }
                }
            }.padding(16)
        }
    }
}

/// «عن الشيخ»: portrait in the arch, intro, biography, milestones and gallery (all from the dashboard).
struct AboutView: View {
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var photo: String?
    var body: some View {
        let a = repo.data?.site.about
        let featured = repo.reciter(repo.data?.site.featuredReciterId) ?? repo.data?.reciters.first
        let n = (repo.data?.recitations ?? []).filter { $0.reciterId == featured?.id }.count
        let bio = (a?["bio"].str.isEmpty == false ? a!["bio"].str : featured?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        ScrollView {
            VStack(spacing: 0) {
                ArchImg(raw: a?["image"].str.isEmpty == false ? a!["image"].str : featured?.image).frame(width: 210, height: 272)
                    .background(RadialGradient(colors: [c.gold.opacity(0.2), .clear], center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 210))
                Text(a?["title"].str.isEmpty == false ? a!["title"].str : tr("عن الشيخ")).font(F.plex(14, .semibold)).foregroundStyle(c.gold).padding(.top, 16)
                Text(a?["name"].str.isEmpty == false ? a!["name"].str : featured?.name ?? "").font(F.amiri(28)).foregroundStyle(c.text).multilineTextAlignment(.center)
                if let i = a?["intro"].str, !i.isEmpty { Text(i).font(F.plex(16)).foregroundStyle(c.muted).multilineTextAlignment(.center).padding(.top, 6) }
                if let f = featured { GoldButton(title: tr("استمع لتلاواته"), icon: "headphones") { ui.path.append(.reciter(f.id)) }.padding(.top, 14) }
                Ornament(width: 200).padding(.vertical, 18)
                if bio.isEmpty { Text(tr("ستُضاف السيرة قريبًا بإذن الله.")).font(F.plex(14)).foregroundStyle(c.muted) }
                else { ForEach(Array(bio.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, p in Text(p.trimmingCharacters(in: .whitespacesAndNewlines)).font(F.amiri(19, bold: false)).foregroundStyle(c.text).lineSpacing(12).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12) } }
                let ms = (a?["milestones"].array ?? []).filter { !$0["year"].str.isEmpty || !$0["text"].str.isEmpty }
                Panel(pad: 18) {
                    if !ms.isEmpty { Text(tr("محطات")).font(F.amiri(22)).foregroundStyle(c.text).padding(.bottom, 8) }
                    ForEach(Array((ms.map { ($0["year"].str, $0["text"].str) } + [(n.ar, tr("تلاوة منشورة على الموقع"))]).enumerated()), id: \.offset) { _, m in
                        HStack(alignment: .top, spacing: 8) { Text(m.0).font(F.plex(16, .semibold)).foregroundStyle(c.gold).frame(minWidth: 64, alignment: .leading); Text(m.1).font(F.plex(14)).foregroundStyle(c.text) }.padding(.vertical, 6)
                    }
                }.padding(.top, 8)
                let gal = (a?["gallery"].array ?? []).map(\.str).filter { !$0.isEmpty }
                if !gal.isEmpty {
                    SectionHead(title: tr("معرض الصور"))
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 10) { ForEach(gal, id: \.self) { g in RemoteImage(raw: g).frame(width: 150, height: 150).clipShape(RoundedRectangle(cornerRadius: 18)).onTapGesture { photo = g } } } }
                }
            }.padding(20)
        }
        .fullScreenCover(item: Binding(get: { photo.map { StrBox(v: $0) } }, set: { photo = $0?.v })) { b in Lightbox(urls: [b.v], start: 0) }
    }
}
struct StrBox: Identifiable { let v: String; var id: String { v } }

/// «الخط الزمني»: recitations and events by date, grouped by hijri year.
struct TimelineScreen: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.pal) private var c
    @State private var f = 0
    private struct Item { let at: Date; var t: Track?; var ev: TimelineEvent? }
    var body: some View {
        var items: [Item] = []
        if f != 2 { for e in repo.data?.events ?? [] { if let d = Fmt.parse(e.date) { items.append(Item(at: d, ev: e)) } } }
        if f != 1 { for t in repo.data?.recitations ?? [] { if let d = Fmt.parse(t.recordedAt.isEmpty ? t.createdAt : t.recordedAt) { items.append(Item(at: d, t: t)) } } }
        items.sort { $0.at > $1.at }
        let yr: (Date) -> String = { d in let fm = DateFormatter(); fm.calendar = Calendar(identifier: .islamicUmmAlQura); fm.locale = L.locale; fm.dateFormat = "y"; return fm.string(from: d) + tr(" هـ") }
        let greg: (Date) -> String = { d in let fm = DateFormatter(); fm.locale = L.locale; fm.dateFormat = "d MMMM yyyy"; return fm.string(from: d) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Seg(items: [tr("الكل"), tr("المناسبات"), tr("التلاوات")], selected: f) { f = $0 }.padding(.bottom, 10)
                if items.isEmpty { Empty(text: tr("لا توجد عناصر بعد."), icon: "clock") }
                ForEach(Array(items.enumerated()), id: \.offset) { i, x in
                    if i == 0 || yr(items[i - 1].at) != yr(x.at) { Text(yr(x.at)).font(F.amiri(22)).foregroundStyle(c.gold).padding(.top, 14).padding(.bottom, 6) }
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            Circle().fill(x.ev != nil ? c.gold : c.surface3).frame(width: 12, height: 12).overlay(Circle().stroke(c.gold, lineWidth: 2))
                            Rectangle().fill(c.line).frame(width: 2).frame(maxHeight: .infinity)
                        }.frame(width: 26).padding(.top, 18)
                        Panel(pad: 14, lattice: false) {
                            Text("\(Prayers.hijri(x.at)) — \(greg(x.at))").font(F.plex(11)).foregroundStyle(c.muted)
                            if let e = x.ev {
                                Text(e.title).font(F.plex(16, .semibold)).foregroundStyle(c.text)
                                if !e.text.isEmpty { Text(e.text).font(F.plex(12.5)).foregroundStyle(c.muted).padding(.top, 4) }
                                if !e.image.isEmpty { RemoteImage(raw: e.image).frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 14)).padding(.top, 8) }
                            } else if let t = x.t {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(t.title).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(2)
                                        Text([repo.reciter(t.reciterId)?.shown, t.location.isEmpty ? nil : t.location].compactMap { $0 }.joined(separator: " — ")).font(F.plex(12.5)).foregroundStyle(c.muted)
                                    }
                                    Spacer()
                                    RemoteImage(raw: t.cover.isEmpty ? repo.reciter(t.reciterId)?.image : t.cover).frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                Chip(text: tr("استماع"), icon: "play") { if t.isVideo { } else { player.play(t, in: [t]) } }.padding(.top, 8)
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }.padding(16)
        }
    }
}

struct ThemeSheet: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let c = Themes.get(store.theme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHead(title: tr("المظهر"))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Themes.all, id: \.key) { p in
                        let on = store.theme == p.key
                        Button { withAnimation { store.theme = p.key } } label: {
                            ZStack(alignment: .topLeading) {
                                Canvas { ctx, s in let ctr = CGPoint(x: s.width / 2, y: s.height / 2); ctx.fill(star8(ctr, s.width / 2), with: .color(p.gold.opacity(0.25))); ctx.stroke(star8(ctr, s.width / 2), with: .color(p.gold), lineWidth: 1.5) }.frame(width: 34, height: 34)
                                VStack(alignment: .leading, spacing: 6) {
                                    Spacer()
                                    Text(tr(tr(p.name))).font(F.plex(15, .bold)).foregroundStyle(p.text)
                                    Capsule().fill(LinearGradient(colors: [p.gold2, p.gold], startPoint: .leading, endPoint: .trailing)).frame(width: 46, height: 5)
                                }
                                if on { HStack { Spacer(); SiteIcon(name: "check", size: 22, color: p.gold) } }
                            }
                            .padding(14).frame(height: 96)
                            .background(RoundedRectangle(cornerRadius: 20).fill(p.stars ? LinearGradient(colors: [Color(hex: 0xFF05061A), Color(hex: 0xFF1D1838)], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: p.grad, startPoint: .top, endPoint: .bottom)))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(on ? p.gold : p.line, lineWidth: on ? 2 : 1))
                        }.buttonStyle(Press())
                    }
                }.padding(.horizontal, 16)
            }.padding(.bottom, 20)
        }.background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir).environment(\.pal, c).presentationDetents([.medium, .large])
    }
}

struct NameSheet: View {
    @EnvironmentObject var store: Store
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var v = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHead(title: tr("اسمك في التطبيق"))
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("اكتب اسمك هنا للترحيب بك.")).font(F.plex(14)).foregroundStyle(c.muted)
                HStack(spacing: 8) { SiteIcon(name: "user", size: 22, color: c.gold); TextField(tr("مثال: أحمد"), text: Binding(get: { v }, set: { v = String($0.prefix(30)) })).font(F.plex(16)) }
                    .padding(.horizontal, 14).padding(.vertical, 13).background(RoundedRectangle(cornerRadius: 18).fill(c.surface.opacity(0.45))).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.line))
                HStack(spacing: 10) {
                    GoldButton(title: tr("حفظ"), icon: "check") { store.name = v.trimmingCharacters(in: .whitespaces); if !store.name.isEmpty { ui.say(tr("أهلًا {0}", store.name)); Repo.shared.event("name", ["visitorName": store.name]) }; dismiss() }
                    if !store.name.isEmpty { GhostButton(title: tr("حذف الاسم")) { store.name = ""; dismiss() } }
                }.padding(.vertical, 16)
            }.padding(.horizontal, 22)
            Spacer()
        }.background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir).onAppear { v = store.name }.presentationDetents([.medium])
    }
}

struct NoticesSheet: View {
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let list = (repo.data?.notices ?? []).sorted { $0.date > $1.date }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHead(title: tr("التنبيهات"))
                if list.isEmpty { Empty(text: tr("لا توجد تنبيهات جديدة."), icon: "bell") }
                ForEach(list) { n in
                    Panel(pad: 16, lattice: false) {
                        Text(n.title).font(F.plex(16, .semibold)).foregroundStyle(c.text)
                        if !n.text.isEmpty { Text(n.text).font(F.plex(14)).foregroundStyle(c.muted).padding(.top, 4) }
                        if !n.link.isEmpty { Button { open(n.link) } label: { Text(tr("التفاصيل ‹")).font(F.plex(14, .semibold)).foregroundStyle(c.gold) }.padding(.top, 8) }
                    }.padding(.horizontal, 18).padding(.vertical, 5)
                }
            }.padding(.bottom, 16)
        }.background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir)
    }
    private func open(_ l: String) {
        let u = l.hasPrefix("/") ? Repo.site.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + l : l
        if u.hasPrefix(Repo.site), let r = Route.fromSite(u) { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { if let t = r.tabKey { ui.go(Route.tab(t) ?? .home) } else { ui.path.append(r) } } }
        else if let x = URL(string: u) { UIApplication.shared.open(x) }
    }
}

/// «الويدجت على الشاشة الرئيسية»: what each widget shows and how to add it.
struct WidgetsHelpView: View {
    @Environment(\.pal) private var c
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("أضف ويدجت «بدر التلاوات» إلى الشاشة الرئيسية أو شاشة القفل لترى التاريخ الهجري ومواعيد الصلاة وآية اليوم دون فتح التطبيق. المس الأداة مطوّلًا ← «تعديل الأداة» لتغيير لونها وشكلها.")).font(F.plex(14)).foregroundStyle(c.muted)
                ForEach([("calendar", tr("التاريخ ومواقيت الصلاة"), tr("التاريخ الهجري واليوم بالخط مع المواقيت — ثلاثة أشكال، صغير ومتوسط وكبير، وعلى شاشة القفل")),
                         ("clock", tr("الصلاة القادمة"), tr("الصلاة القادمة والعدّ التنازلي — وعلى شاشة القفل")), ("moon", tr("رمضان"), tr("كم يومًا بقي على رمضان، وفي رمضان: اليوم والوقت المتبقي للإفطار")),
                         ("book", tr("آية اليوم"), tr("آية تتغير كل يوم؛ وعلى شاشة القفل آية قصيرة بين القوسين المزخرفين")),
                         ("beads", tr("عدّاد التسبيح"), tr("المس الأداة نفسها لتسبّح")), ("check", tr("عبادات اليوم"), tr("علّم على صلواتك وأذكارك ووردك من الأداة")),
                         ("refresh", tr("متابعة الوضوء"), tr("المسها عند الوضوء، ومرة أخرى إذا انتقض")), ("scroll", tr("الورد اليومي"), tr("ورد اليوم ونسبة الختمة")),
                         ("play", tr("المشغّل"), tr("التلاوة الحالية — المسه لفتح المشغّل")), ("beads", tr("الأذكار"), tr("أذكار الصباح والمساء والنوم حسب الوقت"))], id: \.1) { i, t, s in
                    Panel(pad: 14, lattice: false) {
                        HStack(spacing: 12) {
                            SiteIcon(name: i, size: 22, color: c.gold).frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 13).fill(c.gold.opacity(0.13)))
                            VStack(alignment: .leading, spacing: 1) { Text(t).font(F.plex(15, .semibold)).foregroundStyle(c.text); Text(s).font(F.plex(12.5)).foregroundStyle(c.muted) }
                        }
                    }
                }
                Text(tr("طريقة الإضافة")).font(F.amiri(22)).foregroundStyle(c.text).padding(.top, 8)
                ForEach(Array([tr("المس مكانًا فارغًا في الشاشة الرئيسية مطوّلًا حتى تهتز الأيقونات."), tr("اضغط «تعديل» أو علامة + في الأعلى."), tr("ابحث عن «بدر التلاوات» واختر الويدجت والحجم."), tr("اضغط «إضافة ويدجت» ثم «تم».")].enumerated()), id: \.offset) { k, s in
                    HStack(alignment: .top, spacing: 10) { Text((k + 1).ar).font(F.plex(13, .bold)).foregroundStyle(c.onGold).frame(width: 24, height: 24).background(Circle().fill(c.gold)); Text(s).font(F.plex(14)).foregroundStyle(c.text) }
                }
                Text(tr("تأخذ الويدجت ألوان المظهر الذي تختاره في التطبيق.")).font(F.plex(12.5)).foregroundStyle(c.faint).padding(.top, 6)
            }.padding(16)
        }
    }
}
