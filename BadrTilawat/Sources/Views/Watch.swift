import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer

/// Saved videos (to watch without internet): one copy per recitation, at the height the person chose.
enum VideoFiles {
    static var dir: URL { let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("videos"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }
    static func file(_ id: String, _ h: Int) -> URL { dir.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_") + "-\(h).mp4") }
    /// the height of the saved copy, if there is one
    static func savedH(_ id: String) -> Int? {
        let pre = id.replacingOccurrences(of: "/", with: "_") + "-"
        let f = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.first { $0.hasPrefix(pre) && $0.hasSuffix(".mp4") }
        return f.flatMap { Int($0.dropFirst(pre.count).dropLast(4)) }
    }
    static func local(_ id: String) -> URL? { savedH(id).map { file(id, $0) } }
    static func delete(_ id: String) { if let h = savedH(id) { try? FileManager.default.removeItem(at: file(id, h)) } }
    static var ids: [String] { (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.compactMap { n in n.range(of: "-", options: .backwards).map { String(n[..<$0.lowerBound]) } } ?? [] }
}

/// Downloads a video copy with progress (URLSession download task).
@MainActor
final class VideoDownloads: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = VideoDownloads()
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var savedTick = 0
    private var jobs: [Int: (id: String, h: Int)] = [:]
    private lazy var session: URLSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    func start(_ t: Track, _ h: Int) {
        guard let v = t.video, let q = v.q.first(where: { $0.h == h }) ?? v.q.last, let u = Repo.media(q.url), progress[t.id] == nil else { return }
        let task = session.downloadTask(with: u)
        jobs[task.taskIdentifier] = (t.id, q.h); progress[t.id] = 0
        task.resume()
    }
    nonisolated func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
        let id = downloadTask.taskIdentifier
        MainActor.assumeIsolated { if let j = jobs[id], e > 0 { progress[j.id] = Double(w) / Double(e) } }
    }
    nonisolated func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
        let id = downloadTask.taskIdentifier
        let ok = (downloadTask.response as? HTTPURLResponse)?.statusCode == 200
        // the temporary file goes away when this returns: move it now
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let moved = ok && (try? FileManager.default.moveItem(at: loc, to: tmp)) != nil
        MainActor.assumeIsolated {
            guard let j = jobs[id] else { return }
            if moved { VideoFiles.delete(j.id); try? FileManager.default.moveItem(at: tmp, to: VideoFiles.file(j.id, j.h)); UIState.shared?.say("حُفظت — يمكنك مشاهدتها بدون إنترنت") }
            else { UIState.shared?.say("تعذّر حفظ الملف. تأكد من المساحة والاتصال.") }
            jobs[id] = nil; progress[j.id] = nil; savedTick += 1
        }
    }
    nonisolated func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) {
        guard e != nil else { return }
        let id = task.taskIdentifier
        MainActor.assumeIsolated { if let j = jobs[id] { jobs[id] = nil; progress[j.id] = nil; UIState.shared?.say("تعذّر حفظ الملف. تأكد من المساحة والاتصال.") } }
    }
}

