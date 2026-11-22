import SwiftUI

/// «الجديد في بدر التلاوات»: shown once after an update (right after the intro), in the user's theme — as on Android. Set in
/// the dashboard (التحكم في التطبيق ← ما الجديد): on/off, until when, «اعرضها تاني للكل», new installs too, the recitations,
/// the reciters and which cards. «متابعة» fades it out; it never shows again for this version (and this dashboard round).
@MainActor
enum WhatsNew {
    private static func w(_ s: Site?) -> J? { guard let s else { return nil }; let j = s.j["app"]["whatsNew"]; return j.isNull ? nil : j }
    /// The round of «ما الجديد» this build carries: changed only for an update that has a new screen (a bug-fix update keeps
    /// it, so the screen does not come again) — the same round as on Android. The dashboard's «إعادة العرض للجميع» adds its count.
    static let round = "2.10.95"
    private static func key(_ s: Site?) -> String { round + "#" + String(w(s)?["rev"].int ?? 0) }
    static func shouldShow(_ s: Site?, existing: Bool) -> Bool {
        guard let j = w(s), j["enabled"].bool(true) else { return false }
        let until = j["until"].str
        if !until.isEmpty { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; if f.string(from: Date()) > until { return false } }
        if !existing && !j["newUsers"].bool() { return false }
        return UserDefaults.standard.string(forKey: "wnSeen") != key(s)
    }
    static func seen(_ s: Site?) { UserDefaults.standard.set(key(s), forKey: "wnSeen") }
    static func card(_ s: Site?, _ k: String) -> Bool { w(s)?["cards"][k].bool(true) ?? true }
    static func collections(_ s: Site?) -> [TrackCollection] {
        guard let all = s?.collections else { return [] }
        let picked = ["col1", "col2"].compactMap { k -> TrackCollection? in let id = w(s)?[k].str ?? ""; return id.isEmpty ? nil : all.first { $0.id == id } }
        if !picked.isEmpty { return picked }
        var out: [TrackCollection] = []
        if let a = all.last(where: { $0.name.contains("1425") || $0.name.contains("١٤٢٥") }) { out.append(a) }
        if let b = all.last(where: { $0.name.contains("فجر") }), !out.contains(b) { out.append(b) }
        return out
    }
    static func reciters(_ s: Site?) -> [Reciter] {
        guard let all = Repo.shared.data?.reciters else { return [] }
        let picked = ["rec1", "rec2"].compactMap { k -> Reciter? in let id = w(s)?[k].str ?? ""; return id.isEmpty ? nil : all.first { $0.id == id } }
        if !picked.isEmpty { return picked }
        return [all.first { $0.name.contains("الأنصاري") }, all.first { $0.name.contains("الجريذي") }].compactMap { $0 }
    }
    /// «الشيخ ياسر بن راشد الدوسري» → «ياسر بن راشد الدوسري» (the card says «مشايخ جدد» already)
    static func bare(_ n: String) -> String { n.replacingOccurrences(of: "^\\s*(الشيخ|القارئ|الإمام|فضيلة)\\s+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
}

struct WhatsNewView: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var prayers: Prayers
    @Environment(\.pal) private var c
    let done: (_ go: (() -> Void)?) -> Void
    @State private var shown = 1.0
    @State private var leaving = false
    @State private var ringSilent = false

    private func leave(_ go: (() -> Void)? = nil) {
        guard !leaving else { return }; leaving = true; WhatsNew.seen(repo.data?.site)
        withAnimation(.easeInOut(duration: 0.7)) { shown = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { done(go) }
    }
    private func card<V: View>(pad: CGFloat = 20, @ViewBuilder _ v: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) { v() }.padding(pad).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(c.gold.opacity(0.18)))
    }
    private func eyebrow(_ t: String) -> some View { Text(t).font(F.plex(12.5, .semibold)).foregroundStyle(c.gold) }
    private func body(_ t: String, _ size: CGFloat = 14) -> some View { Text(t).font(F.plex(size)).foregroundStyle(c.muted).lineSpacing(size * 0.6).fixedSize(horizontal: false, vertical: true) }

