import SwiftUI

/// «القرآن»: the mushaf, read-and-listen and the surah index in one place (like the Android app).
struct QuranView: View {
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    @State private var q = ""
    var body: some View {
        let mus = repo.data?.site.sec("mushaf") != false
        let last = Store.shared.str("lastRead").split(separator: ":").compactMap { Int($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if q.isEmpty {
                    if mus {
                        HStack(spacing: 10) {
                            BigTile(icon: "book", title: tr("المصحف الشريف"), sub: tr("صفحات مصحف المدينة")) { ui.path.append(.mushaf) }
                            BigTile(icon: "waveform", title: tr("اقرأ واستمع واحفظ"), sub: tr("الكلمات تضيء مع التلاوة")) { ui.path.append(.readIndex) }
                        }.padding(.horizontal, 16).padding(.vertical, 8)
                        WirdCard().padding(.horizontal, 16).padding(.vertical, 6)
                        QuranFullBanner().padding(.horizontal, 16).padding(.vertical, 4)
                    }
                    if last.count == 2, (1...114).contains(last[0]) {
                        Button { ui.path.append(.surah(last[0] * 1000 + last[1])) } label: {
                            HStack(spacing: 10) {
                                SiteIcon(name: "bookmark", size: 24, color: c.onGold)
                                VStack(alignment: .leading, spacing: 0) { Text(tr("تابع القراءة")).font(F.plex(12.5, .medium)); Text(tr("سورة {0} — الآية {1}", Quran.surahs[last[0] - 1], last[1].ar)).font(F.plex(14, .semibold)) }.foregroundStyle(c.onGold)
                                Spacer(); SiteIcon(name: "chev-l", size: 22, color: c.onGold)
                            }.padding(14).background(RoundedRectangle(cornerRadius: 18).fill(c.goldBrush))
                        }.buttonStyle(Press()).padding(.horizontal, 16).padding(.vertical, 4)
                    }
                }
                SectionHead(title: tr("فهرس السور"), kicker: tr("١١٤ سورة"))
                SearchField(text: $q, hint: tr("ابحث عن سورة باسمها أو رقمها")).padding(.horizontal, 16).padding(.vertical, 4)
                ForEach(Array(Quran.surahs.enumerated()).filter { q.isEmpty || QuranMeta.norm($0.element).contains(QuranMeta.norm(q.trimmingCharacters(in: .whitespaces))) || "\($0.offset + 1)" == q.trimmingCharacters(in: .whitespaces) }, id: \.offset) { i, n in
                    HStack(spacing: 14) {
                        SurahMedal(n: i + 1, size: 44)
                        VStack(alignment: .leading, spacing: 0) { Text(tr("سورة {0}", n)).font(F.amiri(20, bold: false)).foregroundStyle(c.text); Text(tr("{0} آية · صفحة {1}", Quran.ayahs[i].ar, Quran.surahPage[i].ar)).font(F.plex(12.5)).foregroundStyle(c.muted) }
                        Spacer()
                        if mus { Button { UserDefaults.standard.set(Quran.surahPage[i], forKey: "mushafPage"); ui.path.append(.mushaf) } label: { SiteIcon(name: "book", size: 22, color: c.faint).frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel(tr("افتح في المصحف")) }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10).contentShape(Rectangle())
                    .onTapGesture { ui.path.append(.surah(i + 1)) }
                }
            }.padding(.bottom, 24)
        }
    }
}

/// The surah number inside the eight-pointed star.
struct SurahMedal: View {
    let n: Int; var size: CGFloat = 40
    @Environment(\.pal) private var c
    var body: some View {
        ZStack {
            Canvas { ctx, s in ctx.stroke(star8(CGPoint(x: s.width / 2, y: s.height / 2), s.width / 2 - 1.5), with: .color(c.gold.opacity(0.75)), lineWidth: 1.3) }
            Text(n.ar).font(F.plex(size * 0.3, .bold)).foregroundStyle(c.gold)
        }.frame(width: size, height: size)
    }
}

struct BigTile: View {
    let icon: String, title: String, sub: String; let action: () -> Void
    @Environment(\.pal) private var c
    var body: some View {
        Button(action: action) {
            Panel(pad: 16) {
                Ico(name: icon, size: 30, color: c.gold)
                Text(title).font(F.plex(16, .semibold)).foregroundStyle(c.text).padding(.top, 10).lineLimit(1).minimumScaleFactor(0.8)
                Text(sub).font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(2)
            }
        }.buttonStyle(Press())
    }
}

/// «الورد اليومي» on the Quran page: today's portion, the khatma's progress, «اقرأ الورد» and «أتممت».
struct WirdCard: View {
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @EnvironmentObject var store: Store
    @Environment(\.pal) private var c
    @State private var msg: String?
    var body: some View {
        let on = Wird.on
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SiteIcon(name: "calendar", size: 20, color: c.gold).frame(width: 38, height: 38).background(Circle().fill(c.gold.opacity(0.18)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(tr("الورد اليومي")).font(F.plex(16, .semibold)).foregroundStyle(c.text)
                    Text(!on ? tr("اجعل لك وردًا ثابتًا من القرآن كل يوم") : Wird.doneToday ? tr("أتممت ورد اليوم — بارك الله فيك") : tr("ورد اليوم بانتظارك")).font(F.plex(12.5)).foregroundStyle(c.muted)
                }
                Spacer()
                if on { Button { ui.sheet = .wird } label: { SiteIcon(name: "gear", size: 22, color: c.muted).frame(width: 44, height: 44) }.accessibilityLabel(tr("إعدادات الورد")) }
            }
            if !on { GoldButton(title: tr("ابدأ وردك"), icon: "plus") { ui.sheet = .wird }.frame(maxWidth: .infinity).padding(.top, 12) }
            else {
                let (f, t) = Wird.range
                Text(Wird.doneToday ? tr("الورد القادم") : tr("ورد اليوم")).font(F.plex(12.5, .medium)).foregroundStyle(c.gold).padding(.top, 14)
                Text(f == t ? tr("صفحة {0}", f.ar) : tr("من صفحة {0} إلى {1}", f.ar, t.ar)).font(F.amiri(24, bold: false)).foregroundStyle(c.text)
                Text(tr("سورة {0} · الجزء {1}", Quran.surahs[Wird.surahOfPage(f) - 1], Wird.juzOf(f).ar)).font(F.plex(12.5)).foregroundStyle(c.muted)
                GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(c.surface3); Capsule().fill(c.goldBrush).frame(width: g.size.width * max(0.015, Double(Wird.percent) / 100)) } }.frame(height: 7).padding(.top, 12)
                HStack { Text(tr("الختمة {0}٪", Wird.percent.ar)).font(F.plex(11)).foregroundStyle(c.muted); Spacer(); if Wird.khatmas > 0 { Text(tr("ختمات: {0}", Wird.khatmas.ar)).font(F.plex(11)).foregroundStyle(c.gold) } }.padding(.top, 6)
                HStack(spacing: 10) {
                    GoldButton(title: tr("اقرأ الورد"), icon: "book") { UserDefaults.standard.set(f, forKey: "mushafPage"); ui.path.append(.mushaf) }.frame(maxWidth: .infinity)
                    if !Wird.doneToday { GhostButton(title: tr("أتممت"), icon: "check") { msg = Wird.done() ? tr("مبارك! أتممت ختم القرآن الكريم — تقبّل الله منك") : tr("تقبّل الله منك — حُفظ موضع وردك القادم") }.frame(maxWidth: .infinity) }
                    else if Wird.canUndo { GhostButton(title: tr("تراجع")) { Wird.undo() }.frame(maxWidth: .infinity) }
                }.padding(.top, 12)
                if let msg { Text(msg).font(F.plex(12.5)).foregroundStyle(c.gold).padding(.top, 8) }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [c.gold.opacity(0.17), c.surface, c.surface], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(c.gold.opacity(0.38)))
    }
}

