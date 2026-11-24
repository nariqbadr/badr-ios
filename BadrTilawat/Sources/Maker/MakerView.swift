import SwiftUI
import AVFoundation
import PhotosUI
import CoreText

/// A video picked from the phone (copied into the app's temporary folder).
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { m in SentTransferredFile(m.url) } importing: { r in
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent("mv-\(UUID().uuidString).\(r.file.pathExtension.isEmpty ? "mov" : r.file.pathExtension)")
            try? FileManager.default.removeItem(at: dst); try FileManager.default.copyItem(at: r.file, to: dst)
            return PickedMovie(url: dst)
        }
    }
}

/// Registers a font file downloaded from the dashboard and returns its PostScript name.
func registerFont(_ remote: URL, key: String) async -> String? {
    let f = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("font-\(key).ttf")
    if !FileManager.default.fileExists(atPath: f.path) {
        guard let (tmp, r) = try? await URLSession.shared.download(from: remote), (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? FileManager.default.moveItem(at: tmp, to: f)
    }
    guard let d = CGDataProvider(url: f as CFURL), let cg = CGFont(d) else { return nil }
    CTFontManagerRegisterGraphicsFont(cg, nil)
    return cg.postScriptName as String?
}

/// Plays the design's sound in the preview.
@MainActor
final class MakerAudio {
    private let engine = AVAudioEngine(), node = AVAudioPlayerNode()
    private var rate = 44100.0
    private var started = false
    init() { engine.attach(node) }
    func play(_ pcm: [Float], _ rate: Int) {
        self.rate = Double(rate)
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(rate), channels: 1, interleaved: false)!
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(pcm.count)) else { return }
        b.frameLength = AVAudioFrameCount(pcm.count)
        pcm.withUnsafeBufferPointer { src in b.floatChannelData![0].update(from: src.baseAddress!, count: pcm.count) }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default); try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start(); node.scheduleBuffer(b, at: nil); node.play(); started = true
    }
    /// seconds played (nil = no sound)
    var time: Double? {
        guard started, let nt = node.lastRenderTime, let pt = node.playerTime(forNodeTime: nt) else { return nil }
        return Double(pt.sampleTime) / pt.sampleRate
    }
    func stop() { node.stop(); engine.stop(); started = false }
}

/// «صانع التصاميم»: the site's templates, sizes, text animations, effects, nature sound, tafsir, reciter audio with word
/// tracking; makes a PNG image or an MP4 video (H.264 + AAC) and saves it to the photos.
struct MakerView: View {
    var s0 = 0, a0 = 0
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var o = MakerOpts()
    @State private var ready = false
    @State private var ayahs: [MAyah] = []
    @State private var preview: UIImage?
    @State private var status: String?
    @State private var mode = ""       // "", "play", "video", "busy"
    @State private var progress = 0.0
    @State private var job: Task<Void, Never>?
    @State private var result: (URL, Bool)?
    @State private var pickSurah = false
    @State private var vcat = "all"
    @State private var myVideos: [(id: String, name: String)] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    @State private var thumbs: [String: UIImage] = [:]
    @State private var audio: MakerAudio?
    private let ctx = MakerContext.shared

    private var mk: J { repo.data?.site.j["maker"] ?? J(nil) }
    private var size: (Int, Int) { MAKER_SIZES[o.size] ?? (1080, 1920) }