/// The video engine: AVPlayer + a layer + picture-in-picture. Leaving the app or locking the phone keeps the sound going
/// (the picture is taken off the player while in the background), and the floating window opens by itself when the app
/// is left while the video plays.
@MainActor
final class VideoEngine: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    static let shared = VideoEngine()
    let player = AVPlayer()
    let layer = AVPlayerLayer()
    private(set) var pip: AVPictureInPictureController?
    @Published private(set) var track: Track?
    @Published private(set) var h = 0
    @Published private(set) var playing = false
    @Published private(set) var buffering = false
    @Published private(set) var failed = false
    @Published var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var pipOn = false
    @Published private(set) var size = CGSize(width: 16, height: 9)
    var onEnd: (() -> Void)?
    private var timeObs: Any?
    private var obs: [NSObjectProtocol] = []
    private var kvo: [NSKeyValueObservation] = []
    private var lastSave = Date.distantPast

    private override init() {
        super.init()
        layer.player = player
        layer.videoGravity = .resizeAspect
        player.allowsExternalPlayback = true
        timeObs = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
        kvo.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let st = p.timeControlStatus
            Task { @MainActor in self?.playing = st != .paused; self?.buffering = st == .waitingToPlayAtSpecifiedRate; self?.nowPlaying() }
        })
        let nc = NotificationCenter.default
        obs.append(nc.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { guard let self, (n.object as? AVPlayerItem) === self.player.currentItem else { return }; if let t = self.track { Store.shared.savePosition(t.id, 0, 0) }; self.onEnd?() }
        })
        // background: the sound goes on, the picture comes off (unless it is in the floating window)
        obs.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self, !self.pipOn else { return }; self.layer.player = nil }
        })
        obs.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layer.player = self?.player }
        })
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pip = AVPictureInPictureController(playerLayer: layer)
            pip?.delegate = self
            pip?.canStartPictureInPictureAutomaticallyFromInline = true
        }
    }

    /// The copy to play: a saved one (no data used), then the person's choice, then 720p.
    static func pickQ(_ t: Track) -> Int {
        let hs = t.video?.q.map(\.h) ?? []
        if let s = VideoFiles.savedH(t.id), hs.contains(s) { return s }
        let pref = Int(Store.shared.str("videoQ", "0")) ?? 0
        let want = pref > 0 ? pref : 720
        return hs.first { $0 <= want } ?? hs.last ?? 0
    }

    func open(_ t: Track) {
        guard t.isVideo else { return }
        if track?.id == t.id { return }
        AudioPlayer.shared.pause(); AyahPlayer.shared.stop()
        track = t; failed = false
        duration = Double(t.durationSec)
        if let v = t.video, v.w > 0, v.h > 0 { size = CGSize(width: v.w, height: v.h) }
        let start = Store.shared.position(t.id)
        load(Self.pickQ(t), at: start, play: false)
        Store.shared.addHistory(t.id)
        artwork(t)
    }
    func load(_ q: Int, at: Double, play: Bool) {
        guard let t = track, let v = t.video else { return }
        h = q
        let url: URL? = VideoFiles.savedH(t.id) == q ? VideoFiles.local(t.id) : Repo.media((v.q.first { $0.h == q } ?? v.q[0]).url)
        guard let url else { failed = true; return }
        let item = AVPlayerItem(url: url)
        kvo.removeAll { $0 === itemKVO }
        itemKVO = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            let bad = it.status == .failed
            let ns = it.presentationSize
            Task { @MainActor in if bad { self?.failed = true }; if ns.width > 0 { self?.size = ns } }
        }
        if let k = itemKVO { kvo.append(k) }
        player.replaceCurrentItem(with: item)
        if at > 0 { player.seek(to: CMTime(seconds: at, preferredTimescale: 600)) }
        position = at
        if play { start() }
    }
    private var itemKVO: NSKeyValueObservation?
    func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        AudioPlayer.shared.pause(); AyahPlayer.shared.stop()
        player.play(); player.rate = Store.shared.speed
        remote()
        Repo.shared.event("play", ["id": track?.id ?? ""])
    }
    func toggle() { if playing { player.pause() } else { start() } }
    func pause() { player.pause() }
    func seek(_ s: Double) { let x = max(0, min(s, duration > 0 ? duration : s)); player.seek(to: CMTime(seconds: x, preferredTimescale: 600)); position = x; nowPlaying() }
    func skip(_ d: Double) { seek(position + d) }
    func setQ(_ q: Int) { let at = position, was = playing; load(q, at: at, play: was) }
    func close() {
        if let t = track { Store.shared.savePosition(t.id, position, duration) }
        player.pause(); player.replaceCurrentItem(with: nil); track = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }
    func startPip() { if let p = pip, p.isPictureInPicturePossible { p.startPictureInPicture() } }

    private func tick(_ s: Double) {
        guard let t = track else { return }
        if s.isFinite { position = s }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        if playing, Date().timeIntervalSince(lastSave) > 5 { lastSave = Date(); Store.shared.savePosition(t.id, position, duration) }
    }

    // MARK: picture-in-picture
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) { Task { @MainActor in self.pipOn = true } }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in
            self.pipOn = false
            // closed from the floating window while the app is in the background: the video stops (as on Android)
            if UIApplication.shared.applicationState == .background { self.player.pause(); self.layer.player = nil }
        }
    }
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler done: @escaping (Bool) -> Void) {
        Task { @MainActor in
            if let t = self.track, UIState.shared?.path.last != .watch(t.id) { UIState.shared?.path.append(.watch(t.id)) }
            done(true)
        }
    }

    // MARK: lock screen
    private var remoteOn = false
    private func remote() {
        let rc = MPRemoteCommandCenter.shared()
        // the recitations player owns these when it plays; the video takes them over while it plays
        rc.playCommand.removeTarget(nil); rc.pauseCommand.removeTarget(nil); rc.togglePlayPauseCommand.removeTarget(nil)
        rc.skipForwardCommand.removeTarget(nil); rc.skipBackwardCommand.removeTarget(nil); rc.changePlaybackPositionCommand.removeTarget(nil)
        rc.playCommand.addTarget { [weak self] _ in self?.start(); return .success }
        rc.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        rc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        rc.skipForwardCommand.preferredIntervals = [10]; rc.skipBackwardCommand.preferredIntervals = [10]
        rc.skipForwardCommand.isEnabled = true; rc.skipBackwardCommand.isEnabled = true
        rc.skipForwardCommand.addTarget { [weak self] _ in self?.skip(10); return .success }
        rc.skipBackwardCommand.addTarget { [weak self] _ in self?.skip(-10); return .success }
        rc.changePlaybackPositionCommand.addTarget { [weak self] e in if let e = e as? MPChangePlaybackPositionCommandEvent { self?.seek(e.positionTime) }; return .success }
        remoteOn = true
        AudioPlayer.shared.yieldRemote = true
        nowPlaying()
    }
    private var art: MPMediaItemArtwork?
    private func nowPlaying() {
        guard let t = track, remoteOn else { return }
        var i: [String: Any] = [MPMediaItemPropertyTitle: t.title, MPMediaItemPropertyArtist: Repo.shared.reciter(t.reciterId)?.name ?? "",
                                MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
                                MPNowPlayingInfoPropertyPlaybackRate: playing ? Double(Store.shared.speed) : 0, MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue]
        if let art { i[MPMediaItemPropertyArtwork] = art }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = i
    }
    private func artwork(_ t: Track) {
        art = nil
        guard let u = Repo.media(t.cover) else { return }
        Task { if let (d, _) = try? await URLSession.shared.data(from: u), let img = UIImage(data: d) { self.art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }; self.nowPlaying() } }
    }
}