/// Surah reader: every ayah with its audio (any reciter), continuous play; a long press for tafsir and more.
struct SurahView: View {
    let s0: Int
    init(s: Int) { s0 = s }
    @EnvironmentObject var repo: Repo
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @EnvironmentObject var ayah: AyahPlayer
    @EnvironmentObject var store: Store
    @Environment(\.pal) private var c
    @State private var ayahs: [String]?
    /// the meaning under each ayah, in the app language (none in Arabic)
    @State private var meaning: [Int: String] = [:]
    @State private var failed = false
    @AppStorage("qsize") private var size = 26.0
    @State private var cont = true
    @State private var act: Int?
    @State private var tafsir: Int?
    private var s: Int { s0 > 1000 ? s0 / 1000 : s0 }
    private var start: Int { s0 > 1000 ? s0 % 1000 : 1 }
    private var rv: String {
        let opts = ayah.options(1, 1).map(\.value)
        let p = store.ayahReciter.isEmpty ? (repo.data?.site.dailyReciter ?? "yasser") : store.ayahReciter
        return opts.contains(p) ? p : (opts.contains("yasser") ? "yasser" : opts.first ?? "yasser")
    }
    var body: some View {
        let cur: Int? = ayah.key.flatMap { k in k.hasPrefix("\(s):") ? Int(k.dropFirst("\(s):".count).prefix { $0 != "|" }) : nil }
        let opts = ayah.options(s, 1)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                OptMenu(label: "", value: rv, opts: opts.map { ($0.value, $0.label + ($0.ok ? "" : tr(" (غير متاحة)"))) }) { store.ayahReciter = $0; ayah.stop() }.frame(maxWidth: .infinity, alignment: .leading)
                Chip(text: nil, icon: "queue", on: cont) { cont.toggle(); ui.say(cont ? tr("تشغيل متتابع للآيات") : tr("تشغيل آية واحدة")) }
                Chip(text: nil, icon: "zoom-out") { size = max(18, size - 2) }
                Chip(text: nil, icon: "zoom-in") { size = min(44, size + 2) }
            }.padding(.horizontal, 12).padding(.vertical, 6)
            ScrollViewReader { sp in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Panel(pad: 18) {
                            VStack(spacing: 0) {
                                Text(tr("سورة {0}", Quran.surahs[s - 1])).font(F.amiri(30)).foregroundStyle(c.goldBrushV)
                                Text(tr("{0} آية · الجزء {1}", Quran.ayahs[s - 1].ar, Quran.juzOfPage(Quran.surahPage[s - 1]).ar)).font(F.plex(12.5)).foregroundStyle(c.muted)
                                Ornament().padding(.vertical, 8)
                                if s != 1 && s != 9 { Text(tr("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")).font(F.quran(24)).foregroundStyle(c.text) }
                                HStack(spacing: 8) {
                                    Chip(text: cur != nil && ayah.playing ? tr("إيقاف") : tr("استمع للسورة"), icon: cur != nil && ayah.playing ? "pause" : "play") { if cur != nil && ayah.playing { ayah.stop() } else { playFrom(1, sp) } }
                                    if repo.data?.site.sec("mushaf") != false { Chip(text: tr("في المصحف"), icon: "book") { UserDefaults.standard.set(Quran.surahPage[s - 1], forKey: "mushafPage"); ui.path.append(.mushaf) } }
                                }.padding(.top, 10)
                            }.frame(maxWidth: .infinity)
                        }.padding(.bottom, 10)
                        if let ayahs {
                            ForEach(1...ayahs.count, id: \.self) { a in
                                let on = cur == a
                                Text("\(ayahClean(s, a, ayahs[a - 1])) \(orn(a.qar))").font(F.quran(size)).foregroundStyle(on ? c.gold : c.text).lineSpacing(size * 0.75).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading).environment(\.layoutDirection, .rightToLeft).padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 18).fill(on ? c.gold.opacity(0.13) : .clear)).padding(.vertical, 3)
                                    .contentShape(Rectangle())
                                    .onTapGesture { if on { ayah.stop() } else { playFrom(a, sp) } }
                                    .onLongPressGesture { act = a }
                                    .id(a)
                                if let m = meaning[a] {
                                    Text(m).font(F.plex(15)).foregroundStyle(c.muted).lineSpacing(5).multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 8)
                                        .environment(\.layoutDirection, L.dir)
                                }
                            }
                            if !meaning.isEmpty, let q = L.quran[L.code] { Text(tr("ترجمة المعاني") + ": " + q.1).font(F.plex(11.5)).foregroundStyle(c.faint).frame(maxWidth: .infinity).padding(.top, 10) }
                            Text(tr("اضغط على الآية لسماعها، واضغط مطوّلًا للتفسير والمزيد")).font(F.plex(11)).foregroundStyle(c.faint).frame(maxWidth: .infinity).padding(.top, 14)
                        } else {
                            Group { if failed { Text(tr("تعذّر تحميل السورة — تحقق من الاتصال")).font(F.plex(14)).foregroundStyle(c.muted) } else { ProgressView().tint(c.gold) } }.padding(40)
                        }
                    }.padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 32)
                }
                .task(id: s) { if let q = L.quran[L.code] { Task { meaning = await repo.tafsir(s, edition: q.0) } }; ayahs = await repo.surahText(s); failed = ayahs == nil; if start > 1 { try? await Task.sleep(nanoseconds: 300_000_000); sp.scrollTo(start, anchor: .top) } }
            }
        }
        .onDisappear { ayah.stop() }
        .bzSheet(item: Binding(get: { act.map(IntBox.init(v:)) }, set: { act = $0?.v })) { b in
            let a = b.v, text = ayahClean(s, a, ayahs?[safe: a - 1] ?? ""), cite = tr("﴿{0}﴾ [سورة {1}: {2}]", text, Quran.surahs[s - 1], a)
            MenuSheet(title: tr("سورة {0} — الآية {1}", Quran.surahs[s - 1], a.ar)) {
                MenuRow(icon: "play", title: tr("استمع للآية")) { act = nil; ayah.play(rv, s, a) }
                MenuRow(icon: "scroll", title: tr("التفسير")) { act = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { tafsir = a } }
                MenuRow(icon: "copy", title: tr("نسخ")) { UIPasteboard.general.string = cite; ui.say(tr("نُسخت الآية")); act = nil }
                MenuRow(icon: "share", title: tr("مشاركة")) { act = nil; share("\(cite)\n\(Repo.site)") }
                MenuRow(icon: "bookmark", title: tr("علامة القراءة هنا")) { Store.shared.set("lastRead", "\(s):\(a)"); ui.say(tr("حُفظت علامة القراءة")); act = nil }
                if repo.data?.site.sec("maker") != false { MenuRow(icon: "image", title: tr("صمّمها")) { act = nil; ui.path.append(.maker(s, a)) } }
                if repo.data?.site.sec("community") != false { MenuRow(icon: "chat", title: tr("انشرها في المجتمع")) { act = nil; ui.path.append(.compose("ayah:\(s):\(a)|\(rv)")) } }
            }.presentationDetents([.medium, .large])
        }
        .bzSheet(item: Binding(get: { tafsir.map(IntBox.init(v:)) }, set: { tafsir = $0?.v })) { b in
            TafsirSheet(s: s, a: b.v, text: ayahClean(s, b.v, ayahs?[safe: b.v - 1] ?? "")).presentationDetents([.medium, .large])
        }
    }
    private func playFrom(_ a: Int, _ sp: ScrollViewProxy) {
        Store.shared.set("lastRead", "\(s):\(a)")
        AudioPlayer.shared.pause()
        ayah.play(rv, s, a) { if cont && a < Quran.ayahs[s - 1] { playFrom(a + 1, sp) } }
        withAnimation { sp.scrollTo(a, anchor: .center) }
    }
}
struct IntBox: Identifiable { let v: Int; var id: Int { v } }
