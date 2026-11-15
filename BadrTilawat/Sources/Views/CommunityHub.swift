import SwiftUI
import AVKit

// MARK: - avatar, badges, rich text (like the site and the Android app)

struct Avatar: View {
    let m: Member?; var size: CGFloat = 46
    @Environment(\.pal) private var c
    var body: some View {
        ZStack {
            Circle().fill(c.goldBrush)
            if let a = m?.avatar, !a.isEmpty { RemoteImage(raw: a).clipShape(Circle()) }
            else { Text(String(((m?.name.isEmpty == false ? m?.name : m?.handle) ?? "?").trimmingCharacters(in: .whitespaces).prefix(1))).font(F.plex(size * 0.42, .bold)).foregroundStyle(c.onGold) }
        }.frame(width: size, height: size)
    }
}

/// The site's badge icons and colours (inc/icons.php + .cm-badge).
let BADGE_LOOK: [String: (String, Color)] = ["owner": ("owner", Color(hex: 0xFFB8862B)), "admin": ("b-admin", Color(hex: 0xFFC8473D)), "mod": ("b-mod", Color(hex: 0xFF2E9E6A)),
    "official": ("verified", Color(hex: 0xFFD4A72C)), "verified": ("verified", Color(hex: 0xFF1D9BF0)), "reciter": ("b-reciter", Color(hex: 0xFF12968F)),
    "teacher": ("b-teacher", Color(hex: 0xFF9A6A35)), "supporter": ("b-supporter", Color(hex: 0xFFE0507A)), "founder": ("b-founder", Color(hex: 0xFFE39A1B))]
func badgesOf(_ m: Member?) -> [String] { guard let m else { return [] }; return Community.badges.map(\.0).filter { m.badges.contains($0) } }
struct BadgeIcons: View {
    let m: Member?; var max = 3; var size: CGFloat = 18
    var body: some View {
        HStack(spacing: 3) { ForEach(badgesOf(m).prefix(max), id: \.self) { k in if let l = BADGE_LOOK[k] { SiteIcon(name: l.0, size: k == "owner" ? size * 1.12 : size, color: l.1).accessibilityLabel(Community.badges.first { $0.0 == k }?.1 ?? "") } } }
    }
}
struct BadgeChips: View {
    let m: Member?
    @Environment(\.pal) private var c
    var body: some View {
        let l = badgesOf(m)
        if !l.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(l, id: \.self) { k in
                    let col = BADGE_LOOK[k]?.1 ?? c.gold
                    HStack(spacing: 5) { SiteIcon(name: BADGE_LOOK[k]?.0 ?? "verified", size: 16, color: col); Text(Community.badges.first { $0.0 == k }?.1 ?? "").font(F.plex(12.5, .bold)).foregroundStyle(c.text) }
                        .padding(.leading, 8).padding(.trailing, 10).padding(.vertical, 3).background(Capsule().fill(col.opacity(0.16)))
                }
            }.padding(.top, 8)
        }
    }
}

/// Text with @mentions, #tags and links (tappable).
struct RichText: View {
    let t: String; var size: CGFloat = 16
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    var body: some View {
        Text(attr).font(F.plex(size)).foregroundStyle(c.text).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { u in
                if u.scheme == "bzu" { ui.path.append(.user(u.host ?? "")); return .handled }
                if u.scheme == "bzt" { ui.path.append(.cm("search:#" + (u.host?.removingPercentEncoding ?? ""))); return .handled }
                return .systemAction
            })
    }
    private var attr: AttributedString {
        let rx = try! NSRegularExpression(pattern: "(https?://[^\\s]+[^\\s.,،؛:!?)\\]])|(^|[^\\w&])@([a-zA-Z0-9_]{3,20})|(^|[^\\p{L}\\p{N}_&])#([\\p{L}\\p{N}_]{2,40})")
        let ns = t as NSString
        var out = AttributedString(); var i = 0
        for m in rx.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            out += AttributedString(ns.substring(with: NSRange(location: i, length: m.range.location - i))); i = m.range.location + m.range.length
            var link: AttributedString
            if m.range(at: 1).location != NSNotFound {
                let u = ns.substring(with: m.range(at: 1))
                link = AttributedString(String(u.replacingOccurrences(of: "^https?://(www\\.)?", with: "", options: .regularExpression).prefix(40)) + (u.count > 48 ? "…" : "")); link.link = URL(string: u)
            } else if m.range(at: 3).location != NSNotFound {
                out += AttributedString(ns.substring(with: m.range(at: 2)))
                let h = ns.substring(with: m.range(at: 3)); link = AttributedString("\u{2066}@\(h)\u{2069}"); link.link = URL(string: "bzu://\(h.lowercased())")
            } else {
                out += AttributedString(ns.substring(with: m.range(at: 4)))
                let h = ns.substring(with: m.range(at: 5)); link = AttributedString("#\(h)"); link.link = URL(string: "bzt://\(h.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? h)")
            }
            link.foregroundColor = c.gold
            out += link
        }
        out += AttributedString(ns.substring(from: i))
        return out
    }
}

