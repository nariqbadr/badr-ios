import SwiftUI

/// Thin seek bar with a round thumb (fills from the right in Arabic).
struct SeekBar: View {
    let value: Double
    let onDrag: (Double) -> Void
    let onDone: (Double) -> Void
    /// 0…1: where each surah starts in a recording with several (a tick on the bar)
    var marks: [Double] = []
    @Environment(\.pal) private var c
    var body: some View {
        GeometryReader { g in
            let w: CGFloat = max(g.size.width, 1), v: CGFloat = CGFloat(min(max(value, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(c.lineSoft).frame(height: 4)
                Capsule().fill(c.gold).frame(width: w * v, height: 4)
                ForEach(Array(marks.enumerated()), id: \.offset) { _, m in
                    Capsule().fill(c.text.opacity(0.55)).frame(width: 2, height: 9).offset(x: w * CGFloat(m) - 1)
                }
                Circle().fill(c.gold).frame(width: 14, height: 14).shadow(color: c.gold.opacity(0.4), radius: 6)
                    .offset(x: w * v - 7)
            }
            .frame(height: 26).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in onDrag(Double(min(max(e.location.x / w, 0), 1))) }
                .onEnded { e in onDone(Double(min(max(e.location.x / w, 0), 1))) })
        }.frame(height: 26).environment(\.layoutDirection, .leftToRight)
    }
}