/// The layer in SwiftUI.
private struct VideoSurface: UIViewRepresentable {
    let layer: AVPlayerLayer
    final class Host: UIView { var pl: AVPlayerLayer?; override func layoutSubviews() { super.layoutSubviews(); pl?.frame = bounds } }
    func makeUIView(context: Context) -> Host { let v = Host(); v.backgroundColor = .black; v.layer.addSublayer(layer); v.pl = layer; return v }
    func updateUIView(_ v: Host, context: Context) { if layer.superlayer !== v.layer { v.layer.addSublayer(layer); v.pl = layer }; v.setNeedsLayout() }
}

private func qLabel(_ h: Int) -> String { h > 0 ? "\(h)p" : "صوت فقط" }
private func qName(_ h: Int) -> String { h >= 1080 ? "Full HD" : h >= 720 ? "HD" : "" }
func sizeTxt(_ b: Int64) -> String { b <= 0 ? "" : b >= 1_000_000_000 ? String(format: "%.1f غيغابايت", Double(b) / 1e9) : "\(max(1, Int(b / 1_048_576)).ar) ميجابايت" }
private func fmtT(_ s: Double) -> String { let x = Int(max(0, s.isFinite ? s : 0)); return x >= 3600 ? String(format: "%d:%02d:%02d", x / 3600, x % 3600 / 60, x % 60) : String(format: "%d:%02d", x / 60, x % 60) }

/// «تلاوة مرئية»: the video page.
struct WatchView: View {
    let id: String
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var store: Store
    @ObservedObject private var v = VideoEngine.shared
    @ObservedObject private var dl = VideoDownloads.shared
    @Environment(\.pal) private var c
    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var full = false
    @State private var sheet: String?
    @State private var auto = Store.shared.bool("videoAuto", true)
    @State private var flash: (fwd: Bool, at: Date)?