/// An ayah or a recitation attached to a post.
struct PostEmbed: View {
    let e: String; var compact = false
    @EnvironmentObject var ayah: AyahPlayer
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    @State private var text: String?
    var body: some View {
        if let m = e.range(of: "^ayah:(\\d+):(\\d+)", options: .regularExpression) {
            let sa = e[m].dropFirst(5).split(separator: ":").compactMap { Int($0) }
            let rv = e.contains("|") ? String(e.split(separator: "|", maxSplits: 1)[1]) : "yasser"
            let s = max(1, min(114, sa.first ?? 1)), a = sa.count > 1 ? sa[1] : 1
            let on = ayah.key == "\(s):\(a)|\(rv)" && ayah.playing
            VStack(spacing: 8) {
                Text(text.map { "﴿\($0)﴾" } ?? "…").font(F.quran(compact ? 18 : 21)).foregroundStyle(c.text).lineSpacing(compact ? 14 : 18).multilineTextAlignment(.center).lineLimit(compact ? 4 : nil).frame(maxWidth: .infinity)
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tr("سورة {0} — الآية {1}", Quran.surahs[s - 1], a.ar)).font(F.plex(14, .semibold)).foregroundStyle(c.gold)
                        let l = ayah.label(rv, s, a); if !l.isEmpty { Text(tr("بصوت {0}", l)).font(F.plex(11)).foregroundStyle(c.muted) }
                    }
                    Spacer()
                    Button { if on { ayah.stop() } else { ayah.play(rv, s, a) } } label: { SiteIcon(name: on ? "pause" : "play", size: 20, color: c.onGold).frame(width: 38, height: 38).background(Circle().fill(c.goldBrush)) }.buttonStyle(.plain).accessibilityLabel(tr("استمع للآية"))
                }
            }
            .padding(14).background(RoundedRectangle(cornerRadius: 18).fill(c.gold.opacity(0.07))).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.gold.opacity(0.35)))
            .padding(.top, 8)
            .task(id: e) { text = ayahClean(s, a, (await repo.surahText(s))?[safe: a - 1] ?? "") }
        } else if e.hasPrefix("track:"), let t = repo.track(String(e.dropFirst(6))) {
            let r = repo.reciter(t.reciterId), cur = player.current?.id == t.id && player.playing
            HStack(spacing: 10) {
                RemoteImage(raw: t.cover.isEmpty ? r?.image : t.cover).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 1) { Text(t.title).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(2); Text(nm(r?.name)).font(F.plex(12.5)).foregroundStyle(c.gold) }
                Spacer()
                Button { if cur { player.toggle() } else { player.play(t, in: [t]) } } label: { SiteIcon(name: cur ? "pause" : "play", size: 20, color: c.onGold).frame(width: 38, height: 38).background(Circle().fill(c.goldBrush)) }.buttonStyle(.plain).accessibilityLabel(tr("تشغيل"))
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 18).fill(c.surface2)).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.line)).padding(.top, 8)
        }
    }
}

/// A post's photos (1–4) as on the site; a tap opens them full screen.
struct MediaGrid: View {
    let media: [CMedia]
    @State private var zoom: Int?
    @Environment(\.pal) private var c
    var body: some View {
        let imgs = media.filter { $0.type == "image" }
        if let v = media.first, v.type == "video" {
            VideoPostPlayer(url: v.url).aspectRatio(v.w > 0 && v.h > 0 ? min(1.9, max(0.6, CGFloat(v.w) / CGFloat(v.h))) : 16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 18)).padding(.top, 8)
        } else if !imgs.isEmpty {
            let ratio: CGFloat = imgs.count == 1 && imgs[0].w > 0 && imgs[0].h > 0 ? min(1.9, max(0.75, CGFloat(imgs[0].w) / CGFloat(imgs[0].h))) : 16 / 10
            Group {
                switch imgs.count {
                case 1: cell(imgs, 0)
                case 2: HStack(spacing: 2) { cell(imgs, 0); cell(imgs, 1) }
                case 3: HStack(spacing: 2) { cell(imgs, 0); VStack(spacing: 2) { cell(imgs, 1); cell(imgs, 2) } }
                default: VStack(spacing: 2) { HStack(spacing: 2) { cell(imgs, 0); cell(imgs, 1) }; HStack(spacing: 2) { cell(imgs, 2); cell(imgs, 3) } }
                }
            }
            .aspectRatio(ratio, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.lineSoft)).padding(.top, 8)
            .fullScreenCover(item: Binding(get: { zoom.map(IntBox.init(v:)) }, set: { zoom = $0?.v })) { b in Lightbox(urls: imgs.map(\.url), start: b.v) }
        }
    }
    private func cell(_ l: [CMedia], _ i: Int) -> some View {
        Color.clear.overlay(RemoteImage(raw: l[i].url)).clipped().contentShape(Rectangle()).onTapGesture { zoom = i }
    }
}
struct Lightbox: View {
    let urls: [String]; let start: Int
    @Environment(\.dismiss) private var dismiss
    @State private var i = 0
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            TabView(selection: $i) { ForEach(urls.indices, id: \.self) { k in ZoomImage(raw: urls[k]).tag(k) } }.tabViewStyle(.page)
            Button { dismiss() } label: { SiteIcon(name: "close", size: 26, color: .white).frame(width: 48, height: 48) }.padding(8).accessibilityLabel(tr("إغلاق"))
        }.onAppear { i = start }
    }
}
private struct ZoomImage: View {
    let raw: String
    @State private var z: CGFloat = 1
    var body: some View { RemoteImage(raw: raw, mode: .fit).scaleEffect(z).gesture(MagnificationGesture().onChanged { z = max(1, min(4, $0)) }.onEnded { _ in if z < 1.1 { withAnimation { z = 1 } } }) }
}
struct VideoPostPlayer: View {
    let url: String
    @State private var p: AVPlayer?
    @Environment(\.pal) private var c
    var body: some View {
        ZStack {
            Color.black
            if let p { VideoPlayer(player: p) }
            else { Button { AudioPlayer.shared.pause(); if let u = Repo.media(url) { let x = AVPlayer(url: u); p = x; x.play() } } label: { SiteIcon(name: "play", size: 34, color: c.onGold).frame(width: 60, height: 60).background(Circle().fill(c.goldBrush)) }.accessibilityLabel(tr("تشغيل الفيديو")) }
        }.onDisappear { p?.pause() }
    }
}