    /// the maker's reciters: the site's own analysed reciters first, then everyayah, whole-surah reciters, silent
    private var recOpts: [(String, String)] {
        guard let d = repo.data else { return [] }
        let names = d.site.j["reciterNames"]
        let own = d.reciters.filter { r in d.readableTracks.contains { repo.track($0.key)?.reciterId == r.id && $0.value.count >= 3 } }.map { ("tkr:\($0.id)", Repo.withSheikh($0.name)) }
        let ea = MAKER_FOLDERS.map(\.0).filter { !names[$0]["hideMaker"].bool() }.map { ($0, Repo.withSheikh(names[$0]["name"].str.isEmpty ? MAKER_NAMES[$0]! : names[$0]["name"].str)) }
        let sr = d.surahReciters.filter { !names["sr:\($0.id)"]["hideMaker"].bool() }.map { ("sr:\($0.id)", Repo.withSheikh(names["sr:\($0.id)"]["name"].str.isEmpty ? $0.name : names["sr:\($0.id)"]["name"].str)) }
        return own + ea + sr + [("", tr("بدون صوت"))]
    }
    private func ownTracks(_ rid: String) -> [(Int, Int, Int)] {
        (repo.data?.readableTracks ?? [:]).compactMap { k, v in repo.track(k)?.reciterId == rid && v.count >= 3 ? (v[0], v[1], v[2]) : nil }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // preview
            ZStack(alignment: .bottom) {
                Color.black
                if let preview { Image(uiImage: preview).resizable().scaledToFit().accessibilityLabel(tr("معاينة التصميم")) } else { ProgressView().tint(c.gold) }
                if let status {
                    VStack(spacing: 6) {
                        Text(status).font(F.plex(13, .medium)).foregroundStyle(.white).multilineTextAlignment(.center)
                        if mode == "video" { ProgressView(value: progress).tint(c.gold) }
                    }.padding(10).frame(maxWidth: .infinity).background(Color.black.opacity(0.66))
                }
            }
            .aspectRatio(CGFloat(size.0) / CGFloat(size.1), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.line))
            .frame(maxHeight: 360).padding(12)
            // actions
            HStack(spacing: 8) {
                if mode == "play" || (mode == "busy" && job != nil) { GoldButton(title: mode == "play" ? tr("إيقاف المعاينة") : tr("إلغاء"), icon: "xmark") { stop() } }
                else { GoldButton(title: tr("معاينة بالصوت"), icon: "play.fill") { play() } }
                if mode == "video" { GhostButton(title: tr("إيقاف"), icon: "xmark") { stop() } } else { GhostButton(title: tr("فيديو"), icon: "film") { if mode.isEmpty { video() } } }
                GhostButton(title: tr("صورة"), icon: "photo") { if mode.isEmpty { image() } }
            }.padding(.horizontal, 12)
            ScrollView { controls.padding(14) }
        }
        .navigationTitle(tr("صانع التصاميم")).navigationBarTitleDisplayMode(.inline)
        .task { setup() }
        .onChange(of: o) { _ in refresh() }
        .onChange(of: photoItem) { it in
            guard let it else { return }
            Task { if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { MakerBackgrounds.photo = img; MakerBackgrounds.clear(); refreshNow() } }
        }
        .onChange(of: videoItem) { it in
            guard let it else { return }
            Task { if let m = try? await it.loadTransferable(type: PickedMovie.self) { let id = m.url.absoluteString; myVideos.append((id, tr("فيديو من جهازي"))); vcat = "mine"; ctx.videoFrames.files[id] = m.url; o.videos.append(id) } }
        }
        .onDisappear { job?.cancel(); audio?.stop(); ctx.videoFrames.release() }
        .bzSheet(isPresented: $pickSurah) { SurahPickSheet(s: o.surah) { s in pickSurah = false; o.surah = s; o.from = 1; o.to = min(Quran.ayahs[s - 1], 2) } }
        .bzSheet(item: Binding(get: { result.map { R(url: $0.0, video: $0.1) } }, set: { if $0 == nil { result = nil } })) { r in resultSheet(r) }
        .environment(\.layoutDirection, L.dir)
    }
    private struct R: Identifiable { let url: URL; let video: Bool; var id: String { url.absoluteString } }

    private func setup() {
        guard !ready else { return }
        var n = MakerOpts()
        let defRec = mk["defaultReciter"].str
        n.reciter = defRec == "__none" ? "" : (defRec.isEmpty ? "yasser" : defRec)
        n.surah = s0 > 0 ? s0 : min(114, max(1, mk["defaultSurah"].isNull ? 67 : mk["defaultSurah"].int))
        n.from = s0 > 0 ? max(1, a0) : max(1, mk["defaultFrom"].isNull ? 1 : mk["defaultFrom"].int)
        n.to = s0 > 0 ? max(1, a0) : max(1, mk["defaultTo"].isNull ? 2 : mk["defaultTo"].int)
        let tpl = mk["defaultTemplate"].str
        n.tpl = MAKER_TEMPLATES.contains { $0.0 == tpl } ? tpl : "emerald"
        o = n; ready = true
        AudioPlayer.shared.pause(); AyahPlayer.shared.stop()
        refresh()
    }
    private func labels() {
        ctx.watermark = mk["watermark"].str.isEmpty ? (repo.data?.site.title ?? "") : mk["watermark"].str
        ctx.reciterLabel = o.reciter.isEmpty ? "" : (recOpts.first { $0.0 == o.reciter }?.1 ?? "")
    }
    @State private var lastKey = ""
    private func refresh() {
        guard ready else { return }
        labels()
        let key = "\(o.surah)|\(o.from)|\(o.to)|\(o.tafsir)|\(o.font)"
        if key != lastKey {
            lastKey = key
            Task {
                guard let txt = await repo.surahText(o.surah) else { ui.say(tr("تعذّر تحميل نص السورة — تحقق من الاتصال")); return }
                let n = txt.count, f = min(max(1, o.from), n), t = min(max(f, o.to), min(n, f + MAKER_MAX_AYAHS - 1))
                if f != o.from || t != o.to { o.from = f; o.to = t; return }
                ayahs = (f...t).map { MAyah(n: $0, text: ayahClean(o.surah, $0, txt[$0 - 1])) }
                ctx.tafsir = o.tafsir.isEmpty ? [:] : await repo.tafsir(o.surah, edition: o.tafsir)
                ctx.quranFontName = await quranFontName(o.font)
                await nameFontsReady()
                ctx.clearLayout()
                if o.tpl == "video" { await prepareVideos() }
                refreshNow()
            }
        } else { Task { await nameFontsReady(); if o.tpl == "video" { await prepareVideos() }; refreshNow() } }
        if o.tpl == "photo" && MakerBackgrounds.photo == nil {
            let img = repo.data?.site.heroImage.isEmpty == false ? repo.data!.site.heroImage : repo.reciter(repo.data?.site.featuredReciterId)?.image ?? ""
            if let u = Repo.media(img) { Task { if let (d, _) = try? await URLSession.shared.data(from: u), let i = UIImage(data: d) { MakerBackgrounds.photo = i; MakerBackgrounds.clear(); refreshNow() } } }
        }
        if o.tpl == "video" && o.videos.isEmpty { o.videos = [mk["videos"][0]["url"].str.isEmpty ? "scene:sky" : mk["videos"][0]["url"].str] }
    }
    /// the names' fonts uploaded in the dashboard, loaded once
    private func nameFontsReady() async {
        for k in [o.rfont, o.mfont] where !["plex", "amiri", "ruqaa", "kufi", "tajawal", "lateef"].contains(k) && ctx.nameFontNames[k] == nil {
            if let f = mk["fonts"].array.first(where: { $0["family"].str == k }), let u = Repo.media(f["url"].str), let n = await registerFont(u, key: k) { ctx.nameFontNames[k] = n }
            else { ui.say(tr("تعذّر تحميل الخط")) }
        }
    }
    private func quranFontName(_ k: String) async -> String {
        switch k {
        case "amiri": return "AmiriQuran-Regular"
        case "scheherazade": return "ScheherazadeNew-Regular"
        case "naskh": return "Amiri-Regular"
        default:
            if let f = mk["fonts"].array.first(where: { $0["family"].str == k }), let u = Repo.media(f["url"].str), let n = await registerFont(u, key: k) { return n }
            ui.say(tr("تعذّر تحميل الخط")); return "AmiriQuran-Regular"
        }
    }
    /// the half-size still preview
    private func refreshNow() {
        guard mode != "play", mode != "video", !ayahs.isEmpty else { return }
        let (W, H) = size, oo = o, a = ayahs
        Task.detached(priority: .userInitiated) {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1
            let img = UIGraphicsImageRenderer(size: CGSize(width: W / 2, height: H / 2), format: f).image { r in
                r.cgContext.scaleBy(x: 0.5, y: 0.5); MakerContext.shared.drawFrame(r.cgContext, CGFloat(W), CGFloat(H), MakerEngine.staticFrame(a), oo)
            }
            await MainActor.run { preview = img }
        }
    }
    private func prepareVideos() async {
        for u in o.videos where !u.hasPrefix("scene:") && ctx.videoFrames.files[u] == nil {
            status = tr("جارٍ تحميل خلفية الفيديو…")
            if let url = Repo.media(u), let f = try? await MakerEngine.download(url, "v-\(abs(u.hashValue)).mp4") { ctx.videoFrames.files[u] = f }
        }
        if mode.isEmpty { status = nil }
    }
    private func fileBase() -> String { "ayah-\(Quran.surahs[o.surah - 1])-\(o.from)" + (o.to > o.from ? "-\(o.to)" : "") }

    private func stop() { job?.cancel(); job = nil; audio?.stop(); mode = ""; status = nil; refreshNow() }
    private func play() {
        if ayahs.isEmpty { ui.say(tr("اختر السورة والآيات أولًا")); return }
        mode = "busy"; status = tr("جارٍ التجهيز…")
        let oo = o, a = ayahs, (W, H) = size
        job = Task {
            do {
                await prepareVideos()
                let tl = try await MakerEngine.buildTimeline(oo, a) { s in status = s }
                MakerEngine.applyAudioFades(tl, oo)
                mode = "play"
                let au = MakerAudio(); audio = au
                if let pcm = tl.pcm { au.play(pcm, tl.rate) }
                let start = Date()
                while !Task.isCancelled {
                    let t = CGFloat(au.time ?? Date().timeIntervalSince(start))
                    if t >= tl.total { break }
                    let img = await Task.detached(priority: .userInitiated) { () -> UIImage in
                        let f = UIGraphicsImageRendererFormat(); f.scale = 1
                        return UIGraphicsImageRenderer(size: CGSize(width: W / 2, height: H / 2), format: f).image { r in
                            r.cgContext.scaleBy(x: 0.5, y: 0.5)
                            MakerContext.shared.drawFrame(r.cgContext, CGFloat(W), CGFloat(H), MakerEngine.frameAt(tl, t), oo)
                            MakerEngine.fadeBlack(r.cgContext, CGFloat(W), CGFloat(H), tl.total, t, oo)
                        }
                    }.value
                    preview = img; status = tr("معاينة — {0} ث", Int(tl.total - t).ar)
                    try? await Task.sleep(nanoseconds: 16_000_000)
                }
            } catch is CancellationError {} catch { ui.say((error as? MakerError)?.msg ?? tr("تعذّر تحميل صوت التلاوة لهذا القارئ — جرّب قارئًا آخر أو «بدون صوت»")) }
            audio?.stop(); mode = ""; status = nil; job = nil; ctx.clearLayout(); refreshNow()
        }
    }
    private func video() {
        if ayahs.isEmpty { ui.say(tr("اختر السورة والآيات أولًا")); return }
        mode = "busy"; status = tr("جارٍ التجهيز…"); progress = 0
        let oo = o, a = ayahs
        job = Task {
            do {
                await prepareVideos()
                let tl = try await MakerEngine.buildTimeline(oo, a) { s in status = s }
                MakerEngine.applyAudioFades(tl, oo)
                mode = "video"
                let url = try await Task.detached(priority: .userInitiated) {
                    try await MakerExport.video(MakerContext.shared, tl, oo) { p in Task { @MainActor in progress = p; status = tr("جارٍ إنشاء الفيديو {0}٪", Int(p * 100).ar) } }
                }.value
                if await saveToPhotos(url, video: true) { ui.say(tr("حُفظ الفيديو في الصور")) } else { ui.say(tr("الفيديو جاهز — اضغط مشاركة لحفظه")) }
                result = (url, true)
                Repo.shared.event("maker", ["kind": "video"])
            } catch is CancellationError {} catch { ui.say((error as? MakerError)?.msg ?? tr("تعذّر إنشاء الفيديو")) }
            mode = ""; status = nil; job = nil
        }
    }
    private func image() {
        if ayahs.isEmpty { return }
        mode = "busy"; status = tr("جارٍ إنشاء الصورة…")
        let (W, H) = size, oo = o, a = ayahs, base = fileBase()
        Task {
            let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
                return UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: f).pngData { r in MakerContext.shared.drawFrame(r.cgContext, CGFloat(W), CGFloat(H), MakerEngine.staticFrame(a), oo) }
            }.value
            mode = ""; status = nil
            guard let data else { ui.say(tr("تعذّر حفظ الصورة")); return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(base + ".png")
            try? data.write(to: url)
            if await saveToPhotos(url, video: false) { ui.say(tr("حُفظت الصورة في الصور")) }
            result = (url, false)
            Repo.shared.event("maker", ["kind": "image"])
        }
    }
    private func saveToPhotos(_ url: URL, video: Bool) async -> Bool {
        let st = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard st == .authorized || st == .limited else { return false }
        return await withCheckedContinuation { k in
            PHPhotoLibrary.shared().performChanges({
                if video { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) } else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
            }) { ok, _ in k.resume(returning: ok) }
        }
    }

    private func resultSheet(_ r: R) -> some View {
        MenuSheet(title: r.video ? tr("الفيديو جاهز") : tr("الصورة جاهزة")) {
            Text(r.video ? tr("حُفظ الفيديو بصيغة MP4 في الصور — مناسب لتيك توك وإنستغرام وواتساب.") : tr("حُفظت الصورة بجودة عالية في الصور.")).font(F.plex(13)).foregroundStyle(c.muted).padding(.horizontal, 20)
            MenuRow(icon: "square.and.arrow.up", title: tr("مشاركة")) {
                let av = UIActivityViewController(activityItems: [r.url], applicationActivities: nil)
                UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController?.topMost.present(av, animated: true)
            }
            if repo.data?.site.sec("community") != false {
                MenuRow(icon: "paperplane", title: tr("انشر في المجتمع")) {
                    PendingAttach.url = r.url; PendingAttach.video = r.video
                    PendingAttach.text = tr("سورة {0} — ", Quran.surahs[o.surah - 1]) + (o.from == o.to ? tr("الآية {0}", o.from.ar) : tr("الآيات {0}–{1}", o.from.ar, o.to.ar))
                    result = nil; ui.path.append(.compose("new"))
                }
            }
        }.presentationDetents([.medium])
    }

    // MARK: controls
    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            group(tr("الآيات والقارئ")) {
                Button { pickSurah = true } label: {
                    HStack { Text(o.surah.ar).font(F.amiri(15)).foregroundStyle(c.gold).frame(width: 34, height: 34).background(Circle().stroke(c.gold.opacity(0.5)))
                        Text(tr("سورة {0}", Quran.surahs[o.surah - 1])).font(F.amiri(19)).foregroundStyle(c.text); Spacer(); Ico(name: "chevron.down", size: 20).foregroundStyle(c.gold) }
                    .padding(12).background(RoundedRectangle(cornerRadius: 16).fill(c.surface.opacity(0.6))).overlay(RoundedRectangle(cornerRadius: 16).stroke(c.line))
                }.buttonStyle(Press())
                HStack(spacing: 8) {
                    let n = Quran.ayahs[o.surah - 1]
                    menu(tr("من"), "\(o.from.ar)", Array(1...n).map { ("\($0)", $0.ar) }) { v in let f = Int(v)!; o.from = f; o.to = max(f, min(o.to, f + MAKER_MAX_AYAHS - 1)) }
                    menu(tr("إلى"), "\(o.to.ar)", Array(1...n).map { ("\($0)", $0.ar) }) { v in let t = Int(v)!; if t - o.from >= MAKER_MAX_AYAHS { ui.say(tr("الحد الأقصى {0} آية في التصميم الواحد", MAKER_MAX_AYAHS.ar)) }; o.to = t; o.from = max(min(o.from, t), t - MAKER_MAX_AYAHS + 1) }
                }
                menu(tr("صوت القارئ"), recOpts.first { $0.0 == o.reciter }?.1 ?? tr("بدون صوت"), recOpts) { v in
                    o.reciter = v
                    if v.hasPrefix("tkr:") {
                        let list = ownTracks(String(v.dropFirst(4)))
                        if !list.isEmpty && !list.contains(where: { $0.0 == o.surah && o.from >= $0.1 && o.to <= $0.2 }) {
                            let x = list.first { $0.0 == o.surah } ?? list[0]
                            o.surah = x.0; o.from = x.1; o.to = min(x.2, x.1 + 2)
                            ui.say(tr("{0} متاح في: ", repo.reciter(String(v.dropFirst(4)))?.name ?? "") + String(list.map { "\(Quran.surahs[$0.0 - 1]) (\($0.1.ar)–\($0.2.ar))" }.joined(separator: tr("، ")).prefix(160)))
                        }
                    }
                }
            }
            group(tr("التصميم")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(MAKER_TEMPLATES, id: \.0) { t in thumb(t.0, t.1) } }
                }
                if o.tpl == "photo" { PhotosPicker(selection: $photoItem, matching: .images) { Label(tr("اختر صورة من جهازك"), systemImage: "photo").font(F.plex(14, .medium)).foregroundStyle(c.gold) } }
                if o.tpl == "video" { videoPicker }
            }
            group(tr("المقاس")) {
                Picker("", selection: $o.size) { Text(tr("ستوري ٩:١٦")).tag("story"); Text(tr("مربع ١:١")).tag("square"); Text(tr("منشور ٤:٥")).tag("post"); Text(tr("عريض ١٦:٩")).tag("wide") }.pickerStyle(.segmented)
            }
            group(tr("الحركة والتأثيرات")) {
                menu(tr("ظهور النص"), animName(o.anim), [("fade", tr("تلاشٍ ناعم")), ("rise", tr("صعود هادئ")), ("words", tr("كلمة كلمة مع التلاوة")), ("glow", tr("توهّج ذهبي")), ("shine", tr("لمعة ذهبية تمر على النص")),
                                                    ("lines", tr("سطرًا سطرًا")), ("wipe", tr("كتابة من اليمين")), ("scale", tr("تكبير ناعم")), ("pop", tr("ظهور بارز")), ("drop", tr("نزول من الأعلى")), ("blur", tr("من الضباب إلى الوضوح")), ("none", tr("بدون حركة"))]) { o.anim = $0 }
                FlowLayout(spacing: 6) {
                    Pill(title: tr("غبار ذهبي"), on: o.particles) { o.particles.toggle() }; Pill(title: tr("تقريب بطيء"), on: o.zoom) { o.zoom.toggle() }
                    Pill(title: tr("أشعة نور"), on: o.rays) { o.rays.toggle() }; Pill(title: tr("هالات ضوء"), on: o.bokeh) { o.bokeh.toggle() }
                    Pill(title: tr("مطر"), on: o.rain) { o.rain.toggle() }; Pill(title: tr("إطار سينمائي"), on: o.vignette) { o.vignette.toggle() }
                    Pill(title: tr("شريط التقدم"), on: o.bar) { o.bar.toggle() }; Pill(title: tr("اسم السورة والآية"), on: o.meta) { o.meta.toggle() }
                    Pill(title: tr("اسم القارئ"), on: o.rname) { o.rname.toggle() }; Pill(title: tr("اسم الموقع"), on: o.mark) { o.mark.toggle() }
                }
                menu(tr("صوت الطبيعة"), ["": tr("بدون"), "rain": tr("مطر"), "wind": tr("رياح"), "waves": tr("أمواج البحر"), "stream": tr("جدول ماء"), "night": tr("ليل هادئ")][o.amb] ?? tr("بدون"),
                     [("", tr("بدون")), ("rain", tr("مطر")), ("wind", tr("رياح")), ("waves", tr("أمواج البحر")), ("stream", tr("جدول ماء")), ("night", tr("ليل هادئ"))]) { o.amb = $0 }
                if !o.amb.isEmpty { slider(tr("مستوى صوت الطبيعة"), Binding(get: { Double(o.ambVol) }, set: { o.ambVol = Int($0) }), 5...100) }
                let fonts = [("amiri", tr("أميري قرآن")), ("scheherazade", tr("شهرزاد")), ("naskh", tr("نسخ"))] + mk["fonts"].array.filter { $0["use"].str != "info" }.map { ($0["family"].str, $0["name"].str.isEmpty ? $0["family"].str : $0["name"].str) }
                menu(tr("خط الآية"), fonts.first { $0.0 == o.font }?.1 ?? tr("أميري قرآن"), fonts) { o.font = $0 }
                menu(tr("التفسير"), ["": tr("بدون تفسير"), "ar.muyassar": tr("التفسير الميسر"), "ar.jalalayn": tr("تفسير الجلالين"), "en.sahih": "English"][o.tafsir] ?? tr("بدون تفسير"),
                     [("", tr("بدون تفسير")), ("ar.muyassar", tr("التفسير الميسر")), ("ar.jalalayn", tr("تفسير الجلالين")), ("en.sahih", "English")]) { o.tafsir = $0 }
                slider(tr("حجم الخط"), Binding(get: { Double(o.fontScale) }, set: { o.fontScale = Int($0) }), 70...140)
                Text(tr("البداية والنهاية (الأسود والصوت)")).font(F.plex(14, .bold)).foregroundStyle(c.text).padding(.top, 6)
                slider(tr("دخول الصورة · {0}", sec(o.vfi)), Binding(get: { Double(o.vfi) }, set: { o.vfi = CGFloat(($0 * 10).rounded() / 10) }), 0...3)
                slider(tr("خروج الصورة · {0}", sec(o.vfo)), Binding(get: { Double(o.vfo) }, set: { o.vfo = CGFloat(($0 * 10).rounded() / 10) }), 0...3)
                slider(tr("دخول الصوت · {0}", sec(o.afi)), Binding(get: { Double(o.afi) }, set: { o.afi = CGFloat(($0 * 10).rounded() / 10) }), 0...4)
                slider(tr("خروج الصوت · {0}", sec(o.afo)), Binding(get: { Double(o.afo) }, set: { o.afo = CGFloat(($0 * 10).rounded() / 10) }), 0...4)
                let nameFonts = [("plex", tr("عادي")), ("amiri", tr("أميري")), ("ruqaa", tr("رقعة")), ("kufi", tr("كوفي")), ("tajawal", tr("تجوال عريض")), ("lateef", tr("لطيف"))] + mk["fonts"].array.filter { ["info", "both"].contains($0["use"].str) }.map { ($0["family"].str, $0["name"].str.isEmpty ? $0["family"].str : $0["name"].str) }
                if o.rname {
                    field(tr("نص اسم القارئ"), tr("فارغ = «بصوت الشيخ …»"), Binding(get: { o.rtext }, set: { o.rtext = String($0.prefix(70)) }))
                    menu(tr("خط اسم القارئ"), nameFonts.first { $0.0 == o.rfont }?.1 ?? tr("عادي"), nameFonts) { o.rfont = $0 }
                    slider(tr("حجم اسم القارئ"), Binding(get: { Double(o.rsize) }, set: { o.rsize = Int($0) }), 70...170)
                }
                if o.mark {
                    field(tr("نص اسم الموقع"), ctx.watermark.isEmpty ? tr("مثل: تطبيق بدر التلاوات") : ctx.watermark, Binding(get: { o.mtext }, set: { o.mtext = String($0.prefix(60)) }))
                    menu(tr("خط اسم الموقع"), nameFonts.first { $0.0 == o.mfont }?.1 ?? tr("عادي"), nameFonts) { o.mfont = $0 }
                    slider(tr("حجم اسم الموقع"), Binding(get: { Double(o.msize) }, set: { o.msize = Int($0) }), 70...200)
                }
            }
        }.padding(.bottom, 40)
    }
    private func animName(_ k: String) -> String {
        ["fade": tr("تلاشٍ ناعم"), "rise": tr("صعود هادئ"), "words": tr("كلمة كلمة مع التلاوة"), "glow": tr("توهّج ذهبي"), "shine": tr("لمعة ذهبية"), "lines": tr("سطرًا سطرًا"), "wipe": tr("كتابة من اليمين"),
         "scale": tr("تكبير ناعم"), "pop": tr("ظهور بارز"), "drop": tr("نزول من الأعلى"), "blur": tr("من الضباب إلى الوضوح"), "none": tr("بدون حركة")][k] ?? k
    }
    private func sec(_ v: CGFloat) -> String { let d = Int((v * 10).rounded()); return d <= 0 ? tr("بدون") : tr("{0}{1} ث", (d / 10).ar, d % 10 != 0 ? "٫" + (d % 10).ar : "") }

    private var videoPicker: some View {
        let lib: [(id: String, name: String, cat: String)] = mk["videos"].array.compactMap { v in v["url"].str.isEmpty ? nil : (v["url"].str, v["name"].str.isEmpty ? tr("فيديو") : v["name"].str, v["cat"].str.isEmpty ? "nature" : v["cat"].str) }
            + myVideos.map { ($0.id, $0.name, "mine") } + [("scene:sky", tr("سماء وغيوم"), "scene"), ("scene:sea", tr("بحر عند الغروب"), "scene"), ("scene:stars", tr("ليل ونجوم"), "scene")]
        let cats = [("all", tr("الكل")), ("haram", tr("الحرم المكي")), ("nabawi", tr("المسجد النبوي")), ("nature", tr("مناظر طبيعية")), ("scene", tr("مشاهد مرسومة")), ("mine", tr("من جهازي"))].filter { k, _ in k == "all" || lib.contains { $0.cat == k } }
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(cats, id: \.0) { k in Pill(title: k.1, on: vcat == k.0) { vcat = k.0 } } } }
            FlowLayout(spacing: 6) {
                ForEach(lib.filter { vcat == "all" || $0.cat == vcat }, id: \.id) { v in
                    let i = o.videos.firstIndex(of: v.id)
                    Pill(title: (i.map { "\(($0 + 1).ar). " } ?? "") + v.name, on: i != nil) { if let i { o.videos.remove(at: i) } else { o.videos.append(v.id) } }
                }
                PhotosPicker(selection: $videoItem, matching: .videos) { Label(tr("فيديو من جهازي"), systemImage: "plus").font(F.plex(13, .medium)).foregroundStyle(c.gold).padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().stroke(c.gold.opacity(0.5))) }
            }
            Text(o.videos.count > 1 ? tr("{0} خلفيات — تتبدّل بالترتيب المرقّم", o.videos.count.ar) : tr("اختر خلفية أو أكثر — مع أكثر من خلفية تتبدّل بانتقال ناعم")).font(F.plex(12)).foregroundStyle(c.muted)
            HStack(spacing: 8) {
                menu(tr("تبديل الخلفيات"), ["time": tr("كل مدة أحددها"), "ayah": tr("مع كل آية"), "none": tr("بدون تبديل")][o.vidMode] ?? "", [("time", tr("كل مدة أحددها")), ("ayah", tr("مع كل آية")), ("none", tr("بدون تبديل"))]) { o.vidMode = $0 }
                if o.vidMode == "time" { menu(tr("كل"), tr("{0} ث", o.every.ar), [4, 6, 8, 10, 15, 20, 30].map { ("\($0)", tr("{0} ث", $0.ar)) }) { o.every = Int($0)! } }
            }
            HStack(spacing: 8) {
                menu(tr("مدة الانتقال"), tr("{0} ث", o.transLen), [0.6, 1.0, 1.4, 2.0, 3.0].map { ("\($0)", tr("{0} ث", $0)) }) { o.transLen = CGFloat(Double($0)!) }
                menu(tr("الانتقال"), ["fade": tr("تلاشٍ ناعم"), "black": tr("عبر الأسود"), "white": tr("عبر الأبيض"), "zoom": tr("تكبير ودخول"), "blur": tr("ضبابي"), "slide": tr("انزلاق"), "wipe": tr("مسح"), "circle": tr("دائرة")][o.trans] ?? "",
                     [("fade", tr("تلاشٍ ناعم")), ("black", tr("عبر الأسود")), ("white", tr("عبر الأبيض")), ("zoom", tr("تكبير ودخول")), ("blur", tr("ضبابي")), ("slide", tr("انزلاق")), ("wipe", tr("مسح")), ("circle", tr("دائرة"))]) { o.trans = $0 }
            }
        }
    }

    private func thumb(_ id: String, _ name: String) -> some View {
        Button { o.tpl = id } label: {
            VStack(spacing: 4) {
                ZStack { if let b = thumbs[id] { Image(uiImage: b).resizable().scaledToFill() } else { c.surface }
                }.frame(width: 92, height: 133).clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(o.tpl == id ? c.gold : c.line, lineWidth: o.tpl == id ? 2.5 : 1))
                Text(name).font(F.plex(11)).foregroundStyle(o.tpl == id ? c.gold : c.text).lineLimit(2).multilineTextAlignment(.center).frame(width: 92)
            }
        }.buttonStyle(Press())
        .task {
            if thumbs[id] != nil { return }
            let img = await Task.detached(priority: .utility) { () -> UIImage in
                let f = UIGraphicsImageRendererFormat(); f.scale = 1
                return UIGraphicsImageRenderer(size: CGSize(width: 270, height: 390), format: f).image { r in
                    r.cgContext.scaleBy(x: 0.25, y: 0.25)
                    var oo = MakerOpts(); oo.tpl = id; oo.videos = ["scene:sky"]; oo.surah = 24
                    MakerContext.thumbs.drawFrame(r.cgContext, 1080, 1560, MakerEngine.staticFrame([MAyah(n: 35, text: tr("ٱللَّهُ نُورُ ٱلسَّمَٰوَٰتِ وَٱلْأَرْضِ"))]), oo)
                }
            }.value
            thumbs[id] = img
        }
    }

    private func group<V: View>(_ title: String, @ViewBuilder _ v: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(F.plex(15, .bold)).foregroundStyle(c.gold); v() }
    }
    private func menu(_ label: String, _ value: String, _ opts: [(String, String)], _ pick: @escaping (String) -> Void) -> some View {
        Menu { ForEach(opts, id: \.0) { k in Button(k.1) { pick(k.0) } } } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(F.plex(11)).foregroundStyle(c.muted)
                HStack { Text(value).font(F.plex(14, .medium)).foregroundStyle(c.text).lineLimit(1); Spacer(); Ico(name: "chevron.down", size: 14.4).foregroundStyle(c.gold) }
            }.padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 14).fill(c.surface.opacity(0.6))).overlay(RoundedRectangle(cornerRadius: 14).stroke(c.line))
        }
    }
    private func slider(_ label: String, _ v: Binding<Double>, _ r: ClosedRange<Double>) -> some View {
        HStack { Text(label).font(F.plex(13)).foregroundStyle(c.text).frame(width: 140, alignment: .leading); Slider(value: v, in: r).tint(c.gold) }
    }
    private func field(_ label: String, _ hint: String, _ v: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(F.plex(12)).foregroundStyle(c.muted)
            TextField(hint, text: v).font(F.plex(14)).padding(10).background(RoundedRectangle(cornerRadius: 12).fill(c.surface.opacity(0.6))).overlay(RoundedRectangle(cornerRadius: 12).stroke(c.line))
        }
    }
}