    private var t: Track? { repo.track(id).flatMap { $0.isVideo ? $0 : nil } }
    private var next: [Track] {
        guard let t else { return [] }
        let l = (repo.data?.sortedTracks ?? []).filter { $0.isVideo && $0.id != t.id }
        return l.filter { $0.reciterId == t.reciterId } + l.filter { $0.reciterId != t.reciterId }
    }

    var body: some View {
        Group {
            if let t {
                if full { stage(t).ignoresSafeArea().statusBarHidden() }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            stage(t).aspectRatio(max(0.42, min(2.38, v.size.width / max(1, v.size.height))), contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.line))
                            info(t)
                            if !next.isEmpty {
                                HStack { Text("التالي").font(F.plex(16, .bold)).foregroundStyle(c.text); Spacer()
                                    Toggle(isOn: $auto) { Text("تشغيل تلقائي").font(F.plex(13)).foregroundStyle(c.muted) }.toggleStyle(.switch).tint(c.gold).fixedSize()
                                        .onChange(of: auto) { Store.shared.set("videoAuto", $0) } }
                                ForEach(next.prefix(20)) { n in VideoRow(t: n) { ui.path.append(.watch(n.id)) } }
                            }
                        }.padding(16).padding(.bottom, 120)
                    }
                }
            } else { Empty(text: "هذه التلاوة غير متاحة الآن", icon: "film") }
        }
        .navigationTitle(full ? "" : "تلاوة مرئية")
        .onChange(of: full) { ui.videoFull = $0 }.onDisappear { ui.videoFull = false }
        .onAppear { if let t { v.open(t); v.onEnd = { if auto, let n = next.first { ui.path.append(.watch(n.id)) } } }; bump() }
        .onChange(of: id) { _ in if let t { v.open(t) } }
        .onDisappear { if !v.pipOn && UIApplication.shared.applicationState == .active && !(ui.path.last.map { if case .watch = $0 { return true } else { return false } } ?? false) { v.close() } }
        .bzSheet(item: Binding(get: { sheet.map { SheetID(id: $0) } }, set: { sheet = $0?.id })) { s in
            if let t { if s.id == "q" { qualitySheet(t) } else { downloadSheet(t) } }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
    private struct SheetID: Identifiable { let id: String }

    private func bump() { controls = true; hideTask?.cancel(); hideTask = Task { try? await Task.sleep(nanoseconds: 3_500_000_000); if !Task.isCancelled, v.playing { withAnimation { controls = false } } } }

    @ViewBuilder private func stage(_ t: Track) -> some View {
        ZStack {
            Color.black
            VideoSurface(layer: v.layer)
            if v.position < 0.2 && !v.playing, let u = t.video?.poster, !u.isEmpty { RemoteImage(raw: u, mode: .fit).allowsHitTesting(false) }
            // double tap: right side goes back, left side goes forward (the bar runs right to left)
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture(count: 2) { v.skip(10); flash = (true, Date()); bump() }.onTapGesture { withAnimation { controls.toggle() }; if controls { bump() } }
                Color.clear.contentShape(Rectangle()).onTapGesture(count: 2) { v.skip(-10); flash = (false, Date()); bump() }.onTapGesture { withAnimation { controls.toggle() }; if controls { bump() } }
            }.environment(\.layoutDirection, .leftToRight)
            if v.buffering { ProgressView().tint(.white).scaleEffect(1.3) }
            if v.failed { Text("تعذّر تشغيل الفيديو. جرّب جودة أقل.").font(F.plex(14)).foregroundStyle(.white).padding(10).background(Capsule().fill(.black.opacity(0.6))) }
            if controls { overlay(t).transition(.opacity) }
        }
    }

    private func overlay(_ t: Track) -> some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.5), .clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
            // left: forward 10 (arrow turning left) · play · right: back 10 (arrow turning right) — as on the site
            HStack(spacing: 34) {
                round("gobackward.10", 26) { v.skip(10); bump() }.accessibilityLabel("تقديم ١٠ ثوانٍ")
                round(v.playing ? "pause.fill" : "play.fill", 34, big: true) { v.toggle(); bump() }.accessibilityLabel(v.playing ? "إيقاف مؤقت" : "تشغيل")
                round("goforward.10", 26) { v.skip(-10); bump() }.accessibilityLabel("رجوع ١٠ ثوانٍ")
            }.environment(\.layoutDirection, .leftToRight)
            VStack(spacing: 6) {
                Spacer()
                SeekLine(pos: v.position, dur: v.duration) { v.seek($0); bump() }
                HStack(spacing: 14) {
                    Text("\(fmtT(v.position)) / \(fmtT(v.duration))").font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.white)
                    Spacer()
                    Button { sheet = "q" } label: { Text(qLabel(v.h)).font(.system(size: 12, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().stroke(.white.opacity(0.7))) }
                    if v.pip != nil { Button { v.startPip() } label: { Ico(name: "pip.enter", size: 20).foregroundStyle(.white) } }
                    Button { withAnimation { full.toggle() }; rotate(full) } label: { Ico(name: full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", size: 20).foregroundStyle(.white) }
                        .accessibilityLabel(full ? "الخروج من ملء الشاشة" : "ملء الشاشة")
                }.padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
    }
    private func round(_ icon: String, _ s: CGFloat, big: Bool = false, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            // the 10-second arrows are mirrored: in right-to-left order «back» turns to the right
            Ico(name: icon, size: s * 1.2, color: big ? c.onGold : .white)
                .scaleEffect(x: big ? 1 : -1, y: 1)
                .frame(width: big ? 72 : 54, height: big ? 72 : 54).background(Circle().fill(big ? c.gold : .black.opacity(0.35)))
        }.buttonStyle(Press())
    }
    private func rotate(_ land: Bool) {
        guard let s = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        AppDelegate.orientation = land ? .landscape : .portrait
        if #available(iOS 16.0, *) { s.requestGeometryUpdate(.iOS(interfaceOrientations: land ? .landscapeRight : .portrait)) { _ in } }
        s.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private func info(_ t: Track) -> some View {
        let r = repo.reciter(t.reciterId)
        let fav = store.favs.contains(t.id)
        let saved = dl.savedTick >= 0 ? VideoFiles.savedH(t.id) : nil
        return VStack(alignment: .leading, spacing: 10) {
            Text(t.title).font(F.amiri(22)).foregroundStyle(c.text)
            if let r { Button { ui.path.append(.reciter(r.id)) } label: { HStack(spacing: 8) { RemoteImage(raw: r.image).frame(width: 30, height: 30).clipShape(Circle()); Text(r.name).font(F.plex(14, .medium)).foregroundStyle(c.gold) } }.buttonStyle(Press()) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(fav ? "heart.fill" : "heart", fav ? "في المفضلة" : "المفضلة") { store.toggleFav(t.id) }
                    if let p = dl.progress[t.id] { chip("arrow.down.circle", "جارٍ الحفظ \(Int(p * 100).ar)٪") {} }
                    else { chip(saved != nil ? "checkmark.circle" : "arrow.down.circle", saved != nil ? "✓ محفوظة" : "تحميل") { sheet = "d" } }
                    if repo.data?.site.sec("clip") != false { chip("scissors", "اصنع مقطعًا للمشاركة") { ui.path.append(.clip(t.id)) } }
                    ShareLink(item: URL(string: Repo.site + "watch/" + t.id) ?? URL(string: Repo.site)!) { HStack(spacing: 6) { Ico(name: "square.and.arrow.up", size: 20); Text("مشاركة") }.font(F.plex(13, .medium)).foregroundStyle(c.text).padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().fill(c.surface2)) }
                }
            }
            if !t.description.isEmpty { Text(t.description).font(F.plex(14)).foregroundStyle(c.muted) }
        }
    }
    private func chip(_ icon: String, _ s: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { HStack(spacing: 6) { Ico(name: icon, size: 18, color: c.gold); Text(s) }.font(F.plex(13, .medium)).foregroundStyle(c.text).padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().fill(c.surface2)) }.buttonStyle(Press())
    }

    private func qualitySheet(_ t: Track) -> some View {
        let qs = t.video?.q ?? []
        let pref = Int(store.str("videoQ", "0")) ?? 0
        return NavigationStack {
            List {
                Button { store.set("videoQ", "0"); v.setQ(VideoEngine.pickQ(t)); sheet = nil } label: { row("تلقائي", "يختار المناسب لاتصالك", on: pref == 0) }.listRowBackground(c.surface)
                ForEach(qs, id: \.h) { q in
                    Button { store.set("videoQ", "\(q.h)"); v.setQ(q.h); sheet = nil } label: { row("\(qLabel(q.h)) \(qName(q.h))", sizeTxt(q.size), on: v.h == q.h && pref != 0) }
                }.listRowBackground(c.surface)
            }.bzList(c).navigationTitle("جودة الفيديو").navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.medium]).environment(\.layoutDirection, .rightToLeft)
    }
    private func downloadSheet(_ t: Track) -> some View {
        let qs = t.video?.q ?? []
        let saved = VideoFiles.savedH(t.id)
        let audioSaved = OfflineFiles.local(t.id) != nil
        return NavigationStack {
            List {
                Section("حفظ للمشاهدة دون إنترنت") {
                    ForEach(qs, id: \.h) { q in
                        Button { if saved == q.h { ui.say("محفوظة بهذه الجودة بالفعل") } else { dl.start(t, q.h); ui.say("بدأ تنزيل الملف") }; sheet = nil } label: { row("\(qLabel(q.h)) \(qName(q.h))", sizeTxt(q.size), on: saved == q.h) }
                    }
                }.listRowBackground(c.surface)
                if !t.audio.isEmpty {
                    Section("حفظ الصوت للاستماع دون إنترنت") {
                        Button {
                            sheet = nil
                            if audioSaved { ui.say("الصوت محفوظ بالفعل"); return }
                            ui.say("جارٍ حفظ الصوت…")
                            Task { let ok = await OfflineFiles.save(t); ui.say(ok ? "حُفظ الصوت — يمكنك سماعه بدون إنترنت" : "تعذّر حفظ الملف. تأكد من المساحة والاتصال.") }
                        } label: { row("صوت فقط", sizeTxt(t.video?.audioSize ?? 0), on: audioSaved) }
                    }.listRowBackground(c.surface)
                }
                if saved != nil { Section { Button(role: .destructive) { VideoFiles.delete(t.id); dl.objectWillChange.send(); ui.say("حُذفت من الجهاز"); sheet = nil } label: { Text("حذف النسخة المحفوظة").font(F.plex(15)) } }.listRowBackground(c.surface) }
            }.bzList(c).navigationTitle("تحميل التلاوة").navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.medium, .large]).environment(\.layoutDirection, .rightToLeft)
    }
    private func row(_ a: String, _ b: String, on: Bool) -> some View {
        HStack { VStack(alignment: .leading, spacing: 2) { Text(a).font(F.plex(15, .medium)).foregroundStyle(c.text); if !b.isEmpty { Text(b).font(F.plex(12)).foregroundStyle(c.muted) } }; Spacer(); if on { Ico(name: "checkmark", size: 20).foregroundStyle(c.gold) } }
    }
}

