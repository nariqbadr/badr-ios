import SwiftUI
import AVFoundation
import UserNotifications

// MARK: - «الورد اليومي»

/// The daily Quran portion: how many pages a day, where the next portion starts, and a daily reminder (like the site's «الورد اليومي»).
@MainActor
enum Wird {
    static let amounts: [(Int, String)] = [(1, "صفحة"), (2, "صفحتان"), (5, "ربع جزء"), (10, "حزب"), (20, "جزء"), (40, "جزءان")]
    private static var s: Store { Store.shared }
    static var on: Bool { s.str("wirdOn", "0") == "1" }
    static var remind: Bool { s.str("wirdRemind", "1") == "1" }
    static var pages: Int { let p = Int(s.str("wirdPages", "5")) ?? 5; return amounts.contains { $0.0 == p } ? p : 5 }
    static var time: String { let t = s.str("wirdTime", "21:00"); return t.range(of: "^([01]\\d|2[0-3]):[0-5]\\d$", options: .regularExpression) != nil ? t : "21:00" }
    static var next: Int { min(604, max(1, Int(s.str("wirdNext", "1")) ?? 1)) }
    static var khatmas: Int { Int(s.str("wirdKhatmas", "0")) ?? 0 }
    private static var prev: Int { Int(s.str("wirdPrev", "0")) ?? 0 }
    static var today: String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }
    static var doneToday: Bool { s.str("wirdDone") == today }
    static var canUndo: Bool { doneToday && prev > 0 }
    static var range: (Int, Int) { (next, min(604, next + pages - 1)) }
    static func juzOf(_ p: Int) -> Int { p < 22 ? 1 : min(30, (p - 2) / 20 + 1) }
    static func surahOfPage(_ p: Int) -> Int { (Quran.surahPage.lastIndex { $0 <= p } ?? 0) + 1 }
    static var text: String { let (f, t) = range; return (f == t ? "صفحة \(f.ar)" : "من صفحة \(f.ar) إلى \(t.ar)") + " — \(Quran.surahs[surahOfPage(f) - 1])" }
    static var percent: Int { (next - 1) * 100 / 604 }

    private static func put(_ kv: [(String, String)]) { kv.forEach { s.set($0.0, $0.1) }; s.objectWillChange.send(); Prayers.shared.schedule() }
    static func setOn(_ r: Bool) { put([("wirdOn", "1"), ("wirdRemind", r ? "1" : "0")]) }
    static func setPages(_ n: Int) { put([("wirdOn", "1"), ("wirdPages", "\(n)")]) }
    static func setTime(_ t: String) { put([("wirdOn", "1"), ("wirdTime", t)]) }
    static func setStart(_ p: Int) { put([("wirdOn", "1"), ("wirdNext", "\(min(604, max(1, p)))"), ("wirdDone", ""), ("wirdPrev", "0")]) }
    /// «أتممت ورد اليوم»: the next portion starts after this one. True when this finished a khatma.
    static func done() -> Bool {
        let (f, t) = range; var n = t + 1, k = khatmas; let kh = n > 604
        if kh { n = 1; k += 1 }
        put([("wirdOn", "1"), ("wirdNext", "\(n)"), ("wirdKhatmas", "\(k)"), ("wirdDone", today), ("wirdPrev", "\(f)")]); return kh
    }
    static func undo() {
        let p = prev; guard p > 0 else { return }
        let k = next == 1 && p > 1 ? max(0, khatmas - 1) : khatmas
        put([("wirdNext", "\(p)"), ("wirdKhatmas", "\(k)"), ("wirdDone", ""), ("wirdPrev", "0")])
    }
    /// the next 7 reminders (today's is skipped once the portion is done); added by Prayers.schedule()
    static func requests() -> [UNNotificationRequest] {
        guard on && remind else { return [] }
        let hm = time.split(separator: ":").compactMap { Int($0) }; guard hm.count == 2 else { return [] }
        var out: [UNNotificationRequest] = []
        let cal = Calendar.current, now = Date()
        for d in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: d, to: now), let at = cal.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: day), at > now else { continue }
            if d == 0 && doneToday { continue }
            let n = UNMutableNotificationContent(); n.title = "وردك من القرآن"; n.body = "وردك اليوم: \(text)"; n.sound = .default; n.userInfo = ["open": "wird"]
            out.append(UNNotificationRequest(identifier: "wird-\(d)", content: n, trigger: UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: at), repeats: false)))
        }
        return out
    }
}