// MARK: - one post

struct PostCard: View {
    let p: Post; var repostBy: Member? = nil; var big = false
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var more = false
    @State private var repostMenu = false
    @State private var askDelete = false
    @State private var askReport = false
    @State private var blockAsk: String?
    @State private var limitFor: Member?
    @State private var tick = 0
    var body: some View {
        VStack(spacing: 0) {
            if p.gone { Text(tr("هذا المنشور لم يعد متاحًا.")).font(F.plex(14)).foregroundStyle(c.faint).padding(18).frame(maxWidth: .infinity, alignment: .leading) }
            else if let a = p.author { content(a) }
            Rectangle().fill(c.lineSoft).frame(height: 1)
        }
        .id(tick)
        .bzSheet(isPresented: $more) { moreSheet.presentationDetents([.medium, .large]) }
        .bzSheet(isPresented: $repostMenu) {
            MenuSheet(title: tr("إعادة النشر")) {
                MenuRow(icon: "repost", title: p.reposted ? tr("تراجع عن إعادة النشر") : tr("إعادة نشر")) { repostMenu = false; Task { if let e = await cm.repost(p) { ui.say(e) } else { ui.say(p.reposted ? tr("أُعيد النشر") : tr("أُلغيت إعادة النشر")) }; tick += 1 } }
                MenuRow(icon: "quote", title: tr("اقتباس")) { repostMenu = false; ui.path.append(.compose("quote:\(p.id)")) }
            }.presentationDetents([.height(240)])
        }
        .bzSheet(item: $limitFor) { LimitSheet(m: $0) }
        .confirmationDialog(tr("حذف المنشور؟"), isPresented: $askDelete) { Button(tr("حذف"), role: .destructive) { Task { do { try await cm.delete(p); ui.say(tr("حُذف المنشور")); tick += 1 } catch { ui.say(Community.msg(error)) } } } }
        .confirmationDialog(tr("لماذا تبلّغ عن هذا المنشور؟"), isPresented: $askReport, titleVisibility: .visible) {
            ForEach(REPORT_REASONS, id: \.self) { r in Button(r) { Task { do { try await cm.report(p, r); ui.say(tr("شكرًا — وصل البلاغ للإدارة وسيُراجع خلال ٢٤ ساعة")) } catch { ui.say(Community.msg(error)) } } } }
            Button(tr("إلغاء"), role: .cancel) {}
        }
        .alert(tr("حظر @{0}؟", blockAsk ?? ""), isPresented: Binding(get: { blockAsk != nil }, set: { if !$0 { blockAsk = nil } })) {
            Button(tr("حظر"), role: .destructive) { if let h = blockAsk { Task { await setRel(h, "block", true) } } }
            Button(tr("إلغاء"), role: .cancel) {}
        } message: { Text(BLOCK_NOTE) }
    }
    @ViewBuilder private func content(_ a: Member) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let r = repostBy { HStack(spacing: 6) { SiteIcon(name: "repost", size: 15, color: c.muted); Text(cm.me?.handle == r.handle ? tr("أعدت النشر") : tr("أعاد نشرها {0}", r.name)).font(F.plex(12.5, .medium)).foregroundStyle(c.muted) }.padding(.leading, 34).padding(.bottom, 4) }
            if p.pinned && !big { HStack(spacing: 6) { SiteIcon(name: "pin", size: 15, color: c.muted); Text(tr("مثبّت")).font(F.plex(12.5, .medium)).foregroundStyle(c.muted) }.padding(.leading, 34).padding(.bottom, 4) }
            HStack(alignment: .top, spacing: 10) {
                Button { ui.path.append(.user(a.handle)) } label: { Avatar(m: a, size: big ? 52 : 46) }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Button { ui.path.append(.user(a.handle)) } label: {
                            HStack(spacing: 0) {
                                Text(a.name).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(1)
                                BadgeIcons(m: a).padding(.leading, 3)
                                if !big { Text(" \u{2066}@\(a.handle)\u{2069} · \(Fmt.ago(p.created))").font(F.plex(12.5)).foregroundStyle(c.muted).lineLimit(1) }
                            }
                        }.buttonStyle(.plain)
                        Spacer(minLength: 4)
                        Button { more = true } label: { SiteIcon(name: "dots", size: 22, color: c.muted).frame(width: 30, height: 26) }.buttonStyle(.plain).accessibilityLabel(tr("المزيد"))
                    }
                    if big { Text("\u{2066}@\(a.handle)\u{2069}").font(F.plex(12.5)).foregroundStyle(c.muted) }
                    if !p.replyToHandle.isEmpty && !big { HStack(spacing: 0) { Text(tr("ردًا على ")).font(F.plex(12.5)).foregroundStyle(c.muted); Button { ui.path.append(.user(p.replyToHandle)) } label: { Text("\u{2066}@\(p.replyToHandle)\u{2069}").font(F.plex(12.5)).foregroundStyle(c.gold) }.buttonStyle(.plain) } }
                    if !p.text.isEmpty { RichText(t: p.text, size: big ? 18 : 16).padding(.top, 3) }
                    MediaGrid(media: p.media)
                    if !p.embed.isEmpty { PostEmbed(e: p.embed) }
                    if let q = p.quote { quoteBox(q) }
                    if p.replyRule != "all" && (big || !p.canReply) { HStack(spacing: 6) { SiteIcon(name: "reply", size: 14, color: c.gold); Text(RULE_NOTE[p.replyRule] ?? "").font(F.plex(12.5)).foregroundStyle(c.muted) }.padding(.top, 8) }
                    if p.restricted { HStack(spacing: 6) { Ico(name: "shield", size: 14.4).foregroundStyle(c.gold); Text(tr("ردّ من حساب مقيّد — يراه هو وصاحب المنشور فقط")).font(F.plex(12.5)).foregroundStyle(c.muted) }.padding(.top, 8) }
                    if big { Text(fullDate(p.created) + (p.views > 0 ? tr(" · {0} مشاهدة", Community.num(p.views)) : "")).font(F.plex(12.5)).foregroundStyle(c.muted).padding(.top, 10) }
                    HStack {
                        act("reply", p.replies, false, c.gold) { reply() }.opacity(p.canReply ? 1 : 0.45)
                        Spacer(); act("repost", p.reposts + p.quotes, p.reposted, Color(hex: 0xFF30A46C)) { if cm.me == nil { ui.go(.community) } else { repostMenu = true } }
                        Spacer(); act(p.liked ? "heart-f" : "heart", p.likes, p.liked, Color(hex: 0xFFE5484D)) { Task { if cm.me == nil { ui.go(.community) } else if let e = await cm.like(p) { ui.say(e) }; tick += 1 } }
                        Spacer(); act("share", 0, false, c.gold) { share((p.text.isEmpty ? tr("منشور في المجتمع") : String(p.text.prefix(120))) + "\n\(Repo.site)community/p/\(p.id)") }
                    }.padding(.top, 8)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { if !big { ui.path.append(.thread(p.id)) } }
    }
    private func quoteBox(_ q: Post) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if q.gone || q.author == nil { Text(tr("هذا المنشور لم يعد متاحًا.")).font(F.plex(14)).foregroundStyle(c.faint) }
            else {
                HStack(spacing: 6) { Avatar(m: q.author, size: 22); Text(q.author!.name).font(F.plex(13, .semibold)).foregroundStyle(c.text); BadgeIcons(m: q.author, max: 2, size: 14); Text(" \u{2066}@\(q.author!.handle)\u{2069} · \(Fmt.ago(q.created))").font(F.plex(11)).foregroundStyle(c.muted).lineLimit(1) }
                if !q.text.isEmpty { Text(q.text).font(F.plex(14)).foregroundStyle(c.text).lineLimit(6) }
                if let m = q.media.first { if m.type == "video" { Text(tr("🎬 فيديو")).font(F.plex(13)).foregroundStyle(c.muted) } else { RemoteImage(raw: m.url).frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 14)) } }
                if q.embed.hasPrefix("ayah:") { PostEmbed(e: q.embed, compact: true) }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.line)).padding(.top, 8)
        .contentShape(Rectangle()).onTapGesture { if !q.gone { ui.path.append(.thread(q.id)) } }
    }
    private func act(_ icon: String, _ n: Int, _ on: Bool, _ col: Color, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            HStack(spacing: 5) { SiteIcon(name: icon, size: 19, color: on ? col : c.muted); if n > 0 { Text(Community.num(n)).font(F.plex(12.5, .medium)).foregroundStyle(on ? col : c.muted) } }.padding(.horizontal, 8).padding(.vertical, 6)
        }.buttonStyle(.plain)
    }
    private func reply() {
        if cm.me == nil { ui.go(.community); return }
        if !p.canReply { ui.say(RULE_NOTE[p.replyRule] ?? tr("لا يمكنك التفاعل مع هذا الحساب.")); return }
        ui.path.append(.compose("reply:\(p.id)"))
    }
    private func setRel(_ h: String, _ kind: String, _ on: Bool) async {
        do { try await cm.rel(h, kind, on); ui.say(REL_DONE[kind].map { on ? $0.0 : $0.1 } ?? "") } catch { ui.say(Community.msg(error)) }
    }
    private var moreSheet: some View {
        MenuSheet(title: tr("المنشور")) {
            MenuRow(icon: "link", title: tr("نسخ الرابط")) { UIPasteboard.general.string = "\(Repo.site)community/p/\(p.id)"; ui.say(tr("نُسخ الرابط")); more = false }
            if cm.me?.canFeedPin == true && p.replyToHandle.isEmpty {
                let on = cm.me?.feedPin != p.id
                MenuRow(icon: "pin", title: on ? tr("تثبيت في أول المجتمع (للكل)") : tr("إلغاء التثبيت من أول المجتمع")) { more = false; Task { do { try await cm.feedPin(p, on); ui.say(on ? tr("ثُبّت في أول المجتمع — اسحب للتحديث") : tr("أُلغي التثبيت من أول المجتمع")) } catch { ui.say(Community.msg(error)) } } }
            }
            if p.mine {
                let prof = p.pinned && !p.feedPinned
                MenuRow(icon: "pin", title: prof ? tr("إلغاء التثبيت") : tr("تثبيت في ملفي")) { more = false; Task { do { try await cm.pin(p, !prof); ui.say(prof ? tr("أُلغي التثبيت") : tr("ثُبّت في ملفك")) } catch { ui.say(Community.msg(error)) } } }
                MenuRow(icon: "trash", title: tr("حذف"), tint: c.danger) { more = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { askDelete = true } }
            } else if cm.me != nil, let a = p.author {
                MenuRow(icon: "speaker.slash", title: tr("كتم @{0}", a.handle), sub: tr("لن تظهر لك منشوراته، دون أن يعلم")) { more = false; Task { await setRel(a.handle, "mute", true) } }
                MenuRow(icon: "nosign", title: tr("حظر @{0}", a.handle), sub: tr("لن يرى منشوراتك ولن يتفاعل معك"), tint: c.danger) { more = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { blockAsk = a.handle } }
                if cm.me?.canLimit == true { MenuRow(icon: "shield", title: tr("تقييد @{0} (إدارة)", a.handle), sub: tr("يتصفح ويقرأ فقط حتى تنتهي المدة")) { more = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { limitFor = a } } }
            }
            if !p.mine { MenuRow(icon: "flag", title: tr("إبلاغ عن المنشور")) { more = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { askReport = true } } }
            if let a = p.author { MenuRow(icon: "user", title: tr("ملف {0}", a.name)) { more = false; ui.path.append(.user(a.handle)) } }
        }
    }
}
var RULE_NOTE: [String: String] { ["follow": tr("يمكن الرد لمن يتابعهم صاحب المنشور"), "mention": tr("يمكن الرد لمن أشار إليهم صاحب المنشور")] }
func fullDate(_ d: Date) -> String { let f = DateFormatter(); f.locale = L.locale; f.dateFormat = "h:mm a · d MMMM yyyy"; return f.string(from: d) }