/// Docked player bar — the site's bottom player laid out for a phone (like the Android app):
/// artwork · title · reciter · heart / time — seek bar — time / speed · repeat · prev · ⟲10 · PLAY · 10⟳ · next · shuffle · queue.
struct MiniPlayer: View {
    @ObservedObject private var autoTr = AutoTr.shared
    @EnvironmentObject var p: AudioPlayer
    @ObservedObject private var clock = AudioPlayer.shared.clock
    @EnvironmentObject var store: Store
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var drag: Double?
    var body: some View {
        if let t = p.current {
            let v = drag ?? (p.duration > 0 ? p.position / p.duration : 0)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        RemoteImage(raw: t.cover.isEmpty ? Repo.shared.reciter(t.reciterId)?.image : t.cover).frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 12))
                        if p.playing { Equalizer(playing: true, color: c.gold2).frame(width: 12, height: 10).padding(3).background(RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.45))).padding(5) }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(titleL(t)).font(F.plex(15, .bold)).foregroundStyle(c.text).lineLimit(1)
                        Text(p.nowLabel?.0 == t.id ? p.nowLabel!.1 : (Repo.shared.reciter(t.reciterId)?.shown ?? "") + miniSurah(t)).font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(1)
                    }.padding(.leading, 12).frame(maxWidth: .infinity, alignment: .leading)
                    Button { store.toggleFav(t.id) } label: { SiteIcon(name: store.favs.contains(t.id) ? "heart-f" : "heart", size: 22, color: store.favs.contains(t.id) ? c.danger : c.muted).frame(width: 40, height: 40) }.accessibilityLabel(tr("المفضلة"))
                    Button { ui.playerOpen = true } label: { Ico(name: "chevron.up", size: 19.2).foregroundStyle(c.muted).frame(width: 38, height: 38) }.accessibilityLabel(tr("فتح المشغّل"))
                    Button { p.close() } label: { SiteIcon(name: "close", size: 20, color: c.muted).frame(width: 38, height: 38) }.accessibilityLabel(tr("إغلاق المشغّل"))
                }
                HStack(spacing: 0) {
                    Text(Fmt.dur(Int(v * p.duration)).isEmpty ? "0:00" : Fmt.dur(Int(v * p.duration))).font(F.plex(11)).foregroundStyle(c.muted).frame(width: 40)
                    SeekBar(value: v, onDrag: { drag = $0 }, onDone: { drag = nil; p.seek($0 * p.duration) }, marks: Chapters.shared.id == t.id ? Chapters.shared.marks(p.duration) : [])
                    Text(Fmt.dur(Int(p.duration)).isEmpty ? "--:--" : Fmt.dur(Int(p.duration))).font(F.plex(11)).foregroundStyle(c.muted).frame(width: 40)
                }.padding(.top, 4).environment(\.layoutDirection, .leftToRight)
                HStack(spacing: 0) {
                    Button { p.setSpeed(nextSpeed(store.speed)) } label: { Text("×" + speedText(store.speed)).font(F.plex(13, .bold)).foregroundStyle(store.speed != 1 ? c.gold : c.muted).frame(width: 40, height: 40) }
                    Spacer(minLength: 0)
                    Button { p.cycleRepeat() } label: { ZStack { SiteIcon(name: "repeat", size: 22, color: p.repeatMode > 0 || p.repN > 0 ? c.gold : c.muted); if p.repeatMode == 2 { Text(tr("١")).font(F.plex(9, .bold)).foregroundStyle(c.gold) } }.frame(width: 40, height: 40) }.accessibilityLabel(tr("تكرار"))
                    Spacer(minLength: 0)
                    Button { p.prev() } label: { SiteIcon(name: "prev", size: 24, color: c.text).frame(width: 40, height: 40) }.accessibilityLabel(tr("السابق"))
                    Spacer(minLength: 0)
                    Button { p.skip(-10) } label: { Ico(name: "gobackward.10", size: 24.0).foregroundStyle(c.text).frame(width: 40, height: 40) }.accessibilityLabel(tr("رجوع ١٠ ثوانٍ"))
                    Spacer(minLength: 0)
                    Button { p.toggle() } label: {
                        ZStack { Circle().fill(c.gold).shadow(color: c.gold.opacity(0.6), radius: 8); SiteIcon(name: p.playing ? "pause" : "play", size: 24, color: c.onGold) }.frame(width: 54, height: 54)
                            // still loading: a ring around the button, the sign stays clear
                            .overlay { if p.buffering && p.playing { LoadingRing(color: c.gold).frame(width: 62, height: 62) } }
                    }.accessibilityLabel(p.playing ? tr("إيقاف مؤقت") : tr("تشغيل"))
                    Spacer(minLength: 0)
                    Button { p.skip(10) } label: { Ico(name: "goforward.10", size: 24.0).foregroundStyle(c.text).frame(width: 40, height: 40) }.accessibilityLabel(tr("تقديم ١٠ ثوانٍ"))
                    Spacer(minLength: 0)
                    Button { p.next() } label: { SiteIcon(name: "next", size: 24, color: c.text).frame(width: 40, height: 40) }.accessibilityLabel(tr("التالي"))
                    Spacer(minLength: 0)
                    Button { p.shuffle.toggle() } label: { SiteIcon(name: "shuffle", size: 22, color: p.shuffle ? c.gold : c.muted).frame(width: 40, height: 40) }.accessibilityLabel(tr("عشوائي"))
                    Spacer(minLength: 0)
                    Button { ui.playerOpen = true } label: { SiteIcon(name: "queue", size: 22, color: c.muted).frame(width: 40, height: 40) }.accessibilityLabel(tr("قائمة الانتظار"))
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.leading, 14).padding(.trailing, 10).padding(.top, 10).padding(.bottom, 4)
            .background(LinearGradient(colors: [c.bg2, c.bg], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(c.lineSoft).frame(height: 1) }
            .contentShape(Rectangle()).onTapGesture { ui.playerOpen = true }
            .buttonStyle(.plain)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
func nextSpeed(_ s: Float) -> Float { let l: [Float] = [1, 1.25, 1.5, 1.75, 2, 0.75]; return l[((l.firstIndex(of: s) ?? 0) + 1) % l.count] }
func speedText(_ s: Float) -> String { s.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(s))" : String(format: "%g", s) }

/// Full-screen player: blurred artwork, the arch artwork with a slow rosette, all the site's controls.
struct PlayerView: View {
    @ObservedObject private var autoTr = AutoTr.shared
    @EnvironmentObject var p: AudioPlayer
    @ObservedObject private var clock = AudioPlayer.shared.clock
    @EnvironmentObject var store: Store
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @EnvironmentObject var repo: Repo
    @ObservedObject private var amb = Ambient.shared
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var drag: Double?
    @State private var showQueue = false
    @State private var showSleep = false
    @State private var showSpeed = false
    @State private var showAmb = false
    @State private var showCh = false
    @ObservedObject private var ch = Chapters.shared
    @State private var breathe = false
    var body: some View {
        if let t = p.current {
            let r = repo.reciter(t.reciterId), art = t.cover.isEmpty ? r?.image : t.cover
            let v = drag ?? (p.duration > 0 ? p.position / p.duration : 0)
            ZStack {
                c.bg.ignoresSafeArea()
                RemoteImage(raw: art).blur(radius: 60).opacity(0.45).ignoresSafeArea()
                LinearGradient(colors: [c.bg.opacity(0.55), c.bg.opacity(0.85), c.bg], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                StarPattern(tile: 110, alpha: 0.6, fade: true).ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Button { dismiss() } label: { Ico(name: "chevron.down", size: 28.8).foregroundStyle(c.text).frame(width: 48, height: 48) }.accessibilityLabel(tr("إغلاق"))
                        VStack(spacing: 0) {
                            Text(tr("يُشغَّل الآن")).font(F.plex(12.5, .medium)).foregroundStyle(c.muted)
                            if !t.surah.isEmpty { Text(tr("سورة {0}", t.surah.replacingOccurrences(of: "سورة ", with: "").trimmingCharacters(in: .whitespaces))).font(F.plex(14, .semibold)).foregroundStyle(c.gold) }
                        }.frame(maxWidth: .infinity)
                        if repo.data?.site.sec("community") != false { Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ui.path.append(.compose("track:" + t.id)) } } label: { SiteIcon(name: "quote", size: 24, color: c.gold).frame(width: 48, height: 48) }.accessibilityLabel(tr("اقتبسها في المجتمع")) }
                        Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ui.menuFor = t } } label: { SiteIcon(name: "dots", size: 24, color: c.text).frame(width: 48, height: 48) }.accessibilityLabel(tr("خيارات أخرى"))
                    }.padding(.top, 4)
                    Spacer(minLength: 8)
                    ZStack {
                        Rosette(color: c.gold.opacity(0.18), spin: p.playing).aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
                        ArchImg(raw: art).aspectRatio(0.8, contentMode: .fit).frame(maxWidth: UIScreen.main.bounds.width * 0.74 * 0.9)
                            .scaleEffect(p.playing ? (breathe ? 1 : 0.97) : 0.9).animation(.spring(response: 0.6, dampingFraction: 0.6), value: p.playing)
                    }.frame(maxHeight: 380)
                    Spacer(minLength: 8)
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(titleL(t)).font(F.amiri(24)).foregroundStyle(c.text).lineLimit(2).id(t.id).transition(.opacity)
                            Button { if let r { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ui.path.append(.reciter(r.id)) } } } label: { Text(nm(r?.name)).font(F.plex(14, .semibold)).foregroundStyle(c.gold) }.buttonStyle(.plain)
                            if !t.location.isEmpty { Text(t.location).font(F.plex(12.5)).foregroundStyle(c.muted) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button { store.toggleFav(t.id) } label: { SiteIcon(name: store.favs.contains(t.id) ? "heart-f" : "heart", size: 26, color: store.favs.contains(t.id) ? c.danger : c.muted).frame(width: 48, height: 48) }.accessibilityLabel(tr("المفضلة"))
                    }
                    SeekBar(value: v, onDrag: { drag = $0 }, onDone: { drag = nil; p.seek($0 * p.duration) }, marks: ch.marks(p.duration)).padding(.top, 8)
                    HStack { Text(Fmt.dur(Int(v * p.duration)).isEmpty ? "0:00" : Fmt.dur(Int(v * p.duration))); Spacer(); Text(Fmt.dur(Int(p.duration)).isEmpty ? "0:00" : Fmt.dur(Int(p.duration))) }.font(F.plex(12.5)).foregroundStyle(c.muted).environment(\.layoutDirection, .leftToRight)
                    ChapterPill(at: v * p.duration) { showCh = true }
                    HStack {
                        Button { p.shuffle.toggle() } label: { SiteIcon(name: "shuffle", size: 24, color: p.shuffle ? c.gold : c.muted).frame(width: 48, height: 48) }.accessibilityLabel(tr("عشوائي"))
                        Spacer()
                        Button { p.prev() } label: { SiteIcon(name: "prev", size: 36, color: c.text).frame(width: 52, height: 52) }.accessibilityLabel(tr("السابق"))
                        Spacer()
                        PlayCircle(playing: p.playing, loading: p.buffering && p.playing, size: 74) { p.toggle() }
                        Spacer()
                        Button { p.next() } label: { SiteIcon(name: "next", size: 36, color: c.text).frame(width: 52, height: 52) }.accessibilityLabel(tr("التالي"))
                        Spacer()
                        Button { p.cycleRepeat() } label: { ZStack { SiteIcon(name: "repeat", size: 24, color: p.repeatMode > 0 ? c.gold : c.muted); if p.repeatMode == 2 { Text(tr("١")).font(F.plex(9, .bold)).foregroundStyle(c.gold) } }.frame(width: 48, height: 48) }.accessibilityLabel(tr("تكرار"))
                    }.padding(.vertical, 10).environment(\.layoutDirection, .leftToRight)
                    HStack {
                        Button { p.skip(-10) } label: { Ico(name: "gobackward.10", size: 25.2).foregroundStyle(c.muted).frame(width: 44, height: 44) }.accessibilityLabel(tr("رجوع ١٠ ثوانٍ"))
                        Spacer(); action("gauge.with.needle", "\(speedText(store.speed))×", store.speed != 1) { showSpeed = true }
                        Spacer(); action("timer", p.sleepAt.map { tr("{0} د", max(0, Int($0.timeIntervalSinceNow / 60) + 1).ar) } ?? tr("مؤقت"), p.sleepOn) { showSleep = true }
                        Spacer(); action("wave", tr("أصوات"), !amb.current.isEmpty) { showAmb = true }
                        Spacer(); action("queue", tr("القائمة"), false) { showQueue = true }
                        Spacer()
                        Button { p.skip(10) } label: { Ico(name: "goforward.10", size: 25.2).foregroundStyle(c.muted).frame(width: 44, height: 44) }.accessibilityLabel(tr("تقديم ١٠ ثوانٍ"))
                    }.environment(\.layoutDirection, .leftToRight)
                    Spacer(minLength: 12)
                }.padding(.horizontal, 24)
            }
            .gesture(DragGesture().onEnded { if $0.translation.height > 80 { dismiss() } })
            .onAppear { withAnimation(.easeInOut(duration: 2.6).repeatForever()) { breathe = true } }
            .environment(\.layoutDirection, L.dir)
            .bzSheet(isPresented: $showQueue) { QueueSheet().presentationDetents([.medium, .large]) }
            .bzSheet(isPresented: $showCh) { ChaptersSheet().presentationDetents([.medium, .large]) }
            .bzSheet(isPresented: $showAmb) { AmbientSheet().presentationDetents([.medium]) }
            .bzSheet(isPresented: $showSpeed) {
                MenuSheet(title: tr("سرعة التشغيل")) {
                    ForEach([Float(0.75), 1, 1.25, 1.5, 1.75, 2], id: \.self) { s in MenuRow(icon: "gauge.with.needle", title: "\(speedText(s))×" + (s == 1 ? tr(" (عادية)") : ""), on: store.speed == s) { p.setSpeed(s); showSpeed = false } }
                }.presentationDetents([.medium])
            }
            .bzSheet(isPresented: $showSleep) {
                MenuSheet(title: tr("مؤقت الإيقاف")) {
                    if let at = p.sleepAt { Text(tr("سيتوقف التشغيل بعد {0} دقيقة تقريبًا.", (Int(at.timeIntervalSinceNow / 60) + 1).ar)).font(F.plex(14)).foregroundStyle(c.muted).padding(.horizontal, 22).padding(.vertical, 4) }
                    ForEach([(0, tr("إيقاف المؤقت")), (10, tr("١٠ دقائق")), (15, tr("١٥ دقيقة")), (30, tr("٣٠ دقيقة")), (45, tr("٤٥ دقيقة")), (60, tr("ساعة")), (-1, tr("عند نهاية التلاوة الحالية"))], id: \.0) { m, l in
                        MenuRow(icon: "timer", title: l) { p.sleep(m); showSleep = false }
                    }
                }.presentationDetents([.medium, .large])
            }
        } else { Color.clear.onAppear { dismiss() } }
    }
    private func action(_ icon: String, _ label: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            VStack(spacing: 2) { Ico(name: icon, size: 22, color: on ? c.gold : c.text); Text(label).font(F.plex(11, .medium)).foregroundStyle(on ? c.gold : c.muted).lineLimit(1) }.padding(.horizontal, 6).padding(.vertical, 4)
        }.buttonStyle(.plain)
    }
}

