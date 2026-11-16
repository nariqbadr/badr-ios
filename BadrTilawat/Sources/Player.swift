import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// The recitations player: background audio, lock-screen controls, queue, speed, sleep timer, resume position.
@MainActor
final class PlayerClock: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var buffering = false
}

@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()
    private let player = AVPlayer()
    private var timeObs: Any?
    private var endObs: NSObjectProtocol?

    @Published private(set) var queue: [Track] = []
    @Published private(set) var index = -1
    @Published private(set) var playing = false
    /// Position, length and buffering change several times a second: they live in [clock], so only the views that
    /// show them (the seek bars) redraw, not every screen that knows about the player.
    let clock = PlayerClock()
    private(set) var buffering: Bool { get { clock.buffering } set { if clock.buffering != newValue { clock.buffering = newValue } } }
    var position: Double { get { clock.position } set { if clock.position != newValue { clock.position = newValue } } }
    private(set) var duration: Double { get { clock.duration } set { if clock.duration != newValue { clock.duration = newValue } } }
    @Published var repeatMode = 0      // 0 off, 1 all, 2 one
    @Published var shuffle = false
    @Published private(set) var sleepAt: Date?
    /// «تكرار عددًا محددًا»: each recitation plays repN times, then the next (0 = off)
    @Published private(set) var repN = 0
    @Published private(set) var repDone = 0
    func repeatTimes(_ n: Int) { repN = n; repDone = 1; repeatMode = 0 }
    func setRepeat(_ m: Int) { repeatMode = m; repN = 0; repDone = 0 }
    private var sleepEndOfTrack = false
    private var sleepTask: Task<Void, Never>?
    private var lastSave = Date.distantPast
    private var progressSent = Set<Int>()

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    /// the exact playing position (position is updated twice a second)
    var currentTime: Double { let t = player.currentTime().seconds; return t.isFinite ? t : position }

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        timeObs = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in self?.tick(t.seconds) }
        }
        endObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] n in
            Task { @MainActor in
                guard let self, (n.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.ended()
            }
        }
        remote()
    }

    // MARK: control
    /// «اقرأ واحفظ» names the ayah being read under the title in the small player (track id, label)
    @Published var nowLabel: (String, String)?
    private var startAt: Double?
    func play(_ t: Track, in list: [Track]? = nil, fromStart: Bool = false, startAt: Double? = nil) {
        AyahPlayer.shared.stop()
        self.startAt = startAt
        if fromStart { for x in list ?? [t] { Store.shared.savePosition(x.id, 0, 0) } }
        let l = list ?? [t]
        queue = l; index = l.firstIndex(of: t) ?? 0
        if !l.contains(t) { queue = [t]; index = 0 }
        load()
    }
    func toggle() {
        if current == nil { return }
        if playing { player.pause() } else { AyahPlayer.shared.stop(); try? AVAudioSession.sharedInstance().setActive(true); player.play(); player.rate = Store.shared.speed }
        playing.toggle(); nowPlaying()
    }
    func pause() { player.pause(); playing = false; nowPlaying() }
    func next() {
        guard !queue.isEmpty else { return }
        if shuffle && queue.count > 1 { var i = index; while i == index { i = Int.random(in: 0..<queue.count) }; index = i }
        else if index + 1 < queue.count { index += 1 } else if repeatMode == 1 { index = 0 } else { return }
        load()
    }
    func prev() { if position > 4 || index == 0 { seek(0) } else { index -= 1; load() } }
    func seek(_ s: Double) { player.seek(to: CMTime(seconds: max(0, s), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero); position = s; nowPlaying() }
    func skip(_ s: Double) { seek(min(max(0, position + s), duration)) }
    func setSpeed(_ r: Float) { Store.shared.speed = r; if playing { player.rate = r }; nowPlaying() }
    func cycleRepeat() { repeatMode = (repeatMode + 1) % 3 }
    func playNext(_ t: Track) { if current == nil { play(t); return }; queue.insert(t, at: index + 1) }
    func enqueue(_ t: Track) { if current == nil { play(t); return }; queue.append(t) }
    func playAt(_ i: Int) { guard queue.indices.contains(i) else { return }; index = i; load() }
    func remove(at i: Int) { guard queue.indices.contains(i), i != index else { return }; queue.remove(at: i); if i < index { index -= 1 } }
    func move(_ from: Int, _ to: Int) { guard queue.indices.contains(from), queue.indices.contains(to), from != index, from != to else { return }; let t = queue.remove(at: from); queue.insert(t, at: to); if from > index && to <= index { index += 1 } }
    /// «إغلاق المشغّل»: stop and empty the queue
    func close() { if let t = current { Store.shared.savePosition(t.id, position, duration) }; player.pause(); player.replaceCurrentItem(with: nil); playing = false; queue = []; index = -1; nowPlaying() }
    func clearUpcoming() { if index >= 0 { queue = Array(queue.prefix(index + 1)) } }

    /// minutes; -1 = at the end of this recitation; 0 = off
    func sleep(_ minutes: Int) {
        sleepTask?.cancel(); sleepEndOfTrack = false; sleepAt = nil
        if minutes == -1 { sleepEndOfTrack = true; return }
        guard minutes > 0 else { return }
        let at = Date().addingTimeInterval(Double(minutes) * 60); sleepAt = at
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.pause(); self?.sleepAt = nil }
        }
    }
    var sleepOn: Bool { sleepAt != nil || sleepEndOfTrack }

    /// pages that light the words with the voice (Mushaf, «اقرأ واستمع واحفظ»): they need exact timing
    var follow = 0 { didSet { if oldValue == 0 && follow > 0 && !curPrecise { preciseNow() } } }
    private var curPrecise = false
    /// the same recitation again with exact timing, from where it is (when a following page opens during playback)
    private func preciseNow() {
        guard let t = current, OfflineFiles.local(t.id) == nil, let url = Repo.media(t.audio) else { return }
        let at = position, was = playing
        curPrecise = true
        player.replaceCurrentItem(with: AVPlayerItem(asset: AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])))
        player.seek(to: CMTime(seconds: at, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if was { player.play(); player.rate = Store.shared.speed }
    }

    // MARK: internals
    private func load() {
        guard let t = current, let url = Repo.media(t.audio) else { return }
        if yieldRemote { yieldRemote = false; VideoEngine.shared.pause(); remote() }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        // precise timing: with the usual estimate, an MP3's clock drifts after a seek or a resume, and the words
        // lit in «اقرأ واستمع واحفظ» / the Mushaf fall behind or run ahead of the voice
        // precise timing reads the file through before it plays: kept for saved files and while the words are followed
        // (Mushaf / «اقرأ واستمع»); otherwise a recitation starts the moment it is tapped
        let local = OfflineFiles.local(t.id)
        curPrecise = local != nil || follow > 0
        let item = AVPlayerItem(asset: AVURLAsset(url: local ?? url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: curPrecise]))
        item.preferredForwardBufferDuration = 0
        player.automaticallyWaitsToMinimizeStalling = local == nil ? false : true
        player.replaceCurrentItem(with: item)
        let resume = startAt ?? Store.shared.position(t.id); startAt = nil
        if resume > 0 { player.seek(to: CMTime(seconds: resume, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
        position = resume; duration = Double(t.durationSec)
        if repN > 0 { repDone = 1 }
        player.play(); player.rate = Store.shared.speed
        playing = true; buffering = true; progressSent = []
        Store.shared.addHistory(t.id)
        Repo.shared.event("play", ["id": t.id])
        nowPlaying(); artwork(t)
    }
    private func tick(_ s: Double) {
        guard current != nil else { return }
        position = s.isFinite ? s : 0
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if playing, Date().timeIntervalSince(lastSave) > 5, let t = current { lastSave = Date(); Store.shared.savePosition(t.id, position, duration) }
        if playing, duration > 0, let t = current {
            let pc = Int(100 * position / duration)
            for m in [25, 50, 75, 100] where pc >= (m == 100 ? 97 : m) && !progressSent.contains(m) { progressSent.insert(m); Repo.shared.event("progress", ["id": t.id, "pct": "\(m)"]) }
        }
    }
    private func ended() {
        if let t = current { Store.shared.savePosition(t.id, 0, 0) }
        if sleepEndOfTrack { sleepEndOfTrack = false; playing = false; nowPlaying(); return }
        if repeatMode == 2 { seek(0); player.play(); return }
        if repN > 1 && repDone < repN { repDone += 1; seek(0); player.play(); return }
        if repN > 0 { repDone = 1 }
        if index + 1 < queue.count || repeatMode == 1 || shuffle { next() } else { playing = false; nowPlaying() }
    }

    // MARK: lock screen
    private var art: MPMediaItemArtwork?
    private func nowPlaying() {
        WidgetBridge.now()
        guard let t = current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: titleL(t), MPMediaItemPropertyArtist: Repo.shared.reciter(t.reciterId)?.shown ?? "",
                                   MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
                                   MPNowPlayingInfoPropertyPlaybackRate: playing ? Double(Store.shared.speed) : 0]
        if let a = art { info[MPMediaItemPropertyArtwork] = a }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func artwork(_ t: Track) {
        art = nil
        guard let u = Repo.media(Repo.shared.image(for: t)) else { return }
        Task {
            guard let (d, _) = try? await Repo.shared.session.data(from: u), let img = UIImage(data: d) else { return }
            await MainActor.run { self.art = makeArtwork(img); self.nowPlaying() }
        }
    }
    /// The video page took the lock-screen controls; the next recitation played takes them back.
    var yieldRemote = false
    private func remote() {
        let c = MPRemoteCommandCenter.shared()
        for cmd in [c.playCommand, c.pauseCommand, c.togglePlayPauseCommand, c.nextTrackCommand, c.previousTrackCommand, c.changePlaybackPositionCommand, c.skipForwardCommand, c.skipBackwardCommand] { cmd.removeTarget(nil) }
        c.skipForwardCommand.isEnabled = false; c.skipBackwardCommand.isEnabled = false
        c.nextTrackCommand.isEnabled = true; c.previousTrackCommand.isEnabled = true
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.playing == false { self?.toggle() } }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.prev() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent { Task { @MainActor in self?.seek(e.positionTime) } }
            return .success
        }
    }
}