// MARK: - the community (feed, explore, notifications, profiles)

/// «المجتمع» like the Android app: [arg] "" (feed) · "search[:q]" · "notifications"; a profile is CommunityView(user:).
struct CommunityView: View {
    var user: String? = nil
    var arg = ""
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var auth = false
    @State private var edit = false
    @State private var ready = false
    private var view: String { user != nil ? "user" : arg.hasPrefix("search") ? "search" : arg == "notifications" ? "notifs" : "feed" }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Pill(title: tr("الرئيسية"), on: view == "feed", icon: "home") { if view != "feed" { ui.go(.community) } }
                Pill(title: tr("استكشف"), on: view == "search", icon: "search") { if view != "search" { ui.path.append(.cm("search")) } }
                if let me = cm.me {
                    Pill(title: tr("الإشعارات"), on: view == "notifs", icon: "bell") { if view != "notifs" { ui.path.append(.cm("notifications")) } }
                        .overlay(alignment: .topTrailing) { if cm.unread > 0 { Text(cm.unread > 99 ? "99+" : cm.unread.ar).font(F.plex(10, .bold)).foregroundStyle(.white).padding(.horizontal, 5).background(Capsule().fill(c.danger)).offset(x: 4, y: -4) } }
                    Spacer()
                    Button { ui.path.append(.user(me.handle)) } label: { Avatar(m: me, size: 36) }.buttonStyle(.plain)
                } else {
                    Spacer()
                    Pill(title: tr("دخول"), on: true, icon: "person.crop.circle") { auth = true }
                }
            }.padding(.horizontal, 12).padding(.vertical, 6)
            if let me = cm.me, me.email.isEmpty, ready {
                HStack(spacing: 8) {
                    SiteIcon(name: "mail", size: 18, color: c.gold)
                    Text(tr("أضف بريدك الإلكتروني لتتمكن من استعادة حسابك إن نسيت كلمة المرور.")).font(F.plex(12.5)).foregroundStyle(c.text).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button(tr("إضافة")) { edit = true }.font(F.plex(14, .bold)).foregroundStyle(c.gold)
                }.padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 14).fill(c.gold.opacity(0.1))).overlay(RoundedRectangle(cornerRadius: 14).stroke(c.gold.opacity(0.45))).padding(.horizontal, 12).padding(.vertical, 4)
            }
            ZStack(alignment: .bottomLeading) {
                if !ready { ProgressView().tint(c.gold).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else {
                    switch view {
                    case "user": UserView(handle: user!.lowercased(), edit: { edit = true })
                    case "notifs": NotifsView()
                    case "search": CmSearchView(q0: arg.hasPrefix("search:") ? String(arg.dropFirst(7)) : "")
                    default: FeedView()
                    }
                }
                if view == "feed" || view == "user" {
                    Button { if cm.me == nil { auth = true } else { ui.path.append(.compose("new")) } } label: {
                        HStack(spacing: 8) { Ico(name: "pencil", size: 21.6); Text(tr("منشور جديد")).font(F.plex(15, .bold)) }
                            .foregroundStyle(c.onGold).padding(.horizontal, 18).frame(height: 56).background(RoundedRectangle(cornerRadius: 20).fill(c.gold)).shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                    }.buttonStyle(Press()).padding(18)
                }
            }
        }
        .task { await cm.loadMe(); ready = true }
        .bzSheet(isPresented: $auth) { AuthSheet() }
        .bzSheet(isPresented: $edit) { EditProfileSheet() }
    }
}