extension MakerContext {
    static let shared = MakerContext()
    /// thumbnails are drawn on their own context (another thread, no shared layout)
    static let thumbs = MakerContext()
}

/// A file the maker made, to attach in the community composer.
enum PendingAttach { nonisolated(unsafe) static var url: URL?; nonisolated(unsafe) static var video = false; nonisolated(unsafe) static var text = "" }

/// Choosing a surah (name or number).
struct SurahPickSheet: View {
    let s: Int; let pick: (Int) -> Void
    @State private var q = ""
    @Environment(\.pal) private var c
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(Quran.surahs.enumerated()).filter { q.isEmpty || QuranMeta.norm($0.element).contains(QuranMeta.norm(q)) || "\($0.offset + 1)" == q }, id: \.offset) { i, n in
                    Button { pick(i + 1) } label: { HStack { Text((i + 1).ar).font(F.plex(13)).foregroundStyle(c.gold).frame(width: 34); Text(tr("سورة {0}", n)).font(F.amiri(18)).foregroundStyle(i + 1 == s ? c.gold : c.text); Spacer(); Text(tr("{0} آية", Quran.ayahs[i].ar)).font(F.plex(12)).foregroundStyle(c.muted) } }
                }.listRowBackground(c.surface)
            }.bzList(c).searchable(text: $q, prompt: tr("ابحث عن سورة")).navigationTitle(tr("اختر السورة")).navigationBarTitleDisplayMode(.inline)
        }.environment(\.layoutDirection, L.dir)
    }
}

/// Wraps its children onto as many rows as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 360; var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews { let z = s.sizeThatFits(.unspecified); if x > 0 && x + z.width > w { x = 0; y += rowH + spacing; rowH = 0 }; x += z.width + spacing; rowH = max(rowH, z.height) }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, rowH: CGFloat = 0
        for s in subviews { let z = s.sizeThatFits(.unspecified); if x > b.minX && x + z.width > b.maxX { x = b.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z)); x += z.width + spacing; rowH = max(rowH, z.height) }
    }
}