/// The seek line of the video: it runs from the right (start) to the left (end).
private struct SeekLine: View {
    let pos: Double, dur: Double; let seek: (Double) -> Void
    @State private var drag: Double?
    @Environment(\.pal) private var c
    var body: some View {
        GeometryReader { g in
            let f = dur > 0 ? min(1, max(0, (drag ?? pos) / dur)) : 0
            ZStack(alignment: .trailing) {
                Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                Capsule().fill(c.gold).frame(width: g.size.width * f, height: 4)
                Circle().fill(c.gold).frame(width: 14, height: 14).offset(x: -(g.size.width * f) + 7)
            }.frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { e in drag = dur * min(1, max(0, (g.size.width - e.location.x) / g.size.width)) }
                .onEnded { _ in if let d = drag { seek(d) }; drag = nil })
        }.frame(height: 24).padding(.horizontal, 14).environment(\.layoutDirection, .leftToRight)
    }
}

/// A video recitation in a list: cover frame with its length, title and reciter.
struct VideoRow: View {
    let t: Track; let tap: () -> Void
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(raw: t.cover).frame(width: 128, height: 72).clipShape(RoundedRectangle(cornerRadius: 12))
                    if !t.durationText.isEmpty { Text(t.durationText).font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(.black.opacity(0.7))).padding(6) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.title).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(2).multilineTextAlignment(.leading)
                    Text(repo.reciter(t.reciterId)?.name ?? "").font(F.plex(12)).foregroundStyle(c.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }.buttonStyle(Press())
    }
}