/// A list of posts loaded page by page (pull to refresh, more at the end).
struct PagedPosts<Header: View>: View {
    let key: String; let load: (Int) async throws -> Community.Page; let empty: String
    @ViewBuilder var header: (Community.Page?) -> Header
    @EnvironmentObject var cm: Community
    @Environment(\.pal) private var c
    @State private var first: Community.Page?
    @State private var items: [FeedItem] = []
    @State private var next = 0
    @State private var err: String?
    @State private var loading = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header(first)
                if first == nil && err == nil { ProgressView().tint(c.gold).frame(maxWidth: .infinity).padding(40) }
                if let err { Empty(text: err, icon: "offline", action: tr("إعادة المحاولة")) { Task { await reload() } } }
                if let p = first?.pinned { PostCard(p: p) }
                if first != nil && items.isEmpty && first?.pinned == nil { Empty(text: empty, icon: "chat") }
                ForEach(items) { it in PostCard(p: it.post, repostBy: it.repostBy).onAppear { if it.id == items.last?.id { Task { await more() } } } }
                if loading { ProgressView().tint(c.gold).frame(maxWidth: .infinity).padding(16) }
            }.padding(.bottom, 90)
        }
        .refreshable { await reload() }
        .task(id: key) { await reload() }
        .onChange(of: cm.relRev) { _ in Task { await reload() } }
    }
    private func reload() async {
        err = nil
        do { let p = try await load(0); first = p; items = p.items; next = p.next } catch { err = Community.msg(error) }
    }
    private func more() async {
        guard next > 0, !loading else { return }
        loading = true; defer { loading = false }
        if let p = try? await load(next) { let have = Set(items.map(\.id)); items += p.items.filter { !have.contains($0.id) }; next = p.next }
    }
}

