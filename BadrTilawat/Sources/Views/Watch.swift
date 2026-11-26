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
            if moved { VideoFiles.delete(j.id); try? FileManager.default.moveItem(at: tmp, to: VideoFiles.file(j.id, j.h)); UIState.shared?.say(tr("حُفظت — يمكنك مشاهدتها بدون إنترنت")) }
            else { UIState.shared?.say(tr("تعذّر حفظ الملف. تأكد من المساحة والاتصال.")) }
            jobs[id] = nil; progress[j.id] = nil; savedTick += 1
        }
    }
    nonisolated func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) {
        guard e != nil else { return }
        let id = task.taskIdentifier
        MainActor.assumeIsolated { if let j = jobs[id] { jobs[id] = nil; progress[j.id] = nil; UIState.shared?.say(tr("تعذّر حفظ الملف. تأكد من المساحة والاتصال.")) } }
    }
}

/// The video engine: AVPlayer + a layer + picture-in-picture. Leaving the app or locking the phone keeps the sound going
/// (the picture is taken off the player while in the background), and the floating window opens by itself when the app
/// is left while the video plays.
@MainActor
final class VideoClock: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
}

/// The time bar and the time under the video: the only parts that change every moment.
private struct VideoTimeBar: View {
    @ObservedObject var clock: VideoClock
    let onSeek: (Double) -> Void
    var body: some View { SeekLine(pos: clock.position, dur: clock.duration, seek: onSeek) }
}
private struct VideoTimeText: View {
    @ObservedObject var clock: VideoClock
    var body: some View { Text("\(fmtT(clock.position)) / \(fmtT(clock.duration))").font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.white) }
}

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
    /// the time: only the time bar watches it (the whole video page redrew four times a second)
    let clock = VideoClock()
    var position: Double = 0 { didSet { if clock.position != position { clock.position = position } } }
    private(set) var duration: Double = 0 { didSet { if clock.duration != duration { clock.duration = duration } } }
    @Published private(set) var pipOn = false
    /// the video has begun (its poster is shown until then)
    @Published private(set) var started = false
    @Published private(set) var size = CGSize(width: 16, height: 9)
    var onEnd: (() -> Void)?
    private var timeObs: Any?
    private var obs: [NSObjectProtocol] = []
    private var kvo: [NSKeyValueObservation] = []
    private var lastSave = Date.distantPast
    private var wasPlaying = false

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
            Task { @MainActor in
                self?.playing = st != .paused; self?.buffering = st == .waitingToPlayAtSpecifiedRate; self?.nowPlaying()
                // started at once (see quick()); once it plays, later stalls wait for enough again, as usual
                if st == .playing { p.automaticallyWaitsToMinimizeStalling = true }
            }
        })
        let nc = NotificationCenter.default
        obs.append(nc.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { guard let self, (n.object as? AVPlayerItem) === self.player.currentItem else { return }; self.ended() }
        })
        // the end signal sometimes never comes for an online video: standing still at its end for 2 seconds counts as the end
        endWatch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.watchEnd() }
        }
        // background: the sound goes on, the picture comes off (unless it is in the floating window)
        obs.append(nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wasPlaying = self?.player.timeControlStatus != .paused }
        })
        obs.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            // the floating window may still be opening at this moment: take the picture off only once it is clear
            // that there is none (taking it off too early is what made the window vanish and the sound stop)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                MainActor.assumeIsolated {
                    guard let self, UIApplication.shared.applicationState == .background else { return }
                    // a playing video goes to the floating window by itself: its picture must stay (taking it off left a grey window)
                    if self.pipOn || self.pip?.isPictureInPictureActive == true || (self.pageVisible && self.wasPlaying && self.pip?.isPictureInPicturePossible == true) { return }
                    self.layer.player = nil
                    if self.wasPlaying && self.track != nil { self.player.play() }      // the sound goes on in the background
                }
            }
        })
        obs.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.layer.player = self?.player
                // its page takes the picture back (it could come back black)
                (self?.layer.superlayer?.delegate as? UIView)?.setNeedsLayout()
            }
        })
        // back in the app: the floating window returns to the video page by itself (as YouTube does)
        obs.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.pip, p.isPictureInPictureActive, self.pageVisible else { return }
                p.stopPictureInPicture()
            }
        })
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pip = AVPictureInPictureController(playerLayer: layer)
            pip?.delegate = self
            pip?.canStartPictureInPictureAutomaticallyFromInline = false
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

    private var endWatch: Timer?
    private var stuck: (at: Double, since: Date)?, endedID: String?
    private func watchEnd() {
        guard let t = track, wantPlay, seekTarget == nil, endedID != t.id, let item = player.currentItem else { stuck = nil; return }
        let d = item.duration.seconds, len = d.isFinite && d > 0 ? d : duration
        let p = player.currentTime().seconds
        guard len > 0, p.isFinite, p >= len - 1.5 else { stuck = nil; return }
        if let s = stuck, abs(s.at - p) < 0.05 { if Date().timeIntervalSince(s.since) >= 2 { stuck = nil; ended() } } else { stuck = (p, Date()) }
    }
    /// the next video (as listed under «التالي»: the same sheikh first)
    static func upNext(_ t: Track) -> [Track] {
        let l = (Repo.shared.data?.sortedTracks ?? []).filter { $0.isVideo && $0.id != t.id }
        return l.filter { $0.reciterId == t.reciterId } + l.filter { $0.reciterId != t.reciterId }
    }
    /// a video ended: with «تشغيل تلقائي» on the next one starts by itself — on its page, in the floating window or in
    /// the background alike (it used to change the page only, and the next video stood paused)
    private func ended() {
        guard let t = track, endedID != t.id else { return }
        endedID = t.id
        Store.shared.savePosition(t.id, 0, 0)
        guard Store.shared.bool("videoAuto", true), let n = Self.upNext(t).first else { wantPlay = false; player.pause(); return }
        open(n, play: true)
        if pageVisible, let ui = UIState.shared, case .watch = ui.path.last { ui.openWatch(n.id) }
    }
    func open(_ t: Track, play: Bool = false) {
        guard t.isVideo else { return }
        if track?.id == t.id { return }
        endedID = nil; stuck = nil
        AudioPlayer.shared.pause(); AyahPlayer.shared.stop()
        track = t; failed = false; started = false; wantPlay = false
        duration = Double(t.durationSec)
        if let v = t.video, v.w > 0, v.h > 0 { size = CGSize(width: v.w, height: v.h) }
        let start = Store.shared.position(t.id)
        load(Self.pickQ(t), at: start, play: play)
        if play { Repo.shared.event("play", ["id": t.id]); nowPlaying() }
        Store.shared.addHistory(t.id)
        artwork(t)
    }
    func load(_ q: Int, at: Double, play: Bool, retry: Bool = false) {
        guard let t = track, let v = t.video else { return }
        h = q; failed = false; stale = false
        if !retry { retries = 0 }
        if play { wantPlay = true }
        let url: URL? = VideoFiles.savedH(t.id) == q ? VideoFiles.local(t.id) : Repo.media((v.q.first { $0.h == q } ?? v.q[0]).url)
        guard let url else { failed = true; return }
        let item = AVPlayerItem(url: url)
        // paused, it reads only a little ahead: it must not take the connection from the recitation playing as sound (a jump in it hung)
        item.preferredForwardBufferDuration = play ? 0 : 3
        kvo.removeAll { $0 === itemKVO }
        itemKVO = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            let bad = it.status == .failed
            let ns = it.presentationSize
            Task { @MainActor in if bad { self?.recover() }; if ns.width > 0 { self?.size = ns } }
        }
        if let k = itemKVO { kvo.append(k) }
        player.replaceCurrentItem(with: item)
        if at > 0 { player.seek(to: CMTime(seconds: at, preferredTimescale: 600)) }
        position = at
        if play {
            wantPlay = true
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback); try? AVAudioSession.sharedInstance().setActive(true)
            AudioPlayer.shared.pause(); AyahPlayer.shared.stop()
            player.currentItem?.preferredForwardBufferDuration = 0; quick(); remote()
        }
    }
    /// the first second of a video from the internet starts as soon as a little of it is here (the files start with their
    /// index, the connection is good): no waiting for the player's own estimate that the whole of it will flow
    private func quick() {
        player.automaticallyWaitsToMinimizeStalling = false
        player.playImmediately(atRate: Store.shared.speed)
    }
    private var itemKVO: NSKeyValueObservation?
    /// a copy that broke (often the connection, e.g. while the same video is being saved): tried again quietly at the same
    /// second; the message shows only when the person asked to play and it still fails
    private var retries = 0, wantPlay = false, stale = false
    private func recover() {
        guard let t = track else { return }
        let at = position, play = wantPlay || playing
        if retries < 2 {
            retries += 1
            Task { try? await Task.sleep(nanoseconds: 1_500_000_000); if self.track?.id == t.id { self.load(self.h, at: at, play: play, retry: true) } }
        } else if play { failed = true } else { stale = true }
    }
    func start() {
        // a paused copy that broke meanwhile: a fresh one, from the same second
        if stale || player.currentItem == nil || player.currentItem?.status == .failed { stale = false; retries = 0; wantPlay = true; load(h, at: position, play: true); return }
        wantPlay = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        AudioPlayer.shared.pause(); AyahPlayer.shared.stop()
        player.currentItem?.preferredForwardBufferDuration = 0
        quick()
        remote()
        Repo.shared.event("play", ["id": track?.id ?? ""])
    }
    func toggle() { if playing { pause() } else { start() } }
    func pause() { wantPlay = false; player.pause(); player.currentItem?.preferredForwardBufferDuration = 3 }
    /// exact seeks: the default one jumps to the nearest key frame, which can be several seconds away —
    /// «forward 10» then landed only 6 seconds on, or even behind where it started
    /// the page is left: a playing video continues as sound in the audio player at the same moment
    func handOffToAudio() {
        guard let t = track else { close(); return }
        let at = position, was = playing
        close()
        if was && !t.audio.isEmpty { AudioPlayer.shared.play(t, startAt: at) }
    }
    func seek(_ s: Double) {
        let x = max(0, min(s, duration > 0 ? duration : s))
        seekTarget = x; position = x
        player.seek(to: CMTime(seconds: x, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in if self?.seekTarget == x { self?.seekTarget = nil } }
        }
        nowPlaying()
    }
    /// where a seek is going: repeated taps add up from there, and the clock does not jump back while it runs
    private var seekTarget: Double?
    func skip(_ d: Double) { seek((seekTarget ?? position) + d) }
    func setQ(_ q: Int) { let at = position, was = playing; load(q, at: at, play: was) }
    func close() {
        if let t = track { Store.shared.savePosition(t.id, position, duration) }
        player.pause(); player.replaceCurrentItem(with: nil); track = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }
    /// the floating window opens by itself only from the video page itself (from anywhere else its picture is not
    /// on screen, and the window stayed grey with a spinner)
    /// counted: the next video's page appears before the last one's goes
    private var pages = 0
    var pageVisible: Bool { pages > 0 }
    func setVisible(_ on: Bool) { pages = max(0, pages + (on ? 1 : -1)); pip?.canStartPictureInPictureAutomaticallyFromInline = pages > 0 }
    func startPip() { if let p = pip, p.isPictureInPicturePossible { p.startPictureInPicture() } }

    private func tick(_ s: Double) {
        guard let t = track else { return }
        if s.isFinite && seekTarget == nil { position = s; if s > 0.3 && !started { started = true } }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        if playing, Date().timeIntervalSince(lastSave) > 5 { lastSave = Date(); Store.shared.savePosition(t.id, position, duration) }
    }

    // MARK: picture-in-picture
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) { DispatchQueue.main.async { MainActor.assumeIsolated { self.pipOn = true } } }
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) { DispatchQueue.main.async { MainActor.assumeIsolated { self.pipOn = true; if self.layer.player == nil { self.layer.player = self.player } } } }
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async { MainActor.assumeIsolated {
            self.pipOn = false
            // no floating window after all: the sound goes on in the background without the picture
            if UIApplication.shared.applicationState == .background { self.layer.player = nil; if self.wasPlaying && self.track != nil { self.player.play() } }
        } }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in
            self.pipOn = false
            // closed from the floating window while the app is in the background: the video stops (as on Android)
            if UIApplication.shared.applicationState == .background { self.player.pause(); self.layer.player = nil }
        }
    }
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler done: @escaping (Bool) -> Void) {
        Task { @MainActor in
            // back from the floating window: its picture returns to the page; the page is opened only if it is not already open
            // (opening a second one put the same video layer in two places and crashed)
            if self.layer.player == nil { self.layer.player = self.player }
            if let t = self.track, let ui = UIState.shared, !ui.path.contains(.watch(t.id)) { ui.openWatch(t.id) }
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
        var i: [String: Any] = [MPMediaItemPropertyTitle: titleL(t), MPMediaItemPropertyArtist: Repo.shared.reciter(t.reciterId)?.shown ?? "",
                                MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
                                MPNowPlayingInfoPropertyPlaybackRate: playing ? Double(Store.shared.speed) : 0, MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue]
        if let art { i[MPMediaItemPropertyArtwork] = art }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = i
    }
    private func artwork(_ t: Track) {
        art = nil
        guard let u = Repo.media(t.cover) else { return }
        Task { if let (d, _) = try? await URLSession.shared.data(from: u), let img = UIImage(data: d) { self.art = makeArtwork(img); self.nowPlaying() } }
    }
}

