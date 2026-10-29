import SwiftUI
import PhotosUI

struct Avatar: View {
    let m: Member?; var size: CGFloat = 44
    @Environment(\.pal) private var c
    var body: some View {
        ZStack {
            Circle().fill(c.surface2)
            if let a = m?.avatar, !a.isEmpty { RemoteImage(raw: a).clipShape(Circle()) }
            else { Text(String((m?.name ?? "؟").prefix(1))).font(F.plex(size * 0.42, .bold)).foregroundStyle(c.gold) }
        }.frame(width: size, height: size)
    }
}

struct BadgeIcons: View {
    let m: Member?
    @Environment(\.pal) private var c
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Community.badges.filter { m?.badges.contains($0.0) == true }.prefix(2), id: \.0) { b in
                Image(systemName: b.2).font(.system(size: 12)).foregroundStyle(b.0 == "verified" ? Color.blue : c.gold)
            }
        }
    }
}

/// An ayah or a recitation attached to a post.
struct EmbedView: View {
    let e: String
    @EnvironmentObject var ayah: AyahPlayer
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var repo: Repo
    @Environment(\.pal) private var c
    @State private var text = ""
    var body: some View {
        Group {
            if e.hasPrefix("ayah:") {
                let parts = e.dropFirst(5).split(separator: "|", maxSplits: 1)
                let sa = parts.first?.split(separator: ":").compactMap { Int($0) } ?? [1, 1]
                let rv = parts.count > 1 ? String(parts[1]) : "yasser"
                if sa.count == 2 {
                    let on = ayah.key == "\(sa[0]):\(sa[1])|\(rv)" && ayah.playing
                    VStack(alignment: .leading, spacing: 8) {
                        Text("﴿\(text)﴾").font(F.quran(20)).foregroundStyle(c.text).lineSpacing(8).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        HStack {
                            Button { if on { ayah.stop() } else { ayah.play(rv, sa[0], sa[1]) } } label: { Image(systemName: on ? "pause.fill" : "play.fill").foregroundStyle(c.onGold).frame(width: 34, height: 34).background(Circle().fill(c.gold)) }
                            Text("سورة \(Quran.surahs[max(0, min(113, sa[0] - 1))]) · \(sa[1].ar)").font(F.plex(12)).foregroundStyle(c.muted)
                        }
                    }
                    .task { text = (await repo.surahText(sa[0]))?[safe: sa[1] - 1] ?? "" }
                }
            } else if e.hasPrefix("track:"), let t = repo.track(String(e.dropFirst(6))) {
                Button { player.play(t, in: [t]) } label: {
                    HStack(spacing: 10) {
                        RemoteImage(raw: repo.image(for: t)).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading) { Text(t.title).font(F.plex(14, .semibold)).foregroundStyle(c.text).lineLimit(2); Text(repo.reciter(t.reciterId)?.name ?? "").font(F.plex(12)).foregroundStyle(c.gold) }
                        Spacer(); Image(systemName: "play.circle.fill").font(.system(size: 28)).foregroundStyle(c.gold)
                    }
                }.buttonStyle(.plain)
            }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 16).fill(c.surface2.opacity(0.7))).overlay(RoundedRectangle(cornerRadius: 16).stroke(c.line))
    }
}