/// « · سورة الملك» after the reciter's name in the bar, in a recording with several surahs
@MainActor func miniSurah(_ t: Track) -> String {
    let ch = Chapters.shared
    guard ch.id == t.id, ch.list.count > 1 else { return "" }
    let k = ch.at(AudioPlayer.shared.position)
    return k >= 0 ? tr(" · سورة {0}", Quran.surahs[ch.list[k].surah - 1]) : ""
}

/// «قائمة التشغيل».
struct QueueSheet: View {
    @EnvironmentObject var p: AudioPlayer
    @Environment(\.pal) private var c
    var body: some View {
        MenuSheet(title: tr("قائمة التشغيل")) {
            HStack { Chip(text: tr("مسح القادم"), icon: "trash") { p.clearUpcoming() } }.padding(.horizontal, 18).padding(.bottom, 6)
            ForEach(Array(p.queue.enumerated()), id: \.offset) { i, q in
                let cur = i == p.index
                HStack(spacing: 10) {
                    Group { if cur { Equalizer(playing: p.playing, color: c.gold) } else { Text((i + 1).ar).font(F.plex(13)).foregroundStyle(c.faint) } }.frame(width: 28)
                    RemoteImage(raw: q.cover.isEmpty ? Repo.shared.reciter(q.reciterId)?.image : q.cover).frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 0) { Text(titleL(q)).font(F.plex(14, .semibold)).foregroundStyle(cur ? c.gold : c.text).lineLimit(1); Text(Repo.shared.reciter(q.reciterId)?.name ?? "").font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(1) }
                    Spacer()
                    if !cur {
                        Button { p.move(i, max(0, i - 1)) } label: { SiteIcon(name: "up", size: 20, color: c.muted).frame(width: 34, height: 34) }.accessibilityLabel(tr("تحريك لأعلى"))
                        Button { p.remove(at: i) } label: { SiteIcon(name: "close", size: 20, color: c.muted).frame(width: 34, height: 34) }.accessibilityLabel(tr("إزالة"))
                    }
                }
                .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 8).background(cur ? c.gold.opacity(0.12) : .clear)
                .contentShape(Rectangle()).onTapGesture { p.playAt(i) }
            }
        }
    }
}