    var body: some View {
        let s = repo.data?.site
        ZStack(alignment: .top) {
            c.bg.ignoresSafeArea()
            RadialGradient(colors: [c.gold.opacity(0.24), c.gold.opacity(0.05), .clear], center: .top, startRadius: 0, endRadius: 300).frame(height: 420).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    head
                    recitations(s)
                    reciters(s)
                    if WhatsNew.card(s, "mushaf") { mushaf }
                    if WhatsNew.card(s, "silent") && prayers.ringSilentAvailable { silent }
                    pair(s)
                    if WhatsNew.card(s, "colors") { colors }
                    GoldButton(title: tr("متابعة")) { leave() }.frame(maxWidth: .infinity).padding(.top, 8)
                }.padding(.horizontal, 16).padding(.top, 32).padding(.bottom, 24)
            }
        }
        .opacity(shown).environment(\.layoutDirection, L.dir)
        .onAppear { ringSilent = prayers.ringSilent }
    }
    private var head: some View {
        VStack(spacing: 12) {
            Image("Logo").resizable().scaledToFit().frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 21))
                .padding(2).background(RoundedRectangle(cornerRadius: 23).fill(LinearGradient(colors: [c.gold2, c.gold.mix(.black, 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            Text(tr("الإصدار {0}", L.digits(WhatsNew.round))).font(F.plex(13, .semibold)).foregroundStyle(c.gold2)
                .padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(c.gold.opacity(0.08))).overlay(Capsule().strokeBorder(c.gold.opacity(0.35)))
            Text(tr("الجديد في بدر التلاوات")).font(F.amiri(32)).foregroundStyle(c.text).multilineTextAlignment(.center)
            body(tr("جمعنا لك أهم ما تغيّر في هذا التحديث."), 15)
        }.frame(maxWidth: .infinity).padding(.bottom, 16)
    }
    @ViewBuilder private func recitations(_ s: Site?) -> some View {
        let cols = WhatsNew.collections(s)
        if !cols.isEmpty {
            card {
                eyebrow(tr("تلاوات جديدة")); Text(tr("أُضيفت إلى التلاوات")).font(F.amiri(26)).foregroundStyle(c.text)
                HStack(spacing: 10) { ForEach(cols) { col in tile(col) } }.padding(.top, 10)
            }
        }
    }
    private func tile(_ col: TrackCollection) -> some View {
        let r = repo.reciter(col.reciterId)
        return Button { leave { UIState.shared?.go(.collection(col.id)) } } label: {
            ZStack(alignment: .bottom) {
                RemoteImage(raw: col.cover.isEmpty ? r?.image : col.cover).frame(maxWidth: .infinity).frame(height: 236).clipped()
                LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.88), location: 1)], startPoint: .top, endPoint: .bottom)
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(col.name).font(F.amiri(20)).foregroundStyle(.white).lineLimit(1)
                        Text(WhatsNew.bare(r?.shown ?? "")).font(F.plex(11.5)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    SiteIcon(name: "play", size: 14, color: c.onGold).frame(width: 34, height: 34).background(Circle().fill(c.gold))
                }.padding(12)
            }
            .overlay(alignment: .topLeading) { Text(tr("جديد")).font(F.plex(11, .bold)).foregroundStyle(.white).padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(.black.opacity(0.45))).padding(10) }
            .clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08)))
        }.buttonStyle(.plain)
    }
    @ViewBuilder private func reciters(_ s: Site?) -> some View {
        let recs = WhatsNew.reciters(s)
        if !recs.isEmpty {
            card(pad: 14) {
                eyebrow(tr("مشايخ جدد")).padding(.horizontal, 6).padding(.top, 6)
                ForEach(Array(recs.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Hairline(inset: 70) }
                    HStack(spacing: 14) {
                        RemoteImage(raw: r.image).frame(width: 52, height: 52).clipShape(Circle())
                            .padding(2).background(Circle().fill(LinearGradient(colors: [c.gold2, c.gold.mix(.black, 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(WhatsNew.bare(r.shown)).font(F.amiri(18)).foregroundStyle(c.text).lineLimit(1)
                            Text(tr("تلاواته الآن في قسم التلاوات")).font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button { leave { UIState.shared?.go(.reciter(r.id)) } } label: {
                            HStack(spacing: 6) { SiteIcon(name: "play", size: 12, color: c.gold2); Text(tr("استمع")).font(F.plex(13, .semibold)).foregroundStyle(c.gold2) }
                                .padding(.horizontal, 14).frame(height: 36).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.gold.opacity(0.3)))
                        }.buttonStyle(.plain)
                    }.padding(.horizontal, 6).frame(height: 72)
                }
            }
        }
    }
    private var mushaf: some View {
        card {
            eyebrow(tr("المصحف")); Text(tr("المصحف يتابعك")).font(F.amiri(26)).foregroundStyle(c.text)
            body(tr("مع التلاوة تنزل الصفحة وحدها إلى الآية التي يقرؤها الشيخ، فلا تحتاج أن تبحث عنها."))
            let ink = Color(red: 0.16, green: 0.14, blue: 0.09)
            (Text(verbatim: "\u{202B}وَٱلَّيۡلِ إِذَا عَسۡعَسَ \(ReadText.mark("١٧")) وَٱلصُّبۡحِ إِذَا تَنَفَّسَ \(ReadText.mark("١٨")) ").foregroundColor(ink.opacity(0.55))
             + Text(verbatim: "إِنَّهُۥ لَقَوۡلُ رَسُولࣲ كَرِيمࣲ \(ReadText.mark("١٩"))").foregroundColor(ink).underline(true, color: Color(red: 0.79, green: 0.64, blue: 0.36))
             + Text(verbatim: " ذِي قُوَّةٍ عِندَ ذِي ٱلۡعَرۡشِ مَكِينࣲ \(ReadText.mark("٢٠"))\u{202C}").foregroundColor(ink.opacity(0.55)))
                .font(F.quran(18)).multilineTextAlignment(.center).lineSpacing(10).frame(maxWidth: .infinity).padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.957, green: 0.925, blue: 0.847))).padding(.top, 10)
        }
    }
    private var silent: some View {
        card {
            eyebrow(tr("الأذان")); Text(tr("يرنّ حتى في الصامت")).font(F.amiri(26)).foregroundStyle(c.text)
            body(tr("اختر الصلاة، فيرنّ أذانها بالصوت الذي اخترته ولو كان الهاتف على الصامت، وتوقفه بلمسة."))
            Toggle(isOn: Binding(get: { ringSilent }, set: { v in ringSilent = v; Task { let ok = await prayers.setRingSilent(v); if v && !ok { ringSilent = false } } })) {
                HStack(spacing: 12) {
                    SiteIcon(name: "bell", size: 22, color: c.gold)
                    VStack(alignment: .leading, spacing: 0) { Text(tr("يرنّ حتى في الصامت")).font(F.plex(15, .bold)).foregroundStyle(c.text); Text(tr("بصوت الأذان المختار")).font(F.plex(12.5)).foregroundStyle(c.muted) }
                }
            }.tint(c.gold).padding(.horizontal, 14).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 16).fill(c.surface2)).padding(.top, 10)
        }
    }
    @ViewBuilder private func pair(_ s: Site?) -> some View {
        let two: [(String, String, String)] = [WhatsNew.card(s, "power") ? ("power", tr("زر الباور يوقفه"), tr("ضغطة على زر الباور توقف الأذان، وقفل الشاشة أو فتحها لا يقطعه.")) : nil,
                                                WhatsNew.card(s, "night") ? ("moon", tr("قيام الليل والضحى"), tr("تذكير بالثلث الأخير من الليل، وآخر بوقت صلاة الضحى.")) : nil].compactMap { $0 }
        if !two.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                ForEach(two, id: \.0) { ic, t, d in
                    VStack(alignment: .leading, spacing: 8) {
                        Group { if ic == "power" { Image(systemName: "power").font(.system(size: 19, weight: .semibold)).foregroundStyle(c.gold2) } else { SiteIcon(name: ic, size: 22, color: c.gold2) } }
                            .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 14).fill(c.gold.opacity(0.12)))
                        Text(t).font(F.amiri(20)).foregroundStyle(c.text)
                        body(d, 13)
                    }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 24).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(c.gold.opacity(0.18)))
                }
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
    private var colors: some View {
        let five = [("fajr", tr("الفجر")), ("dhuhr", tr("الظهر")), ("asr", tr("العصر")), ("maghrib", tr("المغرب")), ("isha", tr("العشاء"))]
        let nk = prayers.next()?.key
        return card {
            eyebrow(tr("مواقيت الصلاة")); Text(tr("لكل صلاة لونها")).font(F.amiri(24)).foregroundStyle(c.text)
            body(tr("كل صلاة بلون سمائها، والصلاة القادمة أوضح من غيرها، والضحى وقيام الليل في سطر تحتها."), 13.5)
            HStack(spacing: 6) {
                ForEach(five, id: \.0) { k, _ in
                    RoundedRectangle(cornerRadius: 12).fill(PrayerSky.swatch(k)).frame(height: 60).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.07)))
                        .padding(k == nk ? 2 : 0).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(k == nk ? c.gold2.opacity(0.7) : .clear))
                }
            }.padding(.top, 10)
            HStack(spacing: 6) { ForEach(five, id: \.0) { k, n in Text(n).font(F.plex(11, k == nk ? .bold : .medium)).foregroundStyle(k == nk ? c.gold2 : c.muted).frame(maxWidth: .infinity).lineLimit(1) } }
            Hairline().padding(.vertical, 4)
            HStack(spacing: 8) {
                ForEach([("duha", tr("صلاة الضحى")), ("qiyam", tr("قيام الليل"))], id: \.0) { k, n in
                    HStack(spacing: 10) { RoundedRectangle(cornerRadius: 7).fill(PrayerSky.swatch(k)).frame(width: 22, height: 22); Text(n).font(F.plex(13)).foregroundStyle(c.text).lineLimit(1); Spacer(minLength: 0) }
                        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.2)))
                }
            }
        }
    }
}