/// The layer in SwiftUI.
private struct VideoSurface: UIViewRepresentable {
    let layer: AVPlayerLayer
    /// the one video layer is shared by every video page: whichever page comes on screen takes it back
    /// (back to an earlier page, or back into the app, showed a black picture with the sound playing)
    final class Host: UIView {
        var pl: AVPlayerLayer?
        func claim() { guard let pl, window != nil else { return }; if pl.superlayer !== layer { layer.addSublayer(pl) }; CATransaction.begin(); CATransaction.setDisableActions(true); pl.frame = bounds; CATransaction.commit() }
        override func layoutSubviews() { super.layoutSubviews(); claim() }
        override func didMoveToWindow() { super.didMoveToWindow(); claim() }
    }
    func makeUIView(context: Context) -> Host { let v = Host(); v.backgroundColor = .black; v.layer.addSublayer(layer); v.pl = layer; return v }
    func updateUIView(_ v: Host, context: Context) { v.pl = layer; v.claim(); v.setNeedsLayout() }
}

private func qLabel(_ h: Int) -> String { h > 0 ? "\(h)p" : tr("صوت فقط") }
private func qName(_ h: Int) -> String { h >= 1080 ? "Full HD" : h >= 720 ? "HD" : "" }
func sizeTxt(_ b: Int64) -> String { b <= 0 ? "" : b >= 1_000_000_000 ? String(format: tr("%.1f غيغابايت"), Double(b) / 1e9) : tr("{0} ميجابايت", max(1, Int(b / 1_048_576)).ar) }
private func fmtT(_ s: Double) -> String { let x = Int(max(0, s.isFinite ? s : 0)); return x >= 3600 ? String(format: "%d:%02d:%02d", x / 3600, x % 3600 / 60, x % 60) : String(format: "%d:%02d", x / 60, x % 60) }