/// «خيارات أخرى» for a recitation — the same options as the site and the Android app.
struct TrackMenu: View {
    let t: Track
    @EnvironmentObject var p: AudioPlayer
    @EnvironmentObject var store: Store
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var addList = false
    @State private var newList = ""
    var body: some View {
        let r = repo.reciter(t.reciterId), s = repo.data?.site
        let feat = { (k: String) in s?.j["features"][k].bool(true) ?? true }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    RemoteImage(raw: t.cover.isEmpty ? r?.image : t.cover).frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 1) { Text(titleL(t)).font(F.plex(16, .semibold)).foregroundStyle(c.text).lineLimit(2); Text(nm(r?.name)).font(F.plex(12.5)).foregroundStyle(c.gold) }
                    Spacer()
                }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 6)
                if !t.description.isEmpty { Text(t.description).font(F.plex(12.5)).foregroundStyle(c.muted).padding(.horizontal, 22).padding(.vertical, 4) }
                Rectangle().fill(c.lineSoft).frame(height: 1).padding(.vertical, 6)
                let fav = store.favs.contains(t.id)
                MenuRow(icon: fav ? "heart-f" : "heart", title: fav ? tr("إزالة من المفضلة") : tr("إضافة للمفضلة")) { store.toggleFav(t.id); ui.say(fav ? tr("أُزيلت من المفضلة") : tr("أُضيفت إلى المفضلة")); dismiss() }
                if t.isVideo { MenuRow(icon: "film", title: tr("مشاهدة الفيديو")) { dismiss(); ui.openWatch(t.id) } }
                if t.isVideo && !t.audio.isEmpty { MenuRow(icon: "headphones", title: tr("استماع صوتي"), sub: tr("تشغيل صوت التلاوة فقط مع إمكانية التنقل في التطبيق")) { dismiss(); AudioPlayer.shared.play(t) } }
                else {
                    MenuRow(icon: "next", title: tr("تشغيل بعد الحالية")) { p.playNext(t); ui.say(tr("ستُشغَّل بعد التلاوة الحالية")); dismiss() }
                    MenuRow(icon: "queue", title: tr("إضافة لقائمة الانتظار")) { p.enqueue(t); ui.say(tr("أُضيفت إلى قائمة الانتظار")); dismiss() }
                }
                if feat("playlists") { MenuRow(icon: "playlist", title: tr("إضافة لقائمة تشغيل")) { addList = true } }
                if feat("listenLater") { MenuRow(icon: "clock", title: store.later.contains(t.id) ? tr("إزالة من «استمع لاحقًا»") : tr("استمع لاحقًا")) { let on = store.toggleLater(t.id); ui.say(on ? tr("أُضيفت إلى استمع لاحقًا") : tr("أُزيلت من استمع لاحقًا")); dismiss() } }
                if s?.sec("community") != false { MenuRow(icon: "quote", title: tr("اقتبسها في المجتمع"), sub: tr("انشر التلاوة في منشور مع تعليقك")) { dismiss(); ui.path.append(.compose("track:" + t.id)) } }
                if feat("shareLinks") { MenuRow(icon: "share", title: tr("مشاركة")) { dismiss(); share("\(t.title) — \(r?.name ?? "")\n\(Repo.site)track/\(Repo.enc(t.id))") } }
                if t.isVideo && t.downloadable { MenuRow(icon: "download", title: tr("تحميل الفيديو"), sub: tr("اختر الجودة واحفظه للمشاهدة دون إنترنت")) { dismiss(); ui.openWatch(t.id) } }
                if feat("offline") && s?.allowDownloads != false && t.downloadable && !t.isVideo {
                    let have = OfflineFiles.local(t.id) != nil
                    MenuRow(icon: "offline", title: have ? tr("حذف من «بدون إنترنت»") : tr("حفظ للاستماع بدون إنترنت")) {
                        if have { OfflineFiles.delete(t.id); ui.say(tr("حُذفت من «بدون إنترنت»")) }
                        else { Task { let ok = await OfflineFiles.save(t); ui.say(ok ? tr("حُفظت — يمكنك سماعها بدون إنترنت") : tr("تعذّر حفظ الملف على الجهاز")) } }
                        dismiss()
                    }
                }
                if let r { MenuRow(icon: "mic", title: tr("صفحة {0}", r.name)) { dismiss(); ui.path.append(.reciter(r.id)) } }
            }.padding(.bottom, 16)
        }
        .background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir)
        .bzSheet(isPresented: $addList) {
            MenuSheet(title: tr("إضافة إلى قائمة تشغيل")) {
                ForEach(store.playlists) { pl in MenuRow(icon: "queue", title: pl.name, sub: tr("{0} تلاوة", pl.ids.count.ar)) { _ = store.addToPlaylist(pl.name, t.id); ui.say(tr("أُضيفت إلى «{0}»", pl.name)); addList = false; dismiss() } }
                HStack(spacing: 10) {
                    TextField(tr("اسم قائمة جديدة"), text: Binding(get: { newList }, set: { newList = String($0.prefix(40)) })).font(F.plex(15)).padding(12).background(RoundedRectangle(cornerRadius: 16).fill(c.surface.opacity(0.45))).overlay(RoundedRectangle(cornerRadius: 16).stroke(c.line))
                    GoldButton(title: tr("إنشاء وإضافة")) { let n = newList.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }; _ = store.addToPlaylist(n, t.id); ui.say(tr("أُضيفت إلى «{0}»", n)); addList = false; dismiss() }
                }.padding(.horizontal, 18).padding(.vertical, 10)
            }.presentationDetents([.medium, .large])
        }
    }
}


