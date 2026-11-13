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

/// Docked player bar (like the site's player bar, laid out for a phone).
struct MiniPlayer: View {
    @EnvironmentObject var p: AudioPlayer
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var drag: Double?
    var body: some View {
        if let t = p.current {
            let v = drag ?? (p.duration > 0 ? p.position / p.duration : 0)
            VStack(spacing: 2) {
                HStack(spacing: 12) {
                    RemoteImage(raw: Repo.shared.image(for: t)).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(F.plex(15, .bold)).foregroundStyle(c.text).lineLimit(1)
                        Text(p.nowLabel?.0 == t.id ? p.nowLabel!.1 : (Repo.shared.reciter(t.reciterId)?.name ?? "")).font(F.plex(12.5)).foregroundStyle(p.nowLabel?.0 == t.id ? c.gold : c.muted).lineLimit(1)
                    }
                    Spacer()
                    Button { store.toggleFav(t.id) } label: { Image(systemName: store.favs.contains(t.id) ? "heart.fill" : "heart").foregroundStyle(store.favs.contains(t.id) ? c.danger : c.muted) }
                    Button { ui.playerOpen = true } label: { Image(systemName: "chevron.up").foregroundStyle(c.muted).frame(width: 30, height: 30) }
                }
                HStack(spacing: 8) {
                    Text(Fmt.dur(Int(v * p.duration)).isEmpty ? "0:00" : Fmt.dur(Int(v * p.duration))).font(F.plex(11)).foregroundStyle(c.muted).frame(width: 40)
                    SeekBar(value: v, onDrag: { drag = $0 }, onDone: { drag = nil; p.seek($0 * p.duration) })
                    Text(Fmt.dur(Int(p.duration)).isEmpty ? "--:--" : Fmt.dur(Int(p.duration))).font(F.plex(11)).foregroundStyle(c.muted).frame(width: 40)
                }
                HStack {
                    Button { p.setSpeed(nextSpeed(store.speed)) } label: { Text("×" + speedText(store.speed)).font(F.plex(13, .bold)).foregroundStyle(store.speed != 1 ? c.gold : c.muted) }
                    Spacer()
                    Button { p.cycleRepeat() } label: { Image(systemName: p.repeatMode == 2 ? "repeat.1" : "repeat").foregroundStyle(p.repeatMode > 0 ? c.gold : c.muted) }
                    Spacer()
                    Button { p.prev() } label: { Image(systemName: "backward.end.fill").font(.system(size: 20)).foregroundStyle(c.text) }
                    Spacer()
                    Button { p.toggle() } label: {
                        Image(systemName: p.playing ? "pause.fill" : "play.fill").font(.system(size: 22)).foregroundStyle(c.onGold)
                            .frame(width: 54, height: 54).background(Circle().fill(c.gold)).shadow(color: c.gold.opacity(0.5), radius: 10)
                    }
                    Spacer()
                    Button { p.next() } label: { Image(systemName: "forward.end.fill").font(.system(size: 20)).foregroundStyle(c.text) }
                    Spacer()
                    Button { p.shuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(p.shuffle ? c.gold : c.muted) }
                    Spacer()
                    Button { ui.playerOpen = true } label: { Image(systemName: "list.bullet").foregroundStyle(c.muted) }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
            .background(LinearGradient(colors: [c.bg2, c.bg], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(c.lineSoft).frame(height: 1) }
            .contentShape(Rectangle()).onTapGesture { ui.playerOpen = true }
            .buttonStyle(.plain)
        }
    }
}
func nextSpeed(_ s: Float) -> Float { let l: [Float] = [1, 1.25, 1.5, 1.75, 2, 0.75]; return l[((l.firstIndex(of: s) ?? 0) + 1) % l.count] }
func speedText(_ s: Float) -> String { s.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(s))" : String(format: "%g", s) }

/// Full-screen player.
struct PlayerView: View {
    @ObservedObject private var amb = Ambient.shared
    @State private var showAmb = false
    @EnvironmentObject var p: AudioPlayer
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var drag: Double?
    @State private var showQueue = false
    @State private var showSleep = false
    var body: some View {
        ZStack {
            Backdrop()
            if let t = p.current {
                RemoteImage(raw: Repo.shared.image(for: t)).blur(radius: 50).opacity(0.35).ignoresSafeArea()
                VStack(spacing: 18) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "chevron.down").font(.system(size: 20, weight: .semibold)) }
                        Spacer()
                        VStack(spacing: 2) { Text("يُشغَّل الآن").font(F.plex(12)).foregroundStyle(c.muted); if !t.surah.isEmpty { Text(t.surah).font(F.plex(13, .semibold)).foregroundStyle(c.gold) } }
                        Spacer()
                        Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ui.menuFor = t } } label: { Image(systemName: "ellipsis") }
                    }.foregroundStyle(c.text).padding(.horizontal, 20).padding(.top, 10)
                    Spacer(minLength: 0)
                    RemoteImage(raw: Repo.shared.image(for: t)).frame(width: 250, height: 310).clipShape(ArchShape())
                        .overlay(ArchShape().stroke(c.gold.opacity(0.6), lineWidth: 1.5)).shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                    VStack(spacing: 6) {
                        Text(t.title).font(F.amiri(24)).foregroundStyle(c.text).multilineTextAlignment(.center).lineLimit(2)
                        Text(Repo.shared.reciter(t.reciterId)?.name ?? "").font(F.plex(14)).foregroundStyle(c.gold)
                    }.padding(.horizontal, 24)
                    let v = drag ?? (p.duration > 0 ? p.position / p.duration : 0)
                    VStack(spacing: 4) {
                        SeekBar(value: v, onDrag: { drag = $0 }, onDone: { drag = nil; p.seek($0 * p.duration) })
                        HStack { Text(Fmt.dur(Int(v * p.duration))); Spacer(); Text(Fmt.dur(Int(p.duration))) }.font(F.plex(12)).foregroundStyle(c.muted)
                    }.padding(.horizontal, 28)
                    HStack(spacing: 30) {
                        Button { p.shuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(p.shuffle ? c.gold : c.muted) }
                        Button { p.prev() } label: { Image(systemName: "backward.end.fill").font(.system(size: 28)) }
                        Button { p.toggle() } label: {
                            Image(systemName: p.playing ? "pause.fill" : "play.fill").font(.system(size: 30)).foregroundStyle(c.onGold)
                                .frame(width: 78, height: 78).background(Circle().fill(c.goldGradient)).shadow(color: c.gold.opacity(0.5), radius: 16)
                        }
                        Button { p.next() } label: { Image(systemName: "forward.end.fill").font(.system(size: 28)) }
                        Button { p.cycleRepeat() } label: { Image(systemName: p.repeatMode == 2 ? "repeat.1" : "repeat").foregroundStyle(p.repeatMode > 0 ? c.gold : c.muted) }
                    }.foregroundStyle(c.text).environment(\.layoutDirection, .leftToRight)
                    HStack(spacing: 26) {
                        Button { p.skip(10) } label: { Image(systemName: "goforward.10") }
                        Button { p.setSpeed(nextSpeed(store.speed)) } label: { Text("×" + speedText(store.speed)).font(F.plex(15, .bold)) }
                        Button { showSleep = true } label: { Image(systemName: p.sleepOn ? "moon.zzz.fill" : "moon.zzz") }.foregroundStyle(p.sleepOn ? c.gold : c.muted)
                        Button { store.toggleFav(t.id) } label: { Image(systemName: store.favs.contains(t.id) ? "heart.fill" : "heart") }.foregroundStyle(store.favs.contains(t.id) ? c.danger : c.muted)
                        Button { showQueue = true } label: { Image(systemName: "list.bullet") }
                        Button { showAmb = true } label: { Image(systemName: "cloud.rain") }.foregroundStyle(amb.current.isEmpty ? c.muted : c.gold).accessibilityLabel("أصوات هادئة")
                        Button { p.skip(-10) } label: { Image(systemName: "gobackward.10") }
                    }.font(.system(size: 20)).foregroundStyle(c.muted).environment(\.layoutDirection, .leftToRight)
                    Spacer(minLength: 0)
                }.padding(.bottom, 20)
            }
        }
        .environment(\.pal, c).environment(\.layoutDirection, .rightToLeft)
        .confirmationDialog("مؤقت الإيقاف", isPresented: $showSleep) {
            ForEach([15, 30, 45, 60], id: \.self) { m in Button("بعد \(m.ar) دقيقة") { p.sleep(m) } }
            Button("نهاية التلاوة") { p.sleep(-1) }
            if p.sleepOn { Button("إيقاف المؤقت", role: .destructive) { p.sleep(0) } }
        }
        .sheet(isPresented: $showQueue) { QueueSheet().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showAmb) { AmbientSheet().presentationDetents([.medium]) }
    }
}

struct QueueSheet: View {
    @EnvironmentObject var p: AudioPlayer
    @Environment(\.pal) private var c
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(p.queue.enumerated()), id: \.offset) { i, t in
                    Button { p.playAt(i) } label: {
                        HStack { Text(t.title).font(F.plex(14, i == p.index ? .bold : .regular)).foregroundStyle(i == p.index ? c.gold : c.text); Spacer(); if i == p.index { Equalizer(color: c.gold) } }
                    }
                    .swipeActions { if i != p.index { Button("إزالة", role: .destructive) { p.remove(at: i) } } }
                    .listRowBackground(c.surface)
                }
            }
            .scrollContentBackground(.hidden).background(c.bg2)
            .navigationTitle("قائمة التشغيل").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("مسح القادم") { p.clearUpcoming() } }
        }.environment(\.layoutDirection, .rightToLeft)
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