struct PostCard: View {
    let p: Post; var repostBy: Member? = nil; var quoted = false
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var askDelete = false
    @State private var limitFor: Member?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let r = repostBy { Label("\(r.name) أعاد النشر", systemImage: "arrow.2.squarepath").font(F.plex(12)).foregroundStyle(c.muted) }
            HStack(alignment: .top, spacing: 10) {
                Button { if let h = p.author?.handle { ui.path.append(.user(h)) } } label: { Avatar(m: p.author, size: quoted ? 28 : 44) }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text(p.author?.name ?? "").font(F.plex(14.5, .bold)).foregroundStyle(c.text).lineLimit(1)
                        BadgeIcons(m: p.author)
                        Text("\u{2066}@\(p.author?.handle ?? "")\u{2069} · \(Fmt.ago(p.created))").font(F.plex(12)).foregroundStyle(c.faint).lineLimit(1)
                        Spacer()
                        if !quoted { Menu {
                            Button { share("\(Repo.site)community/post/\(p.id)") } label: { Label("مشاركة", systemImage: "square.and.arrow.up") }
                            if p.mine { Button(role: .destructive) { askDelete = true } label: { Label("حذف", systemImage: "trash") } }
                            else { Button { Task { await cm.report(p, "غير لائق"); ui.say("شكرًا — سيراجعه المشرفون") } } label: { Label("إبلاغ", systemImage: "flag") } }
                            if !p.mine, cm.me?.canLimit == true, let a = p.author { Button { limitFor = a } label: { Label("تقييد @\(a.handle) (إدارة)", systemImage: "shield") } }
                        } label: { Image(systemName: "ellipsis").foregroundStyle(c.muted).frame(width: 26, height: 22) } }
                    }
                    if !p.replyToHandle.isEmpty { Text("ردًّا على \u{2066}@\(p.replyToHandle)\u{2069}").font(F.plex(12)).foregroundStyle(c.gold) }
                    if !p.text.isEmpty { Text(p.text).font(F.plex(15)).foregroundStyle(c.text).fixedSize(horizontal: false, vertical: true) }
                    ForEach(p.media, id: \.self) { m in if m.type == "image" { RemoteImage(raw: m.url).frame(maxHeight: 320).clipShape(RoundedRectangle(cornerRadius: 16)) } }
                    if !p.embed.isEmpty { EmbedView(e: p.embed) }
                    if let q = p.quote, !quoted { PostCard(p: q, quoted: true).padding(10).overlay(RoundedRectangle(cornerRadius: 16).stroke(c.line)) }
                    if !quoted {
                        HStack {
                            action("bubble.left", p.replies) { ui.path.append(.compose("reply:\(p.id)")) }
                            Spacer()
                            Menu {
                                Button { Task { if let e = await cm.repost(p) { ui.say(e) } } } label: { Label(p.reposted ? "إلغاء إعادة النشر" : "إعادة نشر", systemImage: "arrow.2.squarepath") }
                                Button { ui.path.append(.compose("quote:\(p.id)")) } label: { Label("اقتباس", systemImage: "quote.bubble") }
                            } label: { HStack(spacing: 4) { Image(systemName: "arrow.2.squarepath"); Text(Community.num(p.reposts)) }.foregroundStyle(p.reposted ? c.ok : c.muted) }
                            Spacer()
                            action(p.liked ? "heart.fill" : "heart", p.likes, tint: p.liked ? c.danger : nil) { Task { if cm.me == nil { ui.go(.community) } else if let e = await cm.like(p) { ui.say(e) } } }
                            Spacer()
                        }.font(F.plex(13)).padding(.top, 4)
                    }
                }
            }
        }
        .padding(.horizontal, quoted ? 0 : 16).padding(.vertical, quoted ? 0 : 12)
        .contentShape(Rectangle()).onTapGesture { if !quoted { ui.path.append(.thread(p.id)) } }
        .sheet(item: $limitFor) { LimitSheet(m: $0) }
        .confirmationDialog("حذف المنشور؟", isPresented: $askDelete) { Button("حذف", role: .destructive) { Task { try? await cm.delete(p); ui.say("حُذف المنشور") } } }
    }
    private func action(_ icon: String, _ n: Int, tint: Color? = nil, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { HStack(spacing: 4) { Image(systemName: icon); Text(Community.num(n)) }.foregroundStyle(tint ?? c.muted) }.buttonStyle(.plain)
    }
}