// MARK: - «سور هذه التلاوة»
/// A recording with several surahs (a juz, a night of taraweeh…) prepared in the dashboard knows where each surah starts:
/// the player shows the surah being recited and jumps straight to any of them (as on the site and Android).
struct Chapter: Hashable { let surah: Int; let at: Double; let end: Double; let from: Int; let to: Int }

@MainActor final class Chapters: ObservableObject {
    static let shared = Chapters()
    @Published private(set) var id = ""
    @Published private(set) var list: [Chapter] = []
    /// the surah being repeated (its index), or -1
    @Published var loop = -1
    private var cache: [String: [Chapter]] = [:]
    private var timer: Timer?
    private var task: Task<Void, Never>?

    /// the recitation now playing changed
    func follow(_ t: Track?) {
        guard let t else { id = ""; list = []; loop = -1; return }
        guard t.id != id else { return }
        id = t.id; list = []; loop = -1
        if let c = cache[t.id] { list = c; return }
        guard !t.isVideo, Repo.shared.data?.readableTracks[t.id] != nil else { return }
        task?.cancel()
        task = Task { [weak self] in
            guard let tm = await Repo.shared.trackTimes(t.id), let self, self.id == t.id else { return }
            func ch(_ s: Int, _ a: [[Int]]) -> Chapter? {
                guard (1...114).contains(s), !a.isEmpty else { return nil }
                return Chapter(surah: s, at: Double(a.map { $0[1] }.min() ?? 0) / 1000, end: Double(a.map { $0[2] }.max() ?? 0) / 1000, from: a.map { $0[0] }.min() ?? 1, to: a.map { $0[0] }.max() ?? 1)
            }
            var l = ([ch(tm.surah, tm.ayahs)] + tm.parts.filter { !$0.rakah }.map { ch($0.surah, $0.ayahs) }).compactMap { $0 }.sorted { $0.at < $1.at }
            if l.count < 2 { l = [] } else { l[0] = Chapter(surah: l[0].surah, at: 0, end: l[0].end, from: l[0].from, to: l[0].to) }   // the opening belongs to the first surah
            self.cache[t.id] = l
            if self.id == t.id { self.list = l }
        }
    }
    func at(_ sec: Double) -> Int { list.lastIndex { sec >= $0.at - 0.3 } ?? -1 }
    func marks(_ dur: Double) -> [Double] {
        let tot = dur > 0 ? dur : (list.last?.end ?? 0)
        return tot > 0 ? list.dropFirst().map { min(1, max(0, $0.at / tot)) } : []
    }
    private func endOf(_ i: Int) -> Double { i + 1 < list.count ? list[i + 1].at : list[i].end + 0.6 }
    func go(_ i: Int) {
        guard list.indices.contains(i) else { return }
        if loop >= 0 && loop != i { setLoop(-1) }   // going to another surah ends the repeat
        let p = AudioPlayer.shared
        p.seek(list[i].at + (i > 0 ? 0.05 : 0)); if !p.playing { p.toggle() }
    }
    /// «كرّر هذه السورة»: when it ends it starts again, until turned off or another recitation plays
    func setLoop(_ i: Int) {
        loop = i; timer?.invalidate(); timer = nil
        guard i >= 0, list.indices.contains(i) else { return }
        let p = AudioPlayer.shared
        if p.position < list[i].at || p.position >= endOf(i) { p.seek(list[i].at + (i > 0 ? 0.05 : 0)) }
        if !p.playing { p.toggle() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.loop >= 0, self.list.indices.contains(self.loop), AudioPlayer.shared.current?.id == self.id else { self?.setLoop(-1); return }
                let k = self.loop, pos = AudioPlayer.shared.position
                if pos >= self.endOf(k) - 0.12 || pos < self.list[k].at - 1.5 { AudioPlayer.shared.seek(self.list[k].at + (k > 0 ? 0.05 : 0)) }
            }
        }
    }
}