struct WirdSheet: View {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var store: Store
    @EnvironmentObject var prayers: Prayers
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var start = false
    @State private var pickTime = false
    @State private var t = Date()
    var body: some View {
        let done = Wird.doneToday, (f, _) = Wird.range
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("الورد اليومي").font(F.amiri(26)).foregroundStyle(c.text)
                VStack(alignment: .leading, spacing: 6) {
                    Text(done ? "وردك القادم" : "وردك اليوم").font(F.plex(12)).foregroundStyle(c.muted)
                    Text(Wird.text).font(F.plex(18, .bold)).foregroundStyle(c.text)
                    Text("الجزء \(Wird.juzOf(f).ar)" + (done ? " · أتممت ورد اليوم، بارك الله فيك" : "")).font(F.plex(12)).foregroundStyle(c.muted)
                    ProgressView(value: Double(Wird.percent), total: 100).tint(c.gold)
                    Text("أنجزت \(Wird.percent.ar)٪ من الختمة" + (Wird.khatmas > 0 ? " · الختمات: \(Wird.khatmas.ar)" : "")).font(F.plex(12)).foregroundStyle(c.muted)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [c.gold.opacity(0.16), c.surface], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.gold.opacity(0.4)))
                HStack(spacing: 10) {
                    GoldButton(title: "اقرأ الورد", icon: "book") {
                        if !Wird.on { Wird.setOn(Wird.remind) }
                        UserDefaults.standard.set(Wird.range.0, forKey: "mushafPage"); dismiss(); ui.drawer = false; ui.path.append(.mushaf)
                    }
                    if !done { GhostButton(title: "أتممت ورد اليوم", icon: "checkmark") { ui.say(Wird.done() ? "مبارك! أتممت ختم القرآن الكريم — تقبّل الله منك" : "تقبّل الله منك — حُفظ موضع وردك القادم") } }
                    else if Wird.canUndo { GhostButton(title: "تراجع عن «أتممت»") { Wird.undo() } }
                }
                Text("مقدار الورد كل يوم").font(F.plex(15, .bold)).padding(.top, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(Wird.amounts, id: \.0) { n, l in Pill(title: n == 1 ? l : "\(l) · \(n.ar) ص", on: Wird.pages == n) { Wird.setPages(n) } } }
                }
                Text("التذكير").font(F.plex(15, .bold)).padding(.top, 8)
                Toggle(isOn: Binding(get: { Wird.on && Wird.remind }, set: { v in
                    Wird.setOn(v); if v { Task { _ = await prayers.requestNotifications() } }
                    ui.say(v ? "سيصلك التذكير كل يوم الساعة \(timeText(Wird.time))" : "أُوقف تذكير الورد")
                })) { Text("ذكّرني بوردي كل يوم").font(F.plex(15)) }.tint(c.gold)
                DatePicker("وقت التذكير", selection: Binding(get: {
                    let hm = Wird.time.split(separator: ":").compactMap { Int($0) }
                    return Calendar.current.date(bySettingHour: hm.first ?? 21, minute: hm.last ?? 0, second: 0, of: Date()) ?? Date()
                }, set: { d in let x = Calendar.current.dateComponents([.hour, .minute], from: d); Wird.setTime(String(format: "%02d:%02d", x.hour ?? 21, x.minute ?? 0)) }), displayedComponents: .hourAndMinute)
                    .font(F.plex(15)).padding(12).background(RoundedRectangle(cornerRadius: 16).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 16).stroke(c.lineSoft))
                Button("ابدأ من موضع آخر") { start = true }.font(F.plex(14, .semibold)).foregroundStyle(c.gold).padding(.top, 6)
            }.padding(22)
        }
        .background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, .rightToLeft)
        .bzSheet(isPresented: $start) { WirdStart().presentationDetents([.large]) }
    }
    private func timeText(_ t: String) -> String {
        let hm = t.split(separator: ":").compactMap { Int($0) }; guard hm.count == 2 else { return t }
        return "\(((hm[0] + 11) % 12 + 1).ar):\(String(format: "%02d", hm[1]).map { c in c.isNumber ? Character(UnicodeScalar(0x660 + Int(String(c))!)!) : c }.map(String.init).joined()) \(hm[0] < 12 ? "ص" : "م")"
    }
}