struct CommunityView: View {
    var user: String? = nil
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var items: [FeedItem] = []
    @State private var next = 0
    @State private var loading = false
    @State private var tab = "all"
    @State private var profile: Member?
    @State private var auth = false
    @State private var edit = false
    @State private var limitFor: Member?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let me = cm.me, me.email.isEmpty, user == nil || user == me.handle {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope").foregroundStyle(c.gold)
                        Text("أضف بريدك الإلكتروني لتتمكن من استعادة حسابك إن نسيت كلمة المرور.").font(F.plex(13)).foregroundStyle(c.text).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button("إضافة") { edit = true }.font(F.plex(13.5, .bold)).foregroundStyle(c.gold)
                    }.padding(12).background(RoundedRectangle(cornerRadius: 14).fill(c.gold.opacity(0.1))).overlay(RoundedRectangle(cornerRadius: 14).stroke(c.gold.opacity(0.45), lineWidth: 1))
                    .padding(.horizontal, 16).padding(.top, 8)
                }
                if let u = user { header(profile, handle: u) }
                else {
                    HStack {
                        if let me = cm.me { Button { ui.path.append(.user(me.handle)) } label: { Avatar(m: me, size: 36) }.buttonStyle(.plain) }
                        Text("المجتمع").font(F.amiri(26)).foregroundStyle(c.text)
                        Spacer()
                        if cm.me == nil { Button("تسجيل الدخول") { auth = true }.font(F.plex(14, .bold)).foregroundStyle(c.gold) }
                    }.padding(16)
                    if cm.me != nil { HStack { Pill(title: "لك", on: tab == "all") { tab = "all" }; Pill(title: "المتابَعون", on: tab == "following") { tab = "following" } }.padding(.horizontal, 16) }
                }
                ForEach(items) { it in PostCard(p: it.post, repostBy: it.repostBy); Divider().overlay(c.lineSoft) }
                if loading { ProgressView().frame(maxWidth: .infinity).padding(30) }
                else if items.isEmpty { Empty(text: "لا توجد منشورات بعد — كن أول من ينشر.", icon: "bubble.left.and.bubble.right") }
                if next > 0 && !loading { Color.clear.frame(height: 1).onAppear { Task { await load(more: true) } } }
            }.padding(.bottom, 90)
        }
        .refreshable { await load() }
        .overlay(alignment: .bottomLeading) {
            if user == nil {
                Button { if cm.me == nil { auth = true } else { ui.path.append(.compose("new")) } } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 22, weight: .semibold)).foregroundStyle(c.onGold).frame(width: 58, height: 58).background(Circle().fill(c.goldGradient)).shadow(color: c.gold.opacity(0.5), radius: 12)
                }.padding(20)
            }
        }
        .task(id: tab + (user ?? "")) { await cm.loadMe(); await load() }
        .sheet(isPresented: $auth) { AuthSheet() }
        .sheet(isPresented: $edit) { EditProfileSheet() }
        .sheet(item: $limitFor, onDismiss: { Task { await load() } }) { LimitSheet(m: $0) }
        .navigationTitle(user.map { "@" + $0 } ?? "").navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func header(_ m: Member?, handle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(raw: m?.cover).frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 18))
                Avatar(m: m, size: 76).overlay(Circle().stroke(c.bg, lineWidth: 4)).offset(x: 14, y: 36)
            }.padding(.horizontal, 16).padding(.bottom, 36)
            HStack { Text(m?.name ?? "").font(F.plex(19, .bold)); BadgeIcons(m: m); Spacer()
                if m?.handle == cm.me?.handle && m != nil { GhostButton(title: "تعديل الملف") { edit = true } }
                else if let m, cm.me != nil { GoldButton(title: m.iFollow ? "إلغاء المتابعة" : "متابعة") { Task { if let e = await cm.follow(m.handle, !m.iFollow) { ui.say(e) }; await load() } } }
                if let m, cm.me?.canLimit == true, m.handle != cm.me?.handle { Button { limitFor = m } label: { Image(systemName: "shield").foregroundStyle(m.limitedNow ? c.gold : c.muted).frame(width: 36, height: 36) } }
            }.padding(.horizontal, 16)
            Text("\u{2066}@\(handle)\u{2069}").font(F.plex(13)).foregroundStyle(c.faint).padding(.horizontal, 16)
            if let b = m?.bio, !b.isEmpty { Text(b).font(F.plex(14)).foregroundStyle(c.text).padding(.horizontal, 16) }
            HStack(spacing: 14) {
                Button { ui.path.append(.people(handle, "following")) } label: { Text("\(Text(Community.num(m?.following ?? 0)).bold().foregroundColor(c.text)) يتابع") }.buttonStyle(.plain)
                Button { ui.path.append(.people(handle, "followers")) } label: { Text("\(Text(Community.num(m?.followers ?? 0)).bold().foregroundColor(c.text)) متابِع") }.buttonStyle(.plain)
                Text("\(Community.num(m?.posts ?? 0)) منشور")
            }.font(F.plex(13)).foregroundStyle(c.muted).padding(.horizontal, 16).padding(.bottom, 8)
            Divider().overlay(c.line)
        }
    }
    private func load(more: Bool = false) async {
        loading = true; defer { loading = false }
        do {
            let pg: Community.Page
            if let u = user { pg = try await cm.user(u, before: more ? next : 0) } else { pg = try await cm.feed(tab, before: more ? next : 0) }
            items = more ? items + pg.items : pg.items; next = pg.next
            if let u = pg.user { profile = u }
        } catch { ui.say(Community.msg(error)) }
    }
}