struct FeedView: View {
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var tab = "all"
    @State private var sug: (people: [Member], tags: [(String, Int)])?
    var body: some View {
        PagedPosts(key: tab, load: { try await cm.feed(tab, before: $0) }, empty: tab == "following" ? tr("لا توجد منشورات بعد — تابع حسابات لترى منشوراتها هنا.") : tr("لا توجد منشورات بعد — كن أول من ينشر.")) { _ in
            if cm.me != nil { Seg(items: [tr("لك"), tr("المتابَعون")], selected: tab == "all" ? 0 : 1) { tab = $0 == 0 ? "all" : "following" }.padding(.horizontal, 16).padding(.vertical, 6) }
            if let s = sug, !s.people.isEmpty || !s.tags.isEmpty { suggestions(s) }
            Rectangle().fill(c.lineSoft).frame(height: 1)
        }
        .task { sug = try? await cm.suggest() }
    }
    private func suggestions(_ s: (people: [Member], tags: [(String, Int)])) -> some View {
        Panel(pad: 12, lattice: false) {
            if !s.tags.isEmpty {
                Text(tr("رائج هذا الأسبوع")).font(F.plex(14, .semibold)).foregroundStyle(c.gold)
                FlowLayout(spacing: 6) { ForEach(s.tags, id: \.0) { t, n in Chip(text: "#\(t) · \(n.ar)", icon: "number") { ui.path.append(.cm("search:#\(t)")) } } }.padding(.vertical, 8)
            }
            if !s.people.isEmpty {
                Text(tr("حسابات مقترحة")).font(F.plex(14, .semibold)).foregroundStyle(c.gold)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(s.people) { m in
                            Button { ui.path.append(.user(m.handle)) } label: {
                                VStack(spacing: 2) {
                                    Avatar(m: m, size: 54)
                                    HStack(spacing: 2) { Text(m.name).font(F.plex(13, .semibold)).foregroundStyle(c.text).lineLimit(1); BadgeIcons(m: m, max: 1, size: 14) }.padding(.top, 4)
                                    Text("\u{2066}@\(m.handle)\u{2069}").font(F.plex(11)).foregroundStyle(c.muted).lineLimit(1)
                                }.frame(width: 90).padding(10).background(RoundedRectangle(cornerRadius: 18).fill(c.bg2.opacity(0.6)))
                            }.buttonStyle(Press())
                        }
                    }
                }.padding(.top, 8)
            }
        }.padding(.horizontal, 12).padding(.vertical, 6)
    }
}