private struct WirdStart: View {
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var page = "\(Wird.next)"
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack { TextField("رقم الصفحة (١–٦٠٤)", text: Binding(get: { page }, set: { page = String($0.filter(\.isNumber).prefix(3)) })).keyboardType(.numberPad)
                        Button("حفظ") { guard let p = Int(page), (1...604).contains(p) else { ui.say("اكتب رقم صفحة من ١ إلى ٦٠٤"); return }; Wird.setStart(p); ui.say("حُفظ موضع الورد"); dismiss() }.foregroundStyle(c.gold) }
                } header: { Text("رقم الصفحة") }.listRowBackground(c.surface)
                Section {
                    ForEach(0..<114, id: \.self) { i in
                        Button { Wird.setStart(Quran.surahPage[i]); ui.say("حُفظ موضع الورد: سورة \(Quran.surahs[i])"); dismiss() } label: {
                            HStack { Text((i + 1).ar).foregroundStyle(c.gold).frame(width: 34); Text("سورة \(Quran.surahs[i])").font(F.amiri(18)).foregroundStyle(c.text); Spacer(); Text("صفحة \(Quran.surahPage[i].ar)").font(F.plex(12)).foregroundStyle(c.muted) }
                        }
                    }
                } header: { Text("أو من أول سورة") }.listRowBackground(c.surface)
            }.bzList(c).navigationTitle("ابدأ وردك من…").navigationBarTitleDisplayMode(.inline)
        }.environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - «أصوات هادئة»

/// Rain, wind, waves and brown noise generated on the phone (no files), like the site's ambient sounds.
@MainActor
final class Ambient: ObservableObject {
    static let shared = Ambient()
    static let kinds: [(key: String, name: String, sub: String, icon: String)] = [("rain", "مطر", "زخات هادئة", "cloud.rain"), ("wind", "رياح", "نسيم في الصحراء", "wind"), ("waves", "أمواج", "بحر هادئ", "water.waves"), ("brown", "عزل الضوضاء", "ضوضاء بنية ناعمة", "waveform")]
    @Published private(set) var current = ""
    @Published var volume: Double = Double(Int(Store.shared.str("ambVol", "45")) ?? 45) { didSet { Store.shared.set("ambVol", "\(Int(volume))"); gen.target = volume / 100 } }
    private var engine: AVAudioEngine?
    private let gen = Gen()