/// Short ayah playback («آية اليوم», the Quran reader) — everyayah reciters, whole-surah reciters (sr:) and the site's analysed recitations (tk:).
@MainActor
final class AyahPlayer: ObservableObject {
    static let shared = AyahPlayer()
    private let player = AVPlayer()
    @Published private(set) var key: String?
    @Published private(set) var playing = false
    @Published private(set) var status = ""
    /// 0…1 of the ayah playing (for the seek bar)
    @Published private(set) var progress: Double = 0
    private var tickObs: Any?
    private var left = 1, repeatN = 1
    private var then: (() -> Void)?
    private var endObs: NSObjectProtocol?

    private init() {
        tickObs = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in guard let self, let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 else { return }; self.progress = min(1, t.seconds / d) }
        }
        endObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] n in
            Task { @MainActor in
                guard let self, (n.object as? AVPlayerItem) === self.player.currentItem else { return }
                if self.repeatN == 0 || self.left > 1 { self.left -= 1; self.player.seek(to: .zero); self.player.play() }
                else { self.playing = false; self.key = nil; let f = self.then; self.then = nil; f?() }
            }
        }
    }

    struct Option: Hashable { let value: String, label: String, ok: Bool }
    /// Reciters that can play this ayah.
    func options(_ s: Int, _ a: Int) -> [Option] {
        guard let d = Repo.shared.data else { return Quran.everyayah.map { Option(value: $0.key, label: $0.name, ok: true) } }
        var out: [Option] = []
        for r in d.reciters {
            let mine = d.readableTracks.filter { Repo.shared.track($0.key)?.reciterId == r.id && $0.value.count >= 3 }
            if !mine.isEmpty { out.append(Option(value: "tk:" + r.id, label: Repo.withSheikh(r.name), ok: mine.contains { $0.value[0] == s && $0.value[1] <= a && a <= $0.value[2] })) }
        }
        for e in Quran.everyayah { let n = d.site.reciterName(e.key); if !n.hideAyah { out.append(Option(value: e.key, label: Repo.withSheikh(n.name.isEmpty ? e.name : n.name), ok: true)) } }
        for sr in d.surahReciters { let v = "sr:" + sr.id; let n = d.site.reciterName(v); if !n.hideAyah { out.append(Option(value: v, label: Repo.withSheikh(n.name.isEmpty ? sr.name : n.name), ok: (d.readableSr[sr.id] ?? []).contains(s))) } }
        return out
    }
    func label(_ v: String, _ s: Int = 1, _ a: Int = 1) -> String { options(s, a).first { $0.value == v }?.label ?? "" }

    private func url(_ rv: String, _ s: Int, _ a: Int) -> URL? {
        let k = Quran.key(s, a)
        if rv.hasPrefix("tk:") {
            guard let d = Repo.shared.data, let tid = d.readableTracks.first(where: { Repo.shared.track($0.key)?.reciterId == String(rv.dropFirst(3)) && $0.value.count >= 3 && $0.value[0] == s && $0.value[1] <= a && a <= $0.value[2] })?.key else { return nil }
            return URL(string: Repo.ajax + "?action=bz&do=track_clip&id=\(Repo.enc(tid))&from=\(a)&to=\(a)")
        }
        if rv.hasPrefix("sr:") {
            guard (Repo.shared.data?.readableSr[String(rv.dropFirst(3))] ?? []).contains(s) else { return nil }
            return URL(string: Repo.ajax + "?action=bz&do=ayah_audio&r=\(Repo.enc(rv))&k=\(k)")
        }
        let folder = Quran.everyayah.first { $0.key == rv }?.folder ?? Quran.everyayah[0].folder
        return URL(string: "https://everyayah.com/data/\(folder)/\(k).mp3")
    }

    /// repeat: 1, 3, 5, 10 … or 0 for endless. Falls back to Yasser Al-Dosari when the reciter has no recording of this ayah.
    func play(_ rv: String, _ s: Int, _ a: Int, repeat r: Int = 1, then: (() -> Void)? = nil) {
        AudioPlayer.shared.pause()
        let main = url(rv, s, a)
        guard let u = main ?? url("yasser", s, a) else { status = tr("تعذّر تحميل الصوت"); return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.replaceCurrentItem(with: AVPlayerItem(url: u)); player.play()
        key = "\(s):\(a)|\(rv)"; playing = true; repeatN = r; left = r == 0 ? Int.max : r; self.then = then
        status = main == nil ? tr("هذه الآية غير متاحة بهذا الصوت — تُشغَّل بصوت الشيخ ياسر الدوسري") : (r == 0 ? tr("تكرار مستمر") : label(rv, s, a))
        Repo.shared.event("ayah", ["s": "\(s)", "a": "\(a)"])
    }
    func stop() { player.pause(); playing = false; key = nil; then = nil }
}

/// «بدون إنترنت»: recitations saved on the phone.
enum OfflineFiles {
    static var dir: URL { let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("offline"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }
    static func file(_ id: String) -> URL { dir.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_") + ".mp3") }
    static func local(_ id: String) -> URL? { FileManager.default.fileExists(atPath: file(id).path) ? file(id) : nil }
    static var ids: [String] { (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.map { String($0.dropLast(4)) } ?? [] }
    static func save(_ t: Track) async -> Bool {
        guard let u = await Repo.media(t.audio), let (tmp, r) = try? await URLSession.shared.download(from: u), (r as? HTTPURLResponse)?.statusCode == 200 else { return false }
        try? FileManager.default.removeItem(at: file(t.id))
        return (try? FileManager.default.moveItem(at: tmp, to: file(t.id))) != nil
    }
    static func delete(_ id: String) { try? FileManager.default.removeItem(at: file(id)) }
}

/// Lock-screen artwork. Made outside the main actor: the system asks for the picture from a background thread.
func makeArtwork(_ img: UIImage) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: img.size) { @Sendable _ in img }
}