/// «تلاوة مرئية»: the video page.
struct WatchView: View {
    let id: String
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @EnvironmentObject var store: Store
    @ObservedObject private var v = VideoEngine.shared
    @ObservedObject private var dl = VideoDownloads.shared
    @Environment(\.pal) private var c
    @State private var controls = true
    @State private var lastTap: (right: Bool, at: Date)?
    @State private var hideTask: Task<Void, Never>?
    @State private var full = false
    @State private var sheet: String?
    @State private var auto = Store.shared.bool("videoAuto", true)
    @State private var flash: (fwd: Bool, at: Date)?

    private var t: Track? { repo.track(id).flatMap { $0.isVideo ? $0 : nil } }
    private var next: [Track] {
        guard let t else { return [] }
        return VideoEngine.upNext(t)
    }

    var body: some View {
        Group {
            if let t {
                if full {
                    // full screen fills the screen edge to edge (no black bars); pinch in to see the whole picture, pinch out to fill again
                    stage(t).ignoresSafeArea().statusBarHidden().persistentSystemOverlays(.hidden)
                        .simultaneousGesture(MagnificationGesture().onEnded { m in v.layer.videoGravity = m < 1 ? .resizeAspect : .resizeAspectFill })
                }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            stage(t).aspectRatio(max(0.42, min(2.38, v.size.width / max(1, v.size.height))), contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.line))
                            info(t)
                            if !next.isEmpty {
                                HStack { Text(tr("التالي")).font(F.plex(16, .bold)).foregroundStyle(c.text); Spacer()
                                    Toggle(isOn: $auto) { Text(tr("تشغيل تلقائي")).font(F.plex(13)).foregroundStyle(c.muted) }.toggleStyle(.switch).tint(c.gold).fixedSize()
                                        .onChange(of: auto) { Store.shared.set("videoAuto", $0) } }
                                ForEach(next.prefix(20)) { n in VideoRow(t: n) { ui.openWatch(n.id) } }
                            }
                        }.padding(16).padding(.bottom, 120)
                    }
                }
            } else { Empty(text: tr("هذه التلاوة غير متاحة الآن"), icon: "film") }
        }
        .navigationTitle(full ? "" : tr("تلاوة مرئية"))
        .onChange(of: full) { f in ui.videoFull = f; v.layer.videoGravity = f ? .resizeAspectFill : .resizeAspect }
        .onDisappear {
            // turning the phone can make SwiftUI call this while the page stays (it is still the last one opened): full
            // screen is kept then — undoing it here left the app sideways with the page's normal layout
            if case .watch(let w)? = ui.path.last, w == id, ProcessInfo.processInfo.environment["BZ_OLDDISAPPEAR"] == nil { return }
            ui.videoFull = false; v.layer.videoGravity = .resizeAspect; if full { full = false; rotate(false) }
        }
        .onAppear { v.setVisible(true); if let t { v.open(t) }; bump()
            // the simulator's tests (BZ_WATCHFULL): the video turned to full screen, as a person would
            if RootView.shot != nil, ProcessInfo.processInfo.environment["BZ_WATCHFULL"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { if !full { withAnimation { full = true }; rotate(true) } }
            }
        }
        .onChange(of: id) { _ in if let t { v.open(t) } }
        // leaving the video (back, another tab) while it plays: the recitation goes on as sound, from the same moment,
        // in the mini player (as on the site); paused, it simply closes
        .onDisappear { v.setVisible(false); if !v.pipOn && UIApplication.shared.applicationState == .active && !(ui.path.last.map { if case .watch = $0 { return true } else { return false } } ?? false) { v.handOffToAudio() } }
        .bzSheet(item: Binding(get: { sheet.map { SheetID(id: $0) } }, set: { sheet = $0?.id })) { s in
            if let t { if s.id == "q" { qualitySheet(t) } else { downloadSheet(t) } }
        }
        .environment(\.layoutDirection, L.dir)
    }
    private struct SheetID: Identifiable { let id: String }

    private func tapped(_ right: Bool) {
        let now = Date()
        if let l = lastTap, l.right == right, now.timeIntervalSince(l.at) < 0.3 {
            lastTap = nil
            v.skip(right ? 10 : -10); flash = (right, now)
            controls = true; bump()
            return
        }
        lastTap = (right, now)
        withAnimation(.easeOut(duration: 0.15)) { controls.toggle() }
        if controls { bump() }
    }
    private func bump() { controls = true; hideTask?.cancel(); hideTask = Task { try? await Task.sleep(nanoseconds: 3_500_000_000); if !Task.isCancelled, v.playing { withAnimation { controls = false } } } }

    @ViewBuilder private func stage(_ t: Track) -> some View {
        ZStack {
            Color.black
            VideoSurface(layer: v.layer)
            if !v.started && !v.playing, let u = t.video?.poster, !u.isEmpty { RemoteImage(raw: u, mode: .fit).allowsHitTesting(false) }
            // double tap: left side goes back 10 seconds, right side forward (like every video player)
            // one tap shows / hides the controls at once; a second tap on the same side within a moment skips 10 s
            // (a separate double-tap gesture made every single tap wait to see whether a second one followed)
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { tapped(false) }
                Color.clear.contentShape(Rectangle()).onTapGesture { tapped(true) }
            }.environment(\.layoutDirection, .leftToRight)
            if v.buffering { ProgressView().tint(.white).scaleEffect(1.3) }
            if v.failed { VStack { Text(tr("تعذّر تشغيل الفيديو. جرّب جودة أقل.")).font(F.plex(13)).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(.black.opacity(0.7))).padding(.top, 12); Spacer() }.allowsHitTesting(false) }
            if controls { overlay(t).transition(.opacity) }
        }
    }

    private func overlay(_ t: Track) -> some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.5), .clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
            // left: back 10 · play · right: forward 10 (left to right, like the time bar)
            HStack(spacing: 34) {
                round("gobackward.10", 26) { v.skip(-10); bump() }.accessibilityLabel(tr("رجوع ١٠ ثوانٍ"))
                round(v.playing ? "pause.fill" : "play.fill", 34, big: true) { v.toggle(); bump() }.accessibilityLabel(v.playing ? tr("إيقاف مؤقت") : tr("تشغيل"))
                round("goforward.10", 26) { v.skip(10); bump() }.accessibilityLabel(tr("تقديم ١٠ ثوانٍ"))
            }.environment(\.layoutDirection, .leftToRight)
            VStack(spacing: 6) {
                Spacer()
                VideoTimeBar(clock: v.clock) { v.seek($0); bump() }
                HStack(spacing: 14) {
                    VideoTimeText(clock: v.clock)
                    Spacer()
                    Button { sheet = "q" } label: { Text(qLabel(v.h)).font(.system(size: 12, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().stroke(.white.opacity(0.7))) }
                    if v.pip != nil { Button { v.startPip() } label: { Ico(name: "pip.enter", size: 20).foregroundStyle(.white).frame(width: 44, height: 44).contentShape(Rectangle()) } }
                    Button { withAnimation { full.toggle() }; rotate(full) } label: { Ico(name: full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", size: 20).foregroundStyle(.white) .frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .accessibilityLabel(full ? tr("الخروج من ملء الشاشة") : tr("ملء الشاشة"))
                }.padding(.horizontal, 14).padding(.bottom, full ? 0 : 4).environment(\.layoutDirection, .leftToRight)
            }
            // full screen: the time bar and its buttons stay clear of the rounded corners, the notch and the home bar
            .padding(.leading, full ? edge.left + 8 : 0).padding(.trailing, full ? edge.right + 8 : 0).padding(.bottom, full ? max(edge.bottom, 12) + 6 : 4)
        }
    }
    /// the screen's safe margins (the video itself fills the whole screen)
    private var edge: UIEdgeInsets {
        let w = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        let e = w?.safeAreaInsets ?? .zero
        let landscape = (w?.bounds.width ?? 0) > (w?.bounds.height ?? 0)
        // in landscape the corners curve on both sides: the same margin on each
        return landscape ? UIEdgeInsets(top: e.top, left: max(e.left, e.right, 24), bottom: e.bottom, right: max(e.left, e.right, 24)) : e
    }
    private func round(_ icon: String, _ s: CGFloat, big: Bool = false, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Ico(name: icon, size: s * 1.2, color: big ? c.onGold : .white)
                .frame(width: big ? 72 : 54, height: big ? 72 : 54).background(Circle().fill(big ? c.gold : .black.opacity(0.35)))
        }.buttonStyle(Press())
    }
    private func rotate(_ land: Bool) {
        guard let s = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        // the allowed orientations change first, then the turn is asked for (the other order can be refused)
        AppDelegate.orientation = land ? .landscape : .portrait
        for w in s.windows { w.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations(); w.rootViewController?.presentedViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        s.requestGeometryUpdate(.iOS(interfaceOrientations: land ? .landscapeRight : .portrait)) { _ in }
    }

    private func info(_ t: Track) -> some View {
        let r = repo.reciter(t.reciterId)
        let fav = store.favs.contains(t.id)
        let saved = dl.savedTick >= 0 ? VideoFiles.savedH(t.id) : nil
        return VStack(alignment: .leading, spacing: 10) {
            Text(titleL(t)).font(F.amiri(22)).foregroundStyle(c.text)
            if let r { Button { ui.path.append(.reciter(r.id)) } label: { HStack(spacing: 8) { RemoteImage(raw: r.image).frame(width: 30, height: 30).clipShape(Circle()); Text(nm(r.name)).font(F.plex(14, .medium)).foregroundStyle(c.gold) } }.buttonStyle(Press()) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(fav ? "heart.fill" : "heart", fav ? tr("في المفضلة") : tr("المفضلة")) { store.toggleFav(t.id) }
                    if let p = dl.progress[t.id] { chip("arrow.down.circle", tr("جارٍ الحفظ {0}٪", Int(p * 100).ar)) {} }
                    else { chip(saved != nil ? "checkmark.circle" : "arrow.down.circle", saved != nil ? tr("✓ محفوظة") : tr("تحميل")) { sheet = "d" } }
                    if repo.data?.site.sec("clip") != false { chip("scissors", tr("اصنع مقطعًا للمشاركة")) { ui.path.append(.clip(t.id)) } }
                    ShareLink(item: URL(string: Repo.site + "watch/" + t.id) ?? URL(string: Repo.site)!) { HStack(spacing: 6) { Ico(name: "square.and.arrow.up", size: 20); Text(tr("مشاركة")) }.font(F.plex(13, .medium)).foregroundStyle(c.text).padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().fill(c.surface2)) }
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
                Button { store.set("videoQ", "0"); v.setQ(VideoEngine.pickQ(t)); sheet = nil } label: { row(tr("تلقائي"), tr("يختار المناسب لاتصالك"), on: pref == 0) }.listRowBackground(c.surface)
                ForEach(qs, id: \.h) { q in
                    Button { store.set("videoQ", "\(q.h)"); v.setQ(q.h); sheet = nil } label: { row("\(qLabel(q.h)) \(qName(q.h))", sizeTxt(q.size), on: v.h == q.h && pref != 0) }
                }.listRowBackground(c.surface)
            }.bzList(c).navigationTitle(tr("جودة الفيديو")).navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.medium]).environment(\.layoutDirection, L.dir)
    }
    private func downloadSheet(_ t: Track) -> some View {
        let qs = t.video?.q ?? []
        let saved = VideoFiles.savedH(t.id)
        let audioSaved = OfflineFiles.local(t.id) != nil
        return NavigationStack {
            List {
                Section(tr("حفظ للمشاهدة دون إنترنت")) {
                    ForEach(qs, id: \.h) { q in
                        Button { if saved == q.h { ui.say(tr("محفوظة بهذه الجودة بالفعل")) } else { dl.start(t, q.h); ui.say(tr("بدأ تنزيل الملف")) }; sheet = nil } label: { row("\(qLabel(q.h)) \(qName(q.h))", sizeTxt(q.size), on: saved == q.h) }
                    }
                }.listRowBackground(c.surface)
                if !t.audio.isEmpty {
                    Section(tr("حفظ الصوت للاستماع دون إنترنت")) {
                        Button {
                            sheet = nil
                            if audioSaved { ui.say(tr("الصوت محفوظ بالفعل")); return }
                            ui.say(tr("جارٍ حفظ الصوت…"))
                            Task { let ok = await OfflineFiles.save(t); ui.say(ok ? tr("حُفظ الصوت — يمكنك سماعه بدون إنترنت") : tr("تعذّر حفظ الملف. تأكد من المساحة والاتصال.")) }
                        } label: { row(tr("صوت فقط"), sizeTxt(t.video?.audioSize ?? 0), on: audioSaved) }
                    }.listRowBackground(c.surface)
                }
                if saved != nil { Section { Button(role: .destructive) { VideoFiles.delete(t.id); dl.objectWillChange.send(); ui.say(tr("حُذفت من الجهاز")); sheet = nil } label: { Text(tr("حذف النسخة المحفوظة")).font(F.plex(15)) } }.listRowBackground(c.surface) }
            }.bzList(c).navigationTitle(tr("تحميل التلاوة")).navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.medium, .large]).environment(\.layoutDirection, L.dir)
    }
    private func row(_ a: String, _ b: String, on: Bool) -> some View {
        HStack { VStack(alignment: .leading, spacing: 2) { Text(a).font(F.plex(15, .medium)).foregroundStyle(c.text); if !b.isEmpty { Text(b).font(F.plex(12)).foregroundStyle(c.muted) } }; Spacer(); if on { Ico(name: "checkmark", size: 20).foregroundStyle(c.gold) } }
    }
}

/// The seek line of the video: from the left (start) to the right (end).
private struct SeekLine: View {
    let pos: Double, dur: Double; let seek: (Double) -> Void
    @State private var drag: Double?
    @Environment(\.pal) private var c
    var body: some View {
        GeometryReader { g in
            let f = dur > 0 ? min(1, max(0, (drag ?? pos) / dur)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                Capsule().fill(c.gold).frame(width: g.size.width * f, height: 4)
                Circle().fill(c.gold).frame(width: 14, height: 14).offset(x: g.size.width * f - 7)
            }.frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { e in drag = dur * min(1, max(0, e.location.x / g.size.width)) }
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
                    Text(titleL(t)).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(2).multilineTextAlignment(.leading)
                    Text(repo.reciter(t.reciterId)?.shown ?? "").font(F.plex(12)).foregroundStyle(c.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }.buttonStyle(Press())
    }
}