/// Followers / following as a full screen with tabs, search and endless scrolling (as on X).
struct PeopleView: View {
    let handle: String
    @State var list: String
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var rows: [Member] = []
    @State private var next = 0
    @State private var loading = false
    @State private var user: Member?
    @State private var q = ""
    @State private var sent = ""
    @State private var err: String?
    @State private var gen = 0
    @State private var following: [String: Bool] = [:]
    init(handle: String, list: String) { self.handle = handle; _list = State(initialValue: list) }
    private let tabs = [("verified", "الموثَّقون"), ("followers", "المتابِعون"), ("following", "يتابع")]
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(c.muted)
                        TextField("ابحث بالاسم أو المعرّف", text: $q).font(F.plex(15)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        if !q.isEmpty { Button { q = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(c.muted) } }
                    }.padding(.horizontal, 14).frame(height: 42).background(Capsule().fill(c.surface)).padding(.horizontal, 16).padding(.vertical, 10)
                    ForEach(rows) { m in row(m); Divider().overlay(c.lineSoft) }
                    if loading { ProgressView().frame(maxWidth: .infinity).padding(24) }
                    else if rows.isEmpty { Empty(text: err ?? (sent.isEmpty ? (list == "verified" ? "لا يوجد متابِعون موثَّقون بعد." : list == "following" ? "لا يتابع أحدًا بعد." : "لا يوجد متابِعون بعد.") : "لا توجد نتائج مطابقة."), icon: "person.2") }
                    if next > 0 && !loading { Color.clear.frame(height: 1).onAppear { Task { await load(more: true) } } }
                } header: {
                    HStack(spacing: 0) {
                        ForEach(tabs, id: \.0) { t in
                            Button { if list != t.0 { list = t.0 } } label: {
                                VStack(spacing: 9) {
                                    Text(t.1).font(F.plex(15, list == t.0 ? .bold : .medium)).foregroundStyle(list == t.0 ? c.text : c.muted)
                                    Capsule().fill(list == t.0 ? c.gold : .clear).frame(width: 52, height: 4)
                                }.frame(maxWidth: .infinity).padding(.top, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.background(c.bg.opacity(0.96)).overlay(alignment: .bottom) { Divider().overlay(c.line) }
                }
            }.padding(.bottom, 90)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: q) { try? await Task.sleep(nanoseconds: 300_000_000); let v = q.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: ""); if v != sent { sent = v } }
        .task(id: list + "|" + sent) { await cm.loadMe(); await load() }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    HStack(spacing: 4) { Text(user?.name ?? "@\(handle)").font(F.plex(15, .bold)).foregroundStyle(c.text).lineLimit(1); BadgeIcons(m: user) }
                    if user != nil { Text("\u{2066}@\(handle)\u{2069}").font(F.plex(11.5)).foregroundStyle(c.muted) }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func row(_ m: Member) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button { ui.path.append(.user(m.handle)) } label: {
                HStack(alignment: .center, spacing: 10) {
                    Avatar(m: m, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) { Text(m.name).font(F.plex(15, .bold)).foregroundStyle(c.text).lineLimit(1); BadgeIcons(m: m) }
                        HStack(spacing: 6) {
                            Text("\u{2066}@\(m.handle)\u{2069}").font(F.plex(13)).foregroundStyle(c.muted).lineLimit(1)
                            if m.followsMe && cm.me != nil { Text("يتابعك").font(F.plex(11)).foregroundStyle(c.muted).padding(.horizontal, 6).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 6).fill(c.surface2)) }
                        }
                        if !m.bio.isEmpty { Text(m.bio).font(F.plex(13.5)).foregroundStyle(c.text).lineLimit(2) }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if let me = cm.me, me.handle != m.handle {
                let on = following[m.handle] ?? m.iFollow
                Button {
                    following[m.handle] = !on
                    Task { if let e = await cm.follow(m.handle, !on) { following[m.handle] = on; ui.say(e) } else { ui.say(!on ? "تتابع @\(m.handle) الآن" : "ألغيت متابعة @\(m.handle)") } }
                } label: {
                    Text(on ? "تتابعه" : "متابعة").font(F.plex(13.5, .bold)).foregroundStyle(on ? c.text : c.onGold)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(on ? AnyShapeStyle(Color.clear) : AnyShapeStyle(c.goldGradient)))
                        .overlay(Capsule().stroke(on ? c.line : .clear, lineWidth: 1))
                }.buttonStyle(Press())
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }
    private func load(more: Bool = false) async {
        if !more { gen += 1; rows = []; next = 0; err = nil }
        let g = gen
        loading = true
        do {
            let r = try await cm.people(handle, list: list, off: more ? next : 0, q: sent)
            guard g == gen else { return }
            let have = Set(rows.map(\.id))
            rows += r.people.filter { !have.contains($0.id) }; next = r.next
            if let u = r.user { user = u }
        } catch { if g == gen { err = Community.msg(error); next = 0 } }
        if g == gen { loading = false }
    }
}