    func toggle(_ k: String) { if current == k { stop() } else { start(k) } }
    func stop() { engine?.stop(); engine = nil; current = "" }
    func start(_ k: String) {
        stop()
        let e = AVAudioEngine()
        let sr = e.outputNode.outputFormat(forBus: 0).sampleRate > 0 ? e.outputNode.outputFormat(forBus: 0).sampleRate : 44100
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        gen.reset(k, sr); gen.target = volume / 100
        let g = gen
        let node = AVAudioSourceNode(format: fmt) { _, _, frames, abl -> OSStatus in
            let l = UnsafeMutableAudioBufferListPointer(abl)
            guard l.count >= 2, let a = l[0].mData?.assumingMemoryBound(to: Float.self), let b = l[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            g.render(a, b, Int(frames)); return noErr
        }
        e.attach(node); e.connect(node, to: e.mainMixerNode, format: fmt)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers]); try? AVAudioSession.sharedInstance().setActive(true)
        do { try e.start(); engine = e; current = k } catch { current = "" }
    }

    /// the generator (runs on the audio thread)
    final class Gen: @unchecked Sendable {
        var target = 0.45
        private var kind = "rain", sr = 44100.0, gain = 0.0, t = 0, drop = 0.0, nextDrop = 0
        private var brown = [0.0, 0.0], p0 = [0.0, 0.0], p1 = [0.0, 0.0], p2 = [0.0, 0.0], one = [0.0, 0.0]
        private var bp: [Biquad] = [], lp500: [Biquad] = [], hp: [Biquad] = [], lp900: [Biquad] = []
        func reset(_ k: String, _ s: Double) {
            kind = k; sr = s; gain = 0; t = 0; drop = 0; nextDrop = 0
            bp = (0..<2).map { _ in Biquad("bp", 2600, 0.4, s) }; lp500 = (0..<2).map { _ in Biquad("lp", 500, 0.7, s) }
            hp = (0..<2).map { _ in Biquad("hp", 3500, 0.7, s) }; lp900 = (0..<2).map { _ in Biquad("lp", 900, 0.7, s) }
            brown = [0, 0]; p0 = [0, 0]; p1 = [0, 0]; p2 = [0, 0]; one = [0, 0]
        }
        func render(_ a: UnsafeMutablePointer<Float>, _ b: UnsafeMutablePointer<Float>, _ n: Int) {
            for i in 0..<n {
                let time = Double(t) / sr
                if kind == "rain" && t >= nextDrop { drop = 0.25 + Double.random(in: 0..<0.35); nextDrop = t + Int(sr * (0.01 + Double.random(in: 0..<0.05))) }
                drop *= pow(0.9965, 22050 / sr)
                gain += (target - gain) * (6 / (sr * 2.5))
                for ch in 0..<2 {
                    let w = Double.random(in: -1..<1)
                    brown[ch] = (brown[ch] + 0.02 * w) / 1.02
                    p0[ch] = 0.99765 * p0[ch] + w * 0.099046; p1[ch] = 0.963 * p1[ch] + w * 0.2965164; p2[ch] = 0.57 * p2[ch] + w * 1.0526913
                    let pink = (p0[ch] + p1[ch] + p2[ch] + w * 0.1848) * 0.11
                    var v: Double
                    switch kind {
                    case "rain": v = bp[ch].f(w * 0.5) * 1.21 + lp500[ch].f(brown[ch] * 3.5) * 0.5 + hp[ch].f(w * 0.5) * drop
                    case "wind":
                        let fc = 650 + 380 * sin(2 * .pi * 0.07 * time + Double(ch)); let al = exp(-2 * .pi * fc / sr)
                        one[ch] = (1 - al) * pink + al * one[ch]; v = one[ch] * (0.7 + 0.35 * sin(2 * .pi * 0.11 * time)) * 2.4
                    case "waves": v = lp900[ch].f(pink) * max(0, 0.6 + 0.55 * sin(2 * .pi * 0.085 * time)) * 1.6
                    default: v = lp900[ch].f(brown[ch] * 3.5) * 0.9
                    }
                    let s = Float(max(-1, min(1, v * gain * 0.67)))
                    if ch == 0 { a[i] = s } else { b[i] = s }
                }
                t += 1
            }
        }
    }
    final class Biquad {
        private let b0, b1, b2, a1, a2: Double
        private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        init(_ type: String, _ f: Double, _ q: Double, _ sr: Double) {
            let w = 2 * .pi * f / sr, al = sin(w) / (2 * q), cw = cos(w), a0 = 1 + al
            switch type {
            case "bp": b0 = al / a0; b1 = 0; b2 = -al / a0
            case "hp": b0 = (1 + cw) / 2 / a0; b1 = -(1 + cw) / a0; b2 = (1 + cw) / 2 / a0
            default: b0 = (1 - cw) / 2 / a0; b1 = (1 - cw) / a0; b2 = (1 - cw) / 2 / a0
            }
            a1 = -2 * cw / a0; a2 = (1 - al) / a0
        }
        func f(_ x: Double) -> Double { let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2; x2 = x1; x1 = x; y2 = y1; y1 = y; return y }
    }
}

struct AmbientSheet: View {
    @ObservedObject private var amb = Ambient.shared
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("أصوات هادئة مع الاستماع").font(F.amiri(24)).foregroundStyle(c.text)
            Text("تعمل مع التلاوة وتساعد على التركيز وعزل الضوضاء حولك.").font(F.plex(14)).foregroundStyle(c.muted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Ambient.kinds, id: \.key) { k in
                    let on = amb.current == k.key
                    Button { amb.toggle(k.key) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Ico(name: k.icon, size: 30, color: on ? c.onGold : c.gold)
                            Text(k.name).font(F.plex(15, .bold)).foregroundStyle(on ? c.onGold : c.text).padding(.top, 6)
                            Text(k.sub).font(F.plex(12)).foregroundStyle(on ? c.onGold.opacity(0.8) : c.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(RoundedRectangle(cornerRadius: 20).fill(on ? AnyShapeStyle(c.goldGradient) : AnyShapeStyle(LinearGradient(colors: [c.surface2, c.surface], startPoint: .top, endPoint: .bottom))))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(on ? .clear : c.line))
                    }.buttonStyle(Press())
                }
            }
            HStack { Ico(name: "speaker.wave.2", size: 20).foregroundStyle(c.gold); Text("مستوى الصوت").font(F.plex(14, .medium)); Slider(value: $amb.volume, in: 5...100).tint(c.gold) }
            if !amb.current.isEmpty { GhostButton(title: "إيقاف الأصوات", icon: "stop.fill") { amb.stop(); dismiss() } }
            Spacer()
        }.padding(22).background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - الأذان