/// Under the seek bar: «سورة الملك (٣ من ٧)» — tap for the list.
struct ChapterPill: View {
    let at: Double
    let open: () -> Void
    @ObservedObject private var ch = Chapters.shared
    @EnvironmentObject var p: AudioPlayer
    @Environment(\.pal) private var c
    var body: some View {
        if ch.list.count > 1, ch.id == p.current?.id {
            let k = max(0, ch.at(at))
            Button(action: open) {
                HStack(spacing: 6) {
                    SiteIcon(name: "book", size: 16, color: c.gold)
                    Text(tr("سورة {0} ({1} من {2})", Quran.surahs[ch.list[k].surah - 1], (k + 1).ar, ch.list.count.ar) + (ch.loop == k ? tr(" · تكرار") : ""))
                        .font(F.plex(13, .semibold)).foregroundStyle(c.gold).lineLimit(1)
                    Ico(name: "chevron.down", size: 13, color: c.gold)
                }
                .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(c.gold.opacity(0.14)))
            }.buttonStyle(.plain).padding(.top, 4)
        }
    }
}

/// The surahs in the recording: tap one to go straight to it, or repeat it.
struct ChaptersSheet: View {
    @ObservedObject private var ch = Chapters.shared
    @EnvironmentObject var p: AudioPlayer
    /* UI actions only */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let cur = ch.at(p.position)
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("سور هذه التلاوة")).font(F.amiri(22)).foregroundStyle(c.text).padding(.horizontal, 20).padding(.top, 18)
            Text(tr("اضغط على أي سورة للانتقال إليها، أو على زر التكرار لتكرارها.")).font(F.plex(13)).foregroundStyle(c.muted).padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 8)
            ScrollViewReader { sr in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(ch.list.enumerated()), id: \.offset) { i, x in row(i, x, on: i == cur).id(i) }
                    }.padding(.horizontal, 14).padding(.bottom, 16)
                }.onAppear { if cur > 1 { sr.scrollTo(cur - 1, anchor: .top) } }
            }
        }
        .background(c.bg.ignoresSafeArea())
        .environment(\.layoutDirection, L.dir)
    }
    private func row(_ i: Int, _ x: Chapter, on: Bool) -> some View {
        let looping = ch.loop == i, name = Quran.surahs[x.surah - 1]
        return HStack(spacing: 12) {
            Button { ch.go(i); dismiss() } label: {
                HStack(spacing: 12) {
                    Text((i + 1).ar).font(F.plex(13, .bold)).foregroundStyle(on ? c.onGold : c.gold).frame(width: 30, height: 30).background(Circle().fill(on ? c.gold : c.surface2))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr("سورة {0}", name)).font(F.plex(15, .semibold)).foregroundStyle(c.text)
                        Text(x.from == 1 && x.to >= Quran.ayahs[x.surah - 1] ? tr("كاملة") : tr("الآيات {0}–{1}", x.from.ar, x.to.ar)).font(F.plex(12)).foregroundStyle(c.muted)
                    }
                    Spacer(minLength: 4)
                    Text(Fmt.dur(Int(x.at)).isEmpty ? "0:00" : Fmt.dur(Int(x.at))).font(F.plex(12)).foregroundStyle(c.muted).environment(\.layoutDirection, .leftToRight)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button {
                if looping { ch.setLoop(-1); ui.say(tr("أُوقف تكرار السورة")) }
                else { ch.setLoop(i); ui.say(tr("ستتكرر سورة {0} حتى توقفها", name)) }
                dismiss()
            } label: { SiteIcon(name: "repeat", size: 19, color: looping ? c.gold : c.muted).frame(width: 36, height: 36).background(Circle().fill(looping ? c.gold.opacity(0.16) : .clear)) }
                .buttonStyle(.plain).accessibilityLabel(looping ? tr("إيقاف تكرار السورة") : tr("كرّر هذه السورة"))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(on ? c.gold.opacity(0.12) : c.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? c.gold : .clear, lineWidth: 1))
    }
}