struct ThreadView: View {
    let id: Int
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var post: Post?
    @State private var replies: [Post] = []
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let p = post { PostCard(p: p); Divider().overlay(c.line)
                    Button { ui.path.append(.compose("reply:\(p.id)")) } label: { HStack { Avatar(m: cm.me, size: 32); Text("اكتب ردّك…").font(F.plex(14)).foregroundStyle(c.muted); Spacer() }.padding(16) }.buttonStyle(.plain)
                    Divider().overlay(c.line)
                } else { ProgressView().frame(maxWidth: .infinity).padding(40) }
                ForEach(replies) { r in PostCard(p: r); Divider().overlay(c.lineSoft) }
            }
        }
        .background(Backdrop()).navigationTitle("المنشور").navigationBarTitleDisplayMode(.inline)
        .task { if let t = try? await cm.thread(id) { post = t.0; replies = t.1 } }
    }
}

struct ComposeView: View {
    let embed: String
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @State private var text = ""
    @State private var media: [CMedia] = []
    @State private var pick: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var err: String?
    @State private var auth = false
    var body: some View {
        let reply = embed.hasPrefix("reply:") ? Int(embed.dropFirst(6)) ?? 0 : 0
        let quote = embed.hasPrefix("quote:") ? Int(embed.dropFirst(6)) ?? 0 : 0
        let att = embed.hasPrefix("ayah:") || embed.hasPrefix("track:") ? embed : ""
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if cm.me == nil {
                    Empty(text: "سجّل الدخول لتنشر في المجتمع.", icon: "lock")
                    GoldButton(title: "تسجيل الدخول") { auth = true }.frame(maxWidth: .infinity)
                } else if let me = cm.me, me.limitedNow {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "shield").foregroundStyle(c.gold)
                        Text(Community.limitMsg(me.limitedUntil, me.limitNote)).font(F.plex(14)).foregroundStyle(c.text).fixedSize(horizontal: false, vertical: true)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(c.gold.opacity(0.08))).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.gold.opacity(0.35)))
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        Avatar(m: cm.me, size: 42)
                        TextField(reply > 0 ? "اكتب ردّك…" : "بماذا تفكر؟", text: $text, axis: .vertical).font(F.plex(16)).lineLimit(4...12)
                    }
                    if !att.isEmpty { EmbedView(e: att) }
                    ScrollView(.horizontal) { HStack { ForEach(media, id: \.self) { m in RemoteImage(raw: m.url).frame(width: 110, height: 110).clipShape(RoundedRectangle(cornerRadius: 14)) } } }
                    if let err { Text(err).font(F.plex(13)).foregroundStyle(c.danger) }
                    HStack {
                        PhotosPicker(selection: $pick, maxSelectionCount: 4, matching: .images) { Image(systemName: "photo").font(.system(size: 20)).foregroundStyle(c.gold) }
                        Spacer()
                        Text("\((280 - text.count).ar)").font(F.plex(12)).foregroundStyle(text.count > 280 ? c.danger : c.muted)
                        GoldButton(title: busy ? "لحظات…" : (reply > 0 ? "ردّ" : "نشر")) {
                            guard !busy else { return }
                            busy = true; err = nil
                            Task {
                                do { try await cm.post(text: text, media: media, embed: att, replyTo: reply, quoteOf: quote); ui.say("نُشر ✓"); ui.path.removeLast() }
                                catch { err = Community.msg(error) }
                                busy = false
                            }
                        }
                    }
                }
            }.padding(18)
        }
        .background(Backdrop()).navigationTitle(reply > 0 ? "ردّ" : quote > 0 ? "اقتباس" : "منشور جديد").navigationBarTitleDisplayMode(.inline)
        .task { await cm.loadMe() }
        .onChange(of: pick) { items in
            Task {
                for it in items { if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { do { media.append(try await cm.upload(img)) } catch { err = Community.msg(error) } } }
                pick = []
            }
        }
        .sheet(isPresented: $auth) { AuthSheet() }
    }
}