struct UserView: View {
    let handle: String; let edit: () -> Void
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var tab = "posts"
    @State private var follow: Bool?
    @State private var followers: Int?
    @State private var relMenu = false
    @State private var blockAsk = false
    @State private var limitFor: Member?
    var body: some View {
        PagedPosts(key: "\(handle)/\(tab)", load: { try await cm.user(handle, tab: tab, before: $0) },
                   empty: tab == "likes" ? tr("لا إعجابات بعد.") : tab == "media" ? tr("لا صور أو فيديو بعد.") : tab == "replies" ? tr("لا ردود بعد.") : cm.me?.handle == handle ? tr("لم تنشر شيئًا بعد — اكتب أول منشور لك.") : tr("لا منشورات بعد.")) { pg in
            if let pg, let u = pg.user { profile(u, pg) }
        }
        .bzSheet(item: $limitFor) { LimitSheet(m: $0) }
    }
    @ViewBuilder private func profile(_ u: Member, _ pg: Community.Page) -> some View {
        let mine = cm.me?.handle == handle
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if !u.cover.isEmpty { RemoteImage(raw: u.cover) } else { ZStack { LinearGradient(colors: [c.surface3, c.gold.opacity(0.35), c.surface2], startPoint: .topLeading, endPoint: .bottomTrailing); StarPattern(tile: 70, alpha: 2) } }
            }.frame(height: 150).clipped()
            HStack(alignment: .bottom) {
                Avatar(m: u, size: 84).padding(4).background(Circle().fill(c.bg))
                Spacer()
                if mine {
                    Button { ui.path.append(.blocked) } label: { Ico(name: "shield", size: 24.0).foregroundStyle(c.gold).frame(width: 44, height: 44) }.accessibilityLabel(tr("الحظر والكتم"))
                    GhostButton(title: tr("تعديل الملف"), icon: "pencil") { edit() }
                } else {
                    if cm.me != nil { Button { relMenu = true } label: { Ico(name: "ellipsis", size: 24.0).foregroundStyle(c.text).frame(width: 44, height: 44) }.accessibilityLabel(tr("المزيد")) }
                    if pg.blocked { if u.blocked { GhostButton(title: tr("إلغاء الحظر"), icon: "nosign") { Task { await setRel(u.handle, "block", false) } } } }
                    else {
                        let f = follow ?? u.iFollow
                        if f { GhostButton(title: tr("متابَع"), icon: "check") { toggle(u, false) } } else { GoldButton(title: tr("متابعة"), icon: "person.badge.plus") { toggle(u, true) } }
                    }
                }
            }.padding(.horizontal, 16).offset(y: -38).padding(.bottom, -38)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) { Text(u.name).font(F.amiri(22)).foregroundStyle(c.text); BadgeIcons(m: u, max: 9, size: 20) }
                HStack(spacing: 6) {
                    Text("\u{2066}@\(u.handle)\u{2069}").font(F.plex(14)).foregroundStyle(c.muted)
                    if u.followsMe { Text(tr("يتابعك")).font(F.plex(11)).foregroundStyle(c.muted).padding(.horizontal, 6).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 6).fill(c.surface2)) }
                }
                BadgeChips(m: u)
                if pg.blocked { Text(u.blockedMe ? tr("لا يمكنك عرض منشورات هذا الحساب أو التفاعل معه.") : tr("لقد حظرت هذا الحساب — لا يمكنه رؤية منشوراتك أو التفاعل معك.")).font(F.plex(14)).foregroundStyle(c.muted).padding(.top, 10) }
                else if u.muted { Text(tr("هذا الحساب مكتوم — لا تظهر منشوراته في صفحتك الرئيسية.")).font(F.plex(12.5)).foregroundStyle(c.muted).padding(.top, 8) }
                if !u.bio.isEmpty { RichText(t: u.bio).padding(.top, 8) }
                FlowLayout(spacing: 14) {
                    if !u.location.isEmpty { HStack(spacing: 3) { SiteIcon(name: "pin", size: 16, color: c.muted); Text(u.location).font(F.plex(12.5)).foregroundStyle(c.muted) } }
                    if !u.website.isEmpty { Link(destination: URL(string: u.website) ?? URL(string: Repo.site)!) { HStack(spacing: 3) { SiteIcon(name: "link", size: 16, color: c.gold); Text(String(u.website.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression).prefix(30))).font(F.plex(12.5)).foregroundStyle(c.gold) } } }
                    if u.created > 0 { HStack(spacing: 3) { SiteIcon(name: "calendar", size: 16, color: c.muted); Text(tr("انضم {0}", joined(u.created))).font(F.plex(12.5)).foregroundStyle(c.muted) } }
                }.padding(.top, 8)
                HStack(spacing: 16) {
                    Button { ui.path.append(.people(u.handle, "following")) } label: { Text(tr("{0} يتابع", Text(u.following.ar).bold().foregroundColor(c.text))) }.buttonStyle(.plain)
                    Button { ui.path.append(.people(u.handle, "followers")) } label: { Text(tr("{0} متابِع", Text((followers ?? u.followers).ar).bold().foregroundColor(c.text))) }.buttonStyle(.plain)
                }.font(F.plex(14)).foregroundStyle(c.muted).padding(.top, 8)
            }.padding(.horizontal, 16).padding(.top, 8)
            if !pg.blocked { Seg(items: [tr("المنشورات"), tr("الردود"), tr("الوسائط"), tr("الإعجابات")], selected: ["posts", "replies", "media", "likes"].firstIndex(of: tab) ?? 0) { tab = ["posts", "replies", "media", "likes"][$0] }.padding(.horizontal, 12).padding(.vertical, 12) }
            Rectangle().fill(c.lineSoft).frame(height: 1)
        }
        .confirmationDialog("@\(u.handle)", isPresented: $relMenu) {
            Button(u.muted ? tr("إلغاء كتم @{0}", u.handle) : tr("كتم @{0}", u.handle)) { Task { await setRel(u.handle, "mute", !u.muted) } }
            if u.blocked { Button(tr("إلغاء حظر @{0}", u.handle)) { Task { await setRel(u.handle, "block", false) } } } else { Button(tr("حظر @{0}", u.handle), role: .destructive) { blockAsk = true } }
            if cm.me?.canLimit == true { Button(u.limitedNow ? tr("تعديل تقييد @{0} (إدارة)", u.handle) : tr("تقييد @{0} (إدارة)", u.handle)) { limitFor = u } }
        }
        .alert(tr("حظر @{0}؟", u.handle), isPresented: $blockAsk) {
            Button(tr("حظر"), role: .destructive) { Task { await setRel(u.handle, "block", true) } }
            Button(tr("إلغاء"), role: .cancel) {}
        } message: { Text(BLOCK_NOTE) }
    }
    private func joined(_ t: Int) -> String { let f = DateFormatter(); f.locale = L.locale; f.dateFormat = "MMMM yyyy"; return f.string(from: Date(timeIntervalSince1970: Double(t))) }
    private func toggle(_ u: Member, _ on: Bool) {
        if cm.me == nil { ui.go(.community); return }
        follow = on
        Task { if let e = await cm.follow(u.handle, on) { follow = !on; ui.say(e) } else { followers = (followers ?? u.followers) + (on ? 1 : -1) } }
    }
    private func setRel(_ h: String, _ kind: String, _ on: Bool) async {
        do { try await cm.rel(h, kind, on); ui.say(REL_DONE[kind].map { on ? $0.0 : $0.1 } ?? "") } catch { ui.say(Community.msg(error)) }
    }
}

