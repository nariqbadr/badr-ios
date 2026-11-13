import SwiftUI

/// Thin seek bar with a round thumb (fills from the right in Arabic).
struct SeekBar: View {
    let value: Double
    let onDrag: (Double) -> Void
    let onDone: (Double) -> Void
    @Environment(\.pal) private var c
    var body: some View {
        GeometryReader { g in
            let w: CGFloat = max(g.size.width, 1), v: CGFloat = CGFloat(min(max(value, 0), 1))
            ZStack(alignment: .trailing) {
                Capsule().fill(c.lineSoft).frame(height: 4)
                Capsule().fill(c.gold).frame(width: w * v, height: 4)
                Circle().fill(c.gold).frame(width: 14, height: 14).shadow(color: c.gold.opacity(0.4), radius: 6)
                    .offset(x: 7 - w * v)
            }
            .frame(height: 26).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in onDrag(Double(min(max(1 - e.location.x / w, 0), 1))) }
                .onEnded { e in onDone(Double(min(max(1 - e.location.x / w, 0), 1))) })
        }.frame(height: 26).environment(\.layoutDirection, .leftToRight)
    }
}

/// Docked player bar — the site's bottom player laid out for a phone (like the Android app):
/// artwork · title · reciter · heart / time — seek bar — time / speed · repeat · prev · ⟲10 · PLAY · 10⟳ · next · shuffle · queue.
struct MiniPlayer: View {
    @EnvironmentObject var p: AudioPlayer
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
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
                        Text(t.title).font(F.plex(15, .bold)).foregroundStyle(c.text).lineLimit(1)
                        Text(p.nowLabel?.0 == t.id ? p.nowLabel!.1 : (Repo.shared.reciter(t.reciterId)?.name ?? "")).font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(1)
                    }.padding(.leading, 12).frame(maxWidth: .infinity, alignment: .leading)
                    Button { store.toggleFav(t.id) } label: { SiteIcon(name: store.favs.contains(t.id) ? "heart-f" : "heart", size: 22, color: store.favs.contains(t.id) ? c.danger : c.muted).frame(width: 40, height: 40) }.accessibilityLabel("المفضلة")
                    Button { ui.playerOpen = true } label: { Image(systemName: "chevron.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(c.muted).frame(width: 38, height: 38) }.accessibilityLabel("فتح المشغّل")
                    Button { p.close() } label: { SiteIcon(name: "close", size: 20, color: c.muted).frame(width: 38, height: 38) }.accessibilityLabel("إغلاق المشغّل")
                }
                HStack(spacing: 0) {
                    Text(Fmt.dur(Int(v * p.duration)).isEmpty ? "0:00" : Fmt.dur(Int(v * p.duration))).font(F.plex(11)).foregroundStyle(c.muted).frame(width: 40)
                    SeekBar(value: v, onDrag: { drag = $0 }, onDone: { drag = nil; p.seek($0 * p.duration) })
                    Text(Fmt.dur(Int(p.duration)).isEmpty ? "--:--" : Fmt.dur(Int(p.duration))).font(F.plex(11)).foregroundStyle(c.muted).frame(width: 40)
                }.padding(.top, 4)
                HStack(spacing: 0) {
                    Button { p.setSpeed(nextSpeed(store.speed)) } label: { Text("×" + speedText(store.speed)).font(F.plex(13, .bold)).foregroundStyle(store.speed != 1 ? c.gold : c.muted).frame(width: 40, height: 40) }
                    Spacer(minLength: 0)
                    Button { p.cycleRepeat() } label: { ZStack { SiteIcon(name: "repeat", size: 22, color: p.repeatMode > 0 || p.repN > 0 ? c.gold : c.muted); if p.repeatMode == 2 { Text("١").font(F.plex(9, .bold)).foregroundStyle(c.gold) } }.frame(width: 40, height: 40) }.accessibilityLabel("تكرار")
                    Spacer(minLength: 0)
                    Button { p.prev() } label: { SiteIcon(name: "prev", size: 24, color: c.text).frame(width: 40, height: 40) }.accessibilityLabel("السابق")
                    Spacer(minLength: 0)
                    Button { p.skip(10) } label: { Image(systemName: "gobackward.10").font(.system(size: 20)).foregroundStyle(c.text).frame(width: 40, height: 40) }.accessibilityLabel("تقديم ١٠ ثوانٍ")
                    Spacer(minLength: 0)
                    Button { p.toggle() } label: {
                        ZStack { Circle().fill(c.gold).shadow(color: c.gold.opacity(0.6), radius: 8); if p.buffering && p.playing { ProgressView().tint(c.onGold) } else { SiteIcon(name: p.playing ? "pause" : "play", size: 24, color: c.onGold) } }.frame(width: 54, height: 54)
                    }.accessibilityLabel(p.playing ? "إيقاف مؤقت" : "تشغيل")
                    Spacer(minLength: 0)
                    Button { p.skip(-10) } label: { Image(systemName: "goforward.10").font(.system(size: 20)).foregroundStyle(c.text).frame(width: 40, height: 40) }.accessibilityLabel("رجوع ١٠ ثوانٍ")
                    Spacer(minLength: 0)
                    Button { p.next() } label: { SiteIcon(name: "next", size: 24, color: c.text).frame(width: 40, height: 40) }.accessibilityLabel("التالي")
                    Spacer(minLength: 0)
                    Button { p.shuffle.toggle() } label: { SiteIcon(name: "shuffle", size: 22, color: p.shuffle ? c.gold : c.muted).frame(width: 40, height: 40) }.accessibilityLabel("عشوائي")
                    Spacer(minLength: 0)
                    Button { ui.playerOpen = true } label: { SiteIcon(name: "queue", size: 22, color: c.muted).frame(width: 40, height: 40) }.accessibilityLabel("قائمة الانتظار")
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
    @EnvironmentObject var p: AudioPlayer
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var repo: Repo
    @ObservedObject private var amb = Ambient.shared
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var drag: Double?
    @State private var showQueue = false
    @State private var showSleep = false
    @State private var showSpeed = false
    @State private var showAmb = false
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
                        Button { dismiss() } label: { Image(systemName: "chevron.down").font(.system(size: 24, weight: .medium)).foregroundStyle(c.text).frame(width: 48, height: 48) }.accessibilityLabel("إغلاق")
                        VStack(spacing: 0) {
                            Text("يُشغَّل الآن").font(F.plex(12.5, .medium)).foregroundStyle(c.muted)
                            if !t.surah.isEmpty { Text("سورة " + t.surah.replacingOccurrences(of: "سورة ", with: "")).font(F.plex(14, .semibold)).foregroundStyle(c.gold) }
                        }.frame(maxWidth: .infinity)
                        if repo.data?.site.sec("community") != false { Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ui.path.append(.compose("track:" + t.id)) } } label: { SiteIcon(name: "quote", size: 24, color: c.gold).frame(width: 48, height: 48) }.accessibilityLabel("اقتبسها في المجتمع") }
                        Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ui.menuFor = t } } label: { SiteIcon(name: "dots", size: 24, color: c.text).frame(width: 48, height: 48) }.accessibilityLabel("خيارات أخرى")
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
                            Text(t.title).font(F.amiri(24)).foregroundStyle(c.text).lineLimit(2).id(t.id).transition(.opacity)
                            Button { if let r { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ui.path.append(.reciter(r.id)) } } } label: { Text(r?.name ?? "").font(F.plex(14, .semibold)).foregroundStyle(c.gold) }.buttonStyle(.plain)
                            if !t.location.isEmpty { Text(t.location).font(F.plex(12.5)).foregroundStyle(c.muted) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button { store.toggleFav(t.id) } label: { SiteIcon(name: store.favs.contains(t.id) ? "heart-f" : "heart", size: 26, color: store.favs.contains(t.id) ? c.danger : c.muted).frame(width: 48, height: 48) }.accessibilityLabel("المفضلة")
                    }
                    SeekBar(value: v, onDrag: { drag = $0 }, onDone: { drag = nil; p.seek($0 * p.duration) }).padding(.top, 8)
                    HStack { Text(Fmt.dur(Int(v * p.duration)).isEmpty ? "0:00" : Fmt.dur(Int(v * p.duration))); Spacer(); Text(Fmt.dur(Int(p.duration)).isEmpty ? "0:00" : Fmt.dur(Int(p.duration))) }.font(F.plex(12.5)).foregroundStyle(c.muted)
                    HStack {
                        Button { p.shuffle.toggle() } label: { SiteIcon(name: "shuffle", size: 24, color: p.shuffle ? c.gold : c.muted).frame(width: 48, height: 48) }.accessibilityLabel("عشوائي")
                        Spacer()
                        Button { p.prev() } label: { SiteIcon(name: "prev", size: 36, color: c.text).frame(width: 52, height: 52) }.accessibilityLabel("السابق")
                        Spacer()
                        PlayCircle(playing: p.playing, loading: p.buffering && p.playing, size: 74) { p.toggle() }
                        Spacer()
                        Button { p.next() } label: { SiteIcon(name: "next", size: 36, color: c.text).frame(width: 52, height: 52) }.accessibilityLabel("التالي")
                        Spacer()
                        Button { p.cycleRepeat() } label: { ZStack { SiteIcon(name: "repeat", size: 24, color: p.repeatMode > 0 ? c.gold : c.muted); if p.repeatMode == 2 { Text("١").font(F.plex(9, .bold)).foregroundStyle(c.gold) } }.frame(width: 48, height: 48) }.accessibilityLabel("تكرار")
                    }.padding(.vertical, 10)
                    HStack {
                        Button { p.skip(-10) } label: { Image(systemName: "goforward.10").font(.system(size: 21)).foregroundStyle(c.muted).frame(width: 44, height: 44) }.accessibilityLabel("رجوع ١٠ ثوانٍ")
                        Spacer(); action("gauge.with.needle", "\(speedText(store.speed))×", store.speed != 1) { showSpeed = true }
                        Spacer(); action("timer", p.sleepAt.map { "\(max(0, Int($0.timeIntervalSinceNow / 60) + 1).ar) د" } ?? "مؤقت", p.sleepOn) { showSleep = true }
                        Spacer(); action("wave", "أصوات", !amb.current.isEmpty) { showAmb = true }
                        Spacer(); action("queue", "القائمة", false) { showQueue = true }
                        Spacer()
                        Button { p.skip(10) } label: { Image(systemName: "gobackward.10").font(.system(size: 21)).foregroundStyle(c.muted).frame(width: 44, height: 44) }.accessibilityLabel("تقديم ١٠ ثوانٍ")
                    }
                    Spacer(minLength: 12)
                }.padding(.horizontal, 24)
            }
            .gesture(DragGesture().onEnded { if $0.translation.height > 80 { dismiss() } })
            .onAppear { withAnimation(.easeInOut(duration: 2.6).repeatForever()) { breathe = true } }
            .environment(\.layoutDirection, .rightToLeft)
            .sheet(isPresented: $showQueue) { QueueSheet().presentationDetents([.medium, .large]) }
            .sheet(isPresented: $showAmb) { AmbientSheet().presentationDetents([.medium]) }
            .sheet(isPresented: $showSpeed) {
                MenuSheet(title: "سرعة التشغيل") {
                    ForEach([Float(0.75), 1, 1.25, 1.5, 1.75, 2], id: \.self) { s in MenuRow(icon: "gauge.with.needle", title: "\(speedText(s))×" + (s == 1 ? " (عادية)" : ""), on: store.speed == s) { p.setSpeed(s); showSpeed = false } }
                }.presentationDetents([.medium])
            }
            .sheet(isPresented: $showSleep) {
                MenuSheet(title: "مؤقت الإيقاف") {
                    if let at = p.sleepAt { Text("سيتوقف التشغيل بعد \((Int(at.timeIntervalSinceNow / 60) + 1).ar) دقيقة تقريبًا.").font(F.plex(14)).foregroundStyle(c.muted).padding(.horizontal, 22).padding(.vertical, 4) }
                    ForEach([(0, "إيقاف المؤقت"), (10, "١٠ دقائق"), (15, "١٥ دقيقة"), (30, "٣٠ دقيقة"), (45, "٤٥ دقيقة"), (60, "ساعة"), (-1, "عند نهاية التلاوة الحالية")], id: \.0) { m, l in
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

/// «قائمة التشغيل».
struct QueueSheet: View {
    @EnvironmentObject var p: AudioPlayer
    @Environment(\.pal) private var c
    var body: some View {
        MenuSheet(title: "قائمة التشغيل") {
            HStack { Chip(text: "مسح القادم", icon: "trash") { p.clearUpcoming() } }.padding(.horizontal, 18).padding(.bottom, 6)
            ForEach(Array(p.queue.enumerated()), id: \.offset) { i, q in
                let cur = i == p.index
                HStack(spacing: 10) {
                    Group { if cur { Equalizer(playing: p.playing, color: c.gold) } else { Text((i + 1).ar).font(F.plex(13)).foregroundStyle(c.faint) } }.frame(width: 28)
                    RemoteImage(raw: q.cover.isEmpty ? Repo.shared.reciter(q.reciterId)?.image : q.cover).frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 0) { Text(q.title).font(F.plex(14, .semibold)).foregroundStyle(cur ? c.gold : c.text).lineLimit(1); Text(Repo.shared.reciter(q.reciterId)?.name ?? "").font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(1) }
                    Spacer()
                    if !cur {
                        Button { p.move(i, max(0, i - 1)) } label: { SiteIcon(name: "up", size: 20, color: c.muted).frame(width: 34, height: 34) }.accessibilityLabel("تحريك لأعلى")
                        Button { p.remove(at: i) } label: { SiteIcon(name: "close", size: 20, color: c.muted).frame(width: 34, height: 34) }.accessibilityLabel("إزالة")
                    }
                }
                .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 8).background(cur ? c.gold.opacity(0.12) : .clear)
                .contentShape(Rectangle()).onTapGesture { p.playAt(i) }
            }
        }
    }
}

/// «خيارات أخرى» for a recitation (same options as the site).
struct TrackMenu: View {
    let t: Track
    @EnvironmentObject var p: AudioPlayer
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var addList = false
    @State private var newList = ""
    var body: some View {
        let r = repo.reciter(t.reciterId)
        let s = repo.data?.site
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    RemoteImage(raw: repo.image(for: t)).frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading) { Text(t.title).font(F.plex(16, .semibold)).lineLimit(2); Text(r?.name ?? "").font(F.plex(13)).foregroundStyle(c.gold) }
                }.padding(20)
                if !t.description.isEmpty { Text(t.description).font(F.plex(13)).foregroundStyle(c.muted).padding(.horizontal, 20).padding(.bottom, 8) }
                Divider().overlay(c.lineSoft)
                item("text.line.first.and.arrowtriangle.forward", "تشغيل بعد الحالية") { p.playNext(t); ui.say("ستُشغَّل بعد التلاوة الحالية") }
                item("text.append", "إضافة لقائمة الانتظار") { p.enqueue(t); ui.say("أُضيفت إلى قائمة الانتظار") }
                Button { addList = true } label: {
                    HStack(spacing: 14) { Image(systemName: "music.note.list").foregroundStyle(c.gold).frame(width: 24); Text("أضف إلى قائمة تشغيل").font(F.plex(15.5)).foregroundStyle(c.text); Spacer() }
                        .padding(.horizontal, 22).padding(.vertical, 14).contentShape(Rectangle())
                }.buttonStyle(.plain)
                item("clock", store.later.contains(t.id) ? "إزالة من «استمع لاحقًا»" : "استمع لاحقًا") { let on = store.toggleLater(t.id); ui.say(on ? "أُضيفت إلى استمع لاحقًا" : "أُزيلت") }
                if s?.sec("community") != false { item("quote.bubble", "اقتبسها في المجتمع") { ui.path.append(.compose("track:" + t.id)) } }
                item("square.and.arrow.up", "مشاركة") { share("\(t.title) — \(r?.name ?? "")\n\(Repo.site)track/\(Repo.enc(t.id))") }
                if s?.allowDownloads != false && t.downloadable {
                    let have = OfflineFiles.local(t.id) != nil
                    item(have ? "trash" : "arrow.down.circle", have ? "حذف من «بدون إنترنت»" : (saving ? "جارٍ الحفظ…" : "حفظ للاستماع بدون إنترنت")) {
                        if have { OfflineFiles.delete(t.id); ui.say("حُذفت") } else {
                            ui.say("جارٍ حفظ التلاوة على الجهاز…")
                            Task { let ok = await OfflineFiles.save(t); await MainActor.run { ui.say(ok ? "حُفظت — يمكنك سماعها بدون إنترنت" : "تعذّر الحفظ") } }
                        }
                    }
                }
                if let r { item("mic", "صفحة \(r.name)") { ui.path.append(.reciter(r.id)) } }
            }
        }
        .background(c.bg2).environment(\.layoutDirection, .rightToLeft)
        .alert("أضف إلى قائمة تشغيل", isPresented: $addList) {
            ForEach(store.playlists) { p in Button(p.name) { ui.say(store.addToPlaylist(p.name, t.id) ? "أُضيفت إلى «\(p.name)»" : "موجودة في «\(p.name)»") } }
            TextField("اسم قائمة جديدة", text: $newList)
            Button("إنشاء وإضافة") { let n = newList; newList = ""; if store.addToPlaylist(n, t.id) { ui.say("أُضيفت إلى «\(n.trimmingCharacters(in: .whitespaces))»") } }
            Button("إلغاء", role: .cancel) {}
        }
    }
    private func item(_ icon: String, _ title: String, _ act: @escaping () -> Void) -> some View {
        Button { dismiss(); act() } label: {
            HStack(spacing: 14) { Image(systemName: icon).foregroundStyle(c.gold).frame(width: 24); Text(title).font(F.plex(15.5)).foregroundStyle(c.text); Spacer() }
                .padding(.horizontal, 22).padding(.vertical, 14).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