struct AuthSheet: View {
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var signup = false
    @State private var name = ""
    @State private var handle = ""
    @State private var pass = ""
    @State private var email = ""
    @State private var rejected = false
    @State private var busy = false
    @State private var err: String?
    @State private var mode = ""          // "" sign in / sign up · "forgot" · "code"
    @State private var code = ""
    var body: some View {
        if mode.isEmpty { authForm } else { forgotForm }
    }
    private var forgotForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(mode == "forgot" ? "نسيت كلمة المرور" : "رمز التحقق").font(F.amiri(26)).foregroundStyle(c.text)
                Text(mode == "forgot" ? "اكتب اسم المستخدم أو البريد المسجّل في حسابك، وسنرسل رمز تحقق من ٦ أرقام إلى بريدك."
                     : "إن كان الحساب مرتبطًا ببريد، فقد أرسلنا إليه رمزًا من ٦ أرقام صالحًا ١٥ دقيقة. راجع البريد الوارد ومجلد الرسائل غير المرغوب فيها (Spam).")
                    .font(F.plex(13.5)).foregroundStyle(c.muted).fixedSize(horizontal: false, vertical: true)
                if mode == "forgot" {
                    TextField("اسم المستخدم أو البريد", text: $handle).textInputAutocapitalization(.never).autocorrectionDisabled().padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                } else {
                    TextField("رمز التحقق (٦ أرقام)", text: Binding(get: { code }, set: { v in
                        let digits = v.map { ch -> Character in if let d = "٠١٢٣٤٥٦٧٨٩".firstIndex(of: ch) { return Character(String("٠١٢٣٤٥٦٧٨٩".distance(from: "٠١٢٣٤٥٦٧٨٩".startIndex, to: d))) }; return ch }.filter { $0.isASCII && $0.isNumber }
                        code = String(String(digits).prefix(6)) }))
                        .keyboardType(.numberPad).textContentType(.oneTimeCode).multilineTextAlignment(.center).font(.system(size: 22, weight: .semibold, design: .rounded))
                        .environment(\.layoutDirection, .leftToRight).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                    SecureField("كلمة المرور الجديدة (8 أحرف على الأقل)", text: $pass).textContentType(.newPassword).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                }
                if let err { Text(err).font(F.plex(13)).foregroundStyle(c.danger) }
                GoldButton(title: busy ? "لحظات…" : (mode == "forgot" ? "إرسال الرمز" : "تغيير كلمة المرور")) {
                    guard !busy else { return }
                    let login = handle.trimmingCharacters(in: .whitespaces)
                    if mode == "forgot" && login.isEmpty { err = "اكتب اسم المستخدم أو البريد."; return }
                    if mode == "code" && code.count != 6 { err = "اكتب الرمز المكوّن من ٦ أرقام."; return }
                    if mode == "code" && pass.count < 8 { err = "كلمة المرور 8 أحرف على الأقل."; return }
                    busy = true; err = nil
                    Task {
                        do {
                            if mode == "forgot" { try await cm.forgotSend(login); pass = ""; mode = "code" }
                            else {
                                let u = try await cm.forgotReset(login, code: code, password: pass)
                                do { try await cm.login(u, pass); ui.say("تم تغيير كلمة المرور — أهلًا بك"); dismiss() }
                                catch { ui.say("تم تغيير كلمة المرور — سجّل الدخول بها الآن"); mode = ""; signup = false }
                            }
                        } catch { err = Community.msg(error); if (error as? CmError)?.code == "code_expired" { code = "" } }
                        busy = false
                    }
                }.frame(maxWidth: .infinity)
                Button(mode == "code" ? "لم يصلك الرمز؟ أرسله مرة أخرى" : "رجوع إلى تسجيل الدخول") {
                    if mode == "code" { Task { do { try await cm.forgotSend(handle.trimmingCharacters(in: .whitespaces)); ui.say("أُرسل رمز جديد إن كان الحساب مرتبطًا ببريد") } catch { ui.say(Community.msg(error)) } } }
                    else { mode = ""; err = nil }
                }.font(F.plex(14, .semibold)).foregroundStyle(c.gold).frame(maxWidth: .infinity)
            }.padding(22).font(F.plex(15))
        }.background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, .rightToLeft)
    }
    private var authForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(signup ? "إنشاء حساب" : "تسجيل الدخول").font(F.amiri(26)).foregroundStyle(c.text)
                HStack { Pill(title: "دخول", on: !signup) { signup = false }; Pill(title: "حساب جديد", on: signup) { signup = true } }
                if signup { field("الاسم", $name) }
                TextField(signup ? "اسم المستخدم (إنجليزي)" : "اسم المستخدم أو البريد", text: Binding(get: { handle }, set: { v in
                    if signup { let ok = String(v.lowercased().replacingOccurrences(of: " ", with: "_").filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }.prefix(20)); rejected = ok.count < min(20, v.count); handle = ok } else { handle = v }
                })).textInputAutocapitalization(.never).autocorrectionDisabled().padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                if signup { Text(rejected ? "اسم المستخدم بالحروف الإنجليزية فقط — غيّر لغة لوحة المفاتيح إلى الإنجليزية" : "حروف إنجليزية وأرقام و _ (3–20)، واكتب اسمك العربي في خانة «الاسم»").font(F.plex(11.5)).foregroundStyle(rejected ? c.danger : c.faint) }
                SecureField(signup ? "كلمة المرور (8 أحرف على الأقل)" : "كلمة المرور", text: $pass).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                if signup {
                    TextField("البريد الإلكتروني", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                }
                if let err { Text(err).font(F.plex(13)).foregroundStyle(c.danger) }
                GoldButton(title: busy ? "لحظات…" : (signup ? "إنشاء الحساب" : "دخول")) {
                    guard !busy else { return }
                    if signup && email.trimmingCharacters(in: .whitespaces).isEmpty { err = "اكتب بريدك الإلكتروني — نحتاجه لإرسال رمز استعادة الحساب إن نسيت كلمة المرور."; return }
                    busy = true; err = nil
                    Task {
                        do { if signup { try await cm.register(name: name, handle: handle, password: pass, email: email) } else { try await cm.login(handle.trimmingCharacters(in: .whitespaces), pass) }
                             ui.say("أهلًا \(cm.me?.name ?? "")"); dismiss() }
                        catch { err = Community.msg(error) }
                        busy = false
                    }
                }.frame(maxWidth: .infinity)
                if !signup { Button("نسيت كلمة المرور؟") { mode = "forgot"; err = nil }.font(F.plex(14, .semibold)).foregroundStyle(c.gold).frame(maxWidth: .infinity) }
                Link("سياسة الخصوصية", destination: URL(string: Repo.site + "privacy")!).font(F.plex(12)).foregroundStyle(c.faint)
            }.padding(22).font(F.plex(15))
        }.background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, .rightToLeft)
    }
    private func field(_ p: String, _ b: Binding<String>) -> some View { TextField(p, text: b).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface)) }
}