struct ThreadView: View {
    let id: Int
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var t: (Post, [Post], [Post])?
    @State private var err: String?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let t {
                    ForEach(t.2) { PostCard(p: $0) }
                    PostCard(p: t.0, big: true)
                    if let me = cm.me {
                        if t.0.canReply {
                            Button { ui.path.append(.compose("reply:\(t.0.id)")) } label: {
                                HStack(spacing: 10) { Avatar(m: me, size: 36); Text(tr("اكتب ردّك…")).font(F.plex(15)).foregroundStyle(c.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 10).overlay(Capsule().stroke(c.line)) }.padding(16)
                            }.buttonStyle(.plain)
                        } else { Text(RULE_NOTE[t.0.replyRule] ?? tr("لا يمكنك الرد على هذا المنشور.")).font(F.plex(14)).foregroundStyle(c.muted).padding(16) }
                        Rectangle().fill(c.lineSoft).frame(height: 1)
                    }
                    ForEach(t.1) { PostCard(p: $0) }
                    if t.1.isEmpty { Text(tr("لا ردود بعد.")).font(F.plex(14)).foregroundStyle(c.faint).frame(maxWidth: .infinity).padding(24) }
                } else if let err { Empty(text: err, icon: "search") }
                else { ProgressView().tint(c.gold).frame(maxWidth: .infinity).padding(40) }
            }.padding(.bottom, 40)
        }
        .task(id: "\(id)-\(cm.relRev)") { do { t = try await cm.thread(id) } catch { err = (error as? CmError)?.code == "not_found" ? tr("هذا المنشور غير موجود.") : Community.msg(error) } }
    }
}

struct NotifsView: View {
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var list: [Notif]?
    @State private var err: String?
    var body: some View {
        let T: [String: (String, Color, String)] = ["like": ("heart-f", Color(hex: 0xFFE5484D), tr("أعجبه منشورك")), "repost": ("repost", Color(hex: 0xFF30A46C), tr("أعاد نشر منشورك")),
            "reply": ("reply", c.gold, tr("ردّ عليك")), "quote": ("quote", c.gold, tr("اقتبس منشورك")), "follow": ("person.badge.plus", c.gold, tr("بدأ متابعتك")), "mention": ("at", c.gold, tr("أشار إليك"))]
        ScrollView {
            LazyVStack(spacing: 0) {
                if let l = list {
                    if l.isEmpty { Empty(text: tr("لا إشعارات بعد — حين يتفاعل أحد مع منشوراتك ستظهر هنا."), icon: "bell") }
                    ForEach(l) { n in
                        let tt = T[n.type] ?? ("bell", c.gold, "")
                        Button { if n.type == "follow" { ui.path.append(.user(n.actor.handle)) } else if let p = n.post { ui.path.append(.thread(p.id)) } } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Ico(name: tt.0, size: 26, color: tt.1)
                                VStack(alignment: .leading, spacing: 0) {
                                    Avatar(m: n.actor, size: 34)
                                    HStack(spacing: 0) { Text(n.actor.name).font(F.plex(14, .bold)).foregroundStyle(c.text); BadgeIcons(m: n.actor, max: 2, size: 14); Text(" \(tt.2) · \(Fmt.ago(n.created))").font(F.plex(12.5)).foregroundStyle(c.muted) }.padding(.top, 6)
                                    if let p = n.post, n.type != "follow", !p.text.isEmpty { Text(String(p.text.prefix(180))).font(F.plex(14)).foregroundStyle(c.muted).multilineTextAlignment(.leading).padding(.top, 4) }
                                }
                                Spacer()
                            }.padding(16).background(n.seen ? .clear : c.gold.opacity(0.06))
                        }.buttonStyle(.plain)
                        Rectangle().fill(c.lineSoft).frame(height: 1)
                    }
                } else if let err { Empty(text: err) }
                else { ProgressView().tint(c.gold).padding(40) }
            }
        }
        .task { do { list = try await cm.notifs() } catch { err = Community.msg(error) } }
    }
}

struct CmSearchView: View {
    let q0: String
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var q = ""
    @State private var sent = ""
    @State private var people: [Member] = []
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchField(text: $q, hint: tr("ابحث عن أشخاص أو منشورات أو #وسم")).onSubmit { sent = q.trimmingCharacters(in: .whitespaces) }
                GoldButton(title: tr("بحث")) { sent = q.trimmingCharacters(in: .whitespaces) }
            }.padding(.horizontal, 16).padding(.vertical, 6)
            if sent.count < 2 { Empty(text: tr("ابحث باسم شخص أو @اسم_مستخدم أو كلمة أو #وسم."), icon: "search"); Spacer() }
            else {
                PagedPosts(key: sent, load: { b in let p = try await cm.search(sent, before: b); if b == 0 { people = p.people }; return p }, empty: tr("لا نتائج.")) { _ in
                    if !people.isEmpty {
                        SectionHead(title: tr("أشخاص"))
                        ForEach(people) { m in
                            Button { ui.path.append(.user(m.handle)) } label: {
                                HStack(spacing: 10) {
                                    Avatar(m: m, size: 46)
                                    VStack(alignment: .leading, spacing: 0) {
                                        HStack(spacing: 2) { Text(m.name).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(1); BadgeIcons(m: m) }
                                        Text("\u{2066}@\(m.handle)\u{2069}").font(F.plex(12.5)).foregroundStyle(c.muted)
                                        if !m.bio.isEmpty { Text(m.bio).font(F.plex(12.5)).foregroundStyle(c.text).lineLimit(2) }
                                    }
                                    Spacer()
                                }.padding(.horizontal, 16).padding(.vertical, 10)
                            }.buttonStyle(.plain)
                        }
                        SectionHead(title: tr("منشورات"))
                    }
                }
            }
        }
        .onAppear { if q.isEmpty && !q0.isEmpty { q = q0; sent = q0 } }
    }
}
