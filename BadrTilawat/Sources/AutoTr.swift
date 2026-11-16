import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Arabic text written by people (recitation titles and their details) in the app's language, translated on the phone
/// itself by Apple's translator (iOS 18 and later) and kept, so each text is translated once.
@MainActor
final class AutoTr: ObservableObject {
    static let shared = AutoTr()
    /// goes up when new translations arrive (the views showing titles then redraw)
    @Published private(set) var rev = 0
    @Published private(set) var pending = 0
    private var cache: [String: String] = [:]
    private var lang = ""
    private var queue: [String] = []
    private var asked = Set<String>()
    private static let arabic = try! NSRegularExpression(pattern: "[\\u0600-\\u06FF]")
    static func hasArabic(_ s: String) -> Bool { arabic.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }

    private func load() {
        guard lang != L.code else { return }
        lang = L.code; queue = []; asked = []
        cache = (UserDefaults.standard.dictionary(forKey: "autoTr_" + lang) as? [String: String]) ?? [:]
    }
    /// the translation, or the text itself until it arrives (and it is asked for)
    func t(_ s: String) -> String {
        if L.ar || s.isEmpty || !AutoTr.hasArabic(s) { return s }
        load()
        if let v = cache[s] { return v }
        if !asked.contains(s) {
            asked.insert(s); queue.append(s)
            DispatchQueue.main.async { self.pending = self.queue.count }
        }
        return s
    }
    func takeBatch() -> [String] { let b = Array(queue.prefix(60)); queue.removeFirst(b.count); pending = queue.count; return b }
    func store(_ out: [String: String]) {
        guard !out.isEmpty else { return }
        for (k, v) in out where !v.isEmpty { cache[k] = v }
        if cache.count > 3000 { cache = out }
        UserDefaults.standard.set(cache, forKey: "autoTr_" + lang)
        rev += 1
    }
}

/// Runs the translator for the queued texts (placed once, on the app's root).
struct AutoTrHost: ViewModifier {
    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *) { content.modifier(AutoTrRunner()) } else { content }
        #else
        content
        #endif
    }
}

#if canImport(Translation)
@available(iOS 18.0, *)
private struct AutoTrRunner: ViewModifier {
    @ObservedObject private var at = AutoTr.shared
    @State private var config: TranslationSession.Configuration?
    @State private var target = ""
    func body(content: Content) -> some View {
        content
            .translationTask(config) { session in
                while true {
                    let batch = await MainActor.run { AutoTr.shared.takeBatch() }
                    if batch.isEmpty { break }
                    let reqs = batch.enumerated().map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: "\($0.offset)") }
                    guard let res = try? await session.translations(from: reqs) else { break }
                    var out: [String: String] = [:]
                    for r in res { if let i = Int(r.clientIdentifier ?? ""), i < batch.count { out[batch[i]] = r.targetText } }
                    await MainActor.run { AutoTr.shared.store(out) }
                }
            }
            .onChange(of: at.pending) { n in if n > 0 { run() } }
            .onAppear { if at.pending > 0 { run() } }
    }
    private func run() {
        // a moment's wait gathers a whole screen of titles into one batch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard !L.ar else { return }
            if config == nil || target != L.code {
                target = L.code
                config = TranslationSession.Configuration(source: Locale.Language(identifier: "ar"), target: Locale.Language(identifier: L.code))
            } else { config?.invalidate() }
        }
    }
}
#endif