/// «تقييد (إدارة)»: read-only for a set time, lifted automatically — admins or a role with «تقييد أعضاء المجتمع».
struct LimitSheet: View {
    let m: Member
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Double = 24
    @State private var days = ""
    @State private var note = ""
    @State private var busy = false
    @State private var err: String?
    private let opts: [(Double, String)] = [(1, "ساعة"), (6, "٦ ساعات"), (24, "يوم"), (72, "٣ أيام"), (168, "أسبوع"), (720, "شهر"), (-1, "عدد أيام…")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("تقييد \u{2066}@\(m.handle)\u{2069}").font(F.amiri(24)).foregroundStyle(c.text)
                if m.limitedNow { Text("مقيّد حاليًا حتى \(Community.limitDate(m.limitedUntil)).").font(F.plex(14)).foregroundStyle(c.gold) }
                Text("المقيَّد يتصفح ويقرأ فقط: لا ينشر ولا يرد ولا يعيد النشر ولا يعجب ولا يتابع حتى تنتهي المدة، ثم يُرفع التقييد تلقائيًا.").font(F.plex(13)).foregroundStyle(c.muted).fixedSize(horizontal: false, vertical: true)
                Text("المدة").font(F.plex(14, .bold)).foregroundStyle(c.text)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(opts, id: \.0) { o in Pill(title: o.1, on: hours == o.0) { hours = o.0 } }
                }
                if hours < 0 { TextField("عدد الأيام (1–365)", text: $days).keyboardType(.numberPad).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface)) }
                TextField("السبب (يظهر له — اختياري)", text: $note).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                if let err { Text(err).font(F.plex(13)).foregroundStyle(c.danger) }
                GoldButton(title: busy ? "لحظات…" : "تقييد الحساب", icon: "shield") {
                    let h = hours < 0 ? Double((Int(days) ?? 0) * 24) : hours
                    if h <= 0 { err = "اكتب عدد أيام التقييد"; return }
                    send(h)
                }.frame(maxWidth: .infinity)
                GhostButton(title: "إلغاء التقييد") { send(0) }.frame(maxWidth: .infinity)
            }.padding(20)
        }.background(Backdrop()).presentationDetents([.medium, .large])
    }
    private func send(_ h: Double) {
        guard !busy else { return }; busy = true; err = nil
        Task {
            do { let t = try await cm.limit(m.handle, hours: h, note: h > 0 ? note.trimmingCharacters(in: .whitespaces) : ""); ui.say(t > 0 ? "قُيّد @\(m.handle) حتى \(Community.limitDate(t))" : "أُلغي تقييد @\(m.handle)"); dismiss() }
            catch { err = Community.msg(error) }
            busy = false
        }
    }
}
struct EditProfileSheet: View {
    @EnvironmentObject var cm: Community
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bio = ""
    @State private var location = ""
    @State private var email = ""
    @State private var busy = false
    @State private var err: String?
    @State private var askDel = false
    @State private var delPass = ""
    @State private var delErr: String?
    @State private var avatarPick: PhotosPickerItem?
    @State private var avatarPath: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("تعديل الملف الشخصي").font(F.amiri(24)).foregroundStyle(c.text)
                PhotosPicker(selection: $avatarPick, matching: .images) { HStack { Avatar(m: cm.me, size: 64); Text("تغيير الصورة").font(F.plex(14)).foregroundStyle(c.gold) } }
                TextField("الاسم", text: $name).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                TextField("نبذة", text: $bio, axis: .vertical).lineLimit(2...5).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                TextField("المكان", text: $location).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                TextField("البريد الإلكتروني (لاستعادة الحساب)", text: $email).textInputAutocapitalization(.never).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                if let err { Text(err).font(F.plex(13)).foregroundStyle(c.danger) }
                HStack {
                    GoldButton(title: busy ? "لحظات…" : "حفظ", icon: "checkmark") {
                        guard let me = cm.me, !busy else { return }; busy = true
                        var f = ["name": name, "handle": me.handle, "bio": bio, "location": location, "website": "", "email": email]
                        if let a = avatarPath { f["avatar"] = a }
                        Task { do { try await cm.saveProfile(f); ui.say("حُفظ ملفك الشخصي"); dismiss() } catch { err = Community.msg(error) }; busy = false }
                    }
                    GhostButton(title: "خروج", icon: "rectangle.portrait.and.arrow.right") { Task { await cm.logout(); ui.say("سُجّل خروجك"); dismiss() } }
                }
                Divider().overlay(c.line).padding(.vertical, 8)
                if !askDel {
                    Button { askDel = true } label: { Label("حذف حسابي", systemImage: "trash").font(F.plex(15, .semibold)).foregroundStyle(c.danger) }
                } else {
                    Text("حذف الحساب نهائيًا").font(F.plex(15, .bold)).foregroundStyle(c.danger)
                    Text("سيُحذف حسابك وكل منشوراتك وردودك وصورك وإعجاباتك ومتابعاتك فورًا، ولا يمكن التراجع. اكتب كلمة المرور للتأكيد.").font(F.plex(13)).foregroundStyle(c.muted)
                    SecureField("كلمة المرور", text: $delPass).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                    if let delErr { Text(delErr).font(F.plex(13)).foregroundStyle(c.danger) }
                    HStack {
                        GhostButton(title: "إلغاء") { askDel = false; delPass = "" }
                        Button { Task { do { try await cm.deleteAccount(delPass); ui.say("حُذف حسابك وكل بياناته"); dismiss() } catch { delErr = Community.msg(error) } } } label: {
                            Text("احذف نهائيًا").font(F.plex(15, .bold)).foregroundStyle(.white).padding(.horizontal, 20).frame(minHeight: 48).background(Capsule().fill(c.danger))
                        }
                    }
                }
                Link("سياسة الخصوصية", destination: URL(string: Repo.site + "privacy")!).font(F.plex(12)).foregroundStyle(c.faint)
            }.padding(22).font(F.plex(15))
        }
        .background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, .rightToLeft)
        .onAppear { name = cm.me?.name ?? ""; bio = cm.me?.bio ?? ""; location = cm.me?.location ?? ""; email = cm.me?.email ?? "" }
        .onChange(of: avatarPick) { it in
            Task { if let d = try? await it?.loadTransferable(type: Data.self), let img = UIImage(data: d), let m = try? await cm.upload(img, kind: "avatar") { avatarPath = m.path; ui.say("رُفعت الصورة — اضغط حفظ") } }
        }
    }
}