/// The adhan voices: the site's list (dashboard) or the two built-in ones.
@MainActor
enum Adhan {
    struct Voice: Hashable { let id: String, name: String, muezzin: String, url: String, fajr: String }
    static var voices: [Voice] {
        let site = (Repo.shared.data?.adhans ?? []).filter { !$0.url.isEmpty }.map { Voice(id: $0.id, name: $0.name, muezzin: $0.muezzin, url: $0.url, fajr: $0.fajr) }
        if !site.isEmpty { return site }
        return [Voice(id: "makkah", name: "أذان الحرم المكي", muezzin: "الشيخ هاشم السقاف", url: Repo.shared.data?.site.j["adhanUrl"].str.isEmpty == false ? Repo.shared.data!.site.j["adhanUrl"].str : "/Makaah Azan.mp3", fajr: ""),
                Voice(id: "madinah", name: "أذان الحرم النبوي", muezzin: "الشيخ محمد قصاص", url: "/wp-content/themes/bawazir-library-premium-v2/assets/adhan/madinah-qassas.mp3", fajr: "/wp-content/themes/bawazir-library-premium-v2/assets/adhan/madinah-qassas-fajr.mp3")]
    }
    static var voiceId: String { let v = Store.shared.str("adhanVoice", "makkah"); return voices.contains { $0.id == v } ? v : (voices.first?.id ?? "makkah") }
    static var voice: Voice? { voices.first { $0.id == voiceId } }
    static func setVoice(_ id: String) { Store.shared.set("adhanVoice", id); Task { await prepare(); Prayers.shared.schedule() } }
    static func url(_ fajr: Bool) -> URL? { guard let v = voice else { return nil }; return Repo.media(fajr && !v.fajr.isEmpty ? v.fajr : v.url) }

    /// iOS plays at most 30 s of a notification sound, from the app's Library/Sounds: the chosen voice is cut there once.
    static var soundsDir: URL { let d = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }
    static func soundName(_ fajr: Bool) -> String? {
        let n = "bz-\(voiceId.filter { $0.isLetter || $0.isNumber })\(fajr && !(voice?.fajr.isEmpty ?? true) ? "-f" : "").caf"
        return FileManager.default.fileExists(atPath: soundsDir.appendingPathComponent(n).path) ? n : nil
    }
    static func prepare() async {
        for fajr in [false, true] {
            if fajr && (voice?.fajr.isEmpty ?? true) { continue }
            let n = "bz-\(voiceId.filter { $0.isLetter || $0.isNumber })\(fajr ? "-f" : "").caf"
            let dst = soundsDir.appendingPathComponent(n)
            if FileManager.default.fileExists(atPath: dst.path) { continue }
            guard let u = url(fajr), let (tmp, r) = try? await URLSession.shared.download(from: u), (r as? HTTPURLResponse)?.statusCode == 200 else { continue }
            let src = tmp.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mp3"); try? FileManager.default.moveItem(at: tmp, to: src)
            await Task.detached { cut(src, dst) }.value
            try? FileManager.default.removeItem(at: src)
        }
    }
    /// the first 29 s, mono 22 kHz, with a short fade at the end
    nonisolated static func cut(_ src: URL, _ dst: URL) {
        guard let inF = try? AVAudioFile(forReading: src) else { return }
        let inFmt = inF.processingFormat
        let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 22050, channels: 1, interleaved: false)!
        let frames = AVAudioFrameCount(min(Double(inF.length), 29 * inFmt.sampleRate))
        guard let ib = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: frames), (try? inF.read(into: ib, frameCount: frames)) != nil,
              let conv = AVAudioConverter(from: inFmt, to: outFmt), let ob = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: AVAudioFrameCount(29 * 22050 + 1024)) else { return }
        var fed = false
        _ = conv.convert(to: ob, error: nil) { _, st in if fed { st.pointee = .endOfStream; return nil }; fed = true; st.pointee = .haveData; return ib }
        let n = Int(ob.frameLength), fade = min(n, 22050 * 3 / 2)
        if let p = ob.floatChannelData?[0] { for i in 0..<fade { p[n - 1 - i] *= Float(i) / Float(fade) } }
        let tmp = dst.deletingPathExtension().appendingPathExtension("tmp.caf")
        try? FileManager.default.removeItem(at: tmp)
        guard let outF = try? AVAudioFile(forWriting: tmp, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 22050, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false], commonFormat: .pcmFormatFloat32, interleaved: false),
              (try? outF.write(from: ob)) != nil else { return }
        try? FileManager.default.moveItem(at: tmp, to: dst)
    }
}

/// The whole adhan, played in the app (from the adhan notification, or «تجربة»).
@MainActor
final class AdhanPlayer: ObservableObject {
    static let shared = AdhanPlayer()
    @Published private(set) var playing = false
    private let player = AVPlayer()
    private var obs: NSObjectProtocol?
    func play(fajr: Bool) {
        guard let u = Adhan.url(fajr) else { return }
        AudioPlayer.shared.pause(); AyahPlayer.shared.stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default); try? AVAudioSession.sharedInstance().setActive(true)
        player.replaceCurrentItem(with: AVPlayerItem(url: u)); player.play(); playing = true
        if let o = obs { NotificationCenter.default.removeObserver(o) }
        obs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in Task { @MainActor in self?.playing = false } }
    }
    func stop() { player.pause(); player.replaceCurrentItem(with: nil); playing = false }
}

struct AdhanKey: Identifiable { let key: String; var id: String { key } }

/// «حان الآن موعد صلاة …» (opened from the adhan notification): stop the adhan or play it; «test» tries the chosen voice.
struct AdhanScreen: View {
    let key: String
    @ObservedObject private var ap = AdhanPlayer.shared
    @EnvironmentObject var prayers: Prayers
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var pulse = false
    private var test: Bool { key == "test" }
    private var name: String {
        if test { return "الأذان" }
        if key == "dhuhr" && Calendar.current.component(.weekday, from: Date()) == 6 { return "الجمعة" }
        return prayers.forDay().first { $0.key == key }?.name ?? ""
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            RadialGradient(colors: [c.gold.opacity(0.14), c.bg], center: .center, startRadius: 10, endRadius: 600).ignoresSafeArea()
            Button { ap.stop(); dismiss() } label: { Ico(name: "xmark", size: 21.6).foregroundStyle(c.text).frame(width: 44, height: 44) }.padding(12).accessibilityLabel("إغلاق")
            ScrollView {
                VStack(spacing: 6) {
                    Text(test ? "تجربة" : "حان الآن موعد صلاة").font(F.plex(18)).foregroundStyle(c.muted)
                    Text(name).font(F.amiri(56)).foregroundStyle(c.gold)
                    Text(prayers.place).font(F.plex(15)).foregroundStyle(c.muted).padding(.bottom, 30)
                    Button { if ap.playing { ap.stop() } else { ap.play(fajr: key == "fajr") } } label: {
                        Ico(name: ap.playing ? "pause.fill" : "play.fill", size: 52.8).foregroundStyle(c.onGold).frame(width: 120, height: 120).background(Circle().fill(c.goldGradient))
                            .scaleEffect(ap.playing && pulse ? 1.08 : 1)
                    }.buttonStyle(.plain).accessibilityLabel(ap.playing ? "إيقاف الأذان" : "تشغيل الأذان")
                    Text(ap.playing ? "إيقاف الأذان" : "تشغيل الأذان").font(F.plex(18, .semibold)).foregroundStyle(c.text).padding(.top, 20)
                    if let v = Adhan.voice { Text("\(v.name) · \(v.muezzin)").font(F.plex(14)).foregroundStyle(c.faint).padding(.top, 4) }
                    Hadith(words: "«إذا سَمِعتُمُ النِّداءَ، فقولوا مِثلَ ما يقولُ المُؤَذِّنُ»").padding(.top, 26)
                }.padding(24).frame(maxWidth: 440).frame(maxWidth: .infinity).padding(.top, 70)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
    }
}

struct Hadith: View {
    let words: String
    @Environment(\.pal) private var c
    var body: some View {
        VStack(spacing: 6) {
            (Text("قال رسول الله ﷺ: ").foregroundColor(c.gold) + Text(words).foregroundColor(c.text)).font(F.amiri(20, bold: false)).multilineTextAlignment(.center).lineSpacing(10)
                .padding(.horizontal, 20).padding(.vertical, 18).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 24).fill(c.gold.opacity(0.09))).overlay(RoundedRectangle(cornerRadius: 24).stroke(c.gold.opacity(0.35)))
            Text("متفق عليه").font(F.plex(13)).foregroundStyle(c.muted)
        }
    }
}
