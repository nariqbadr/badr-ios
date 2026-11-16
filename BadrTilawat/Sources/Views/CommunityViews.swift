import SwiftUI
import PhotosUI

/// Followers / following as a full screen with tabs, search and endless scrolling (as on X).
struct PeopleView: View {
    let handle: String
    @State var list: String
    @EnvironmentObject var cm: Community
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
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
    private let tabs = [("verified", tr("الموثَّقون")), ("followers", tr("المتابِعون")), ("following", tr("يتابع"))]
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    HStack(spacing: 8) {
                        Ico(name: "magnifyingglass", size: 20).foregroundStyle(c.muted)
                        TextField(tr("ابحث بالاسم أو المعرّف"), text: $q).font(F.plex(15)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        if !q.isEmpty { Button { q = "" } label: { Ico(name: "xmark.circle.fill", size: 20).foregroundStyle(c.muted) } }
                    }.padding(.horizontal, 14).frame(height: 42).background(Capsule().fill(c.surface)).padding(.horizontal, 16).padding(.vertical, 10)
                    ForEach(rows) { m in row(m); Divider().overlay(c.lineSoft) }
                    if loading { ProgressView().frame(maxWidth: .infinity).padding(24) }
                    else if rows.isEmpty { Empty(text: err ?? (sent.isEmpty ? (list == "verified" ? tr("لا يوجد متابِعون موثَّقون بعد.") : list == "following" ? tr("لا يتابع أحدًا بعد.") : tr("لا يوجد متابِعون بعد.")) : tr("لا توجد نتائج مطابقة.")), icon: "person.2") }
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
                            if m.followsMe && cm.me != nil { Text(tr("يتابعك")).font(F.plex(11)).foregroundStyle(c.muted).padding(.horizontal, 6).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 6).fill(c.surface2)) }
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
                    Task { if let e = await cm.follow(m.handle, !on) { following[m.handle] = on; ui.say(e) } else { ui.say(!on ? tr("تتابع @{0} الآن", m.handle) : tr("ألغيت متابعة @{0}", m.handle)) } }
                } label: {
                    Text(on ? tr("تتابعه") : tr("متابعة")).font(F.plex(13.5, .bold)).foregroundStyle(on ? c.text : c.onGold)
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

struct ComposeView: View {
    let embed: String
    @EnvironmentObject var cm: Community
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
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
                    Empty(text: tr("سجّل الدخول لتنشر في المجتمع."), icon: "lock")
                    GoldButton(title: tr("تسجيل الدخول")) { auth = true }.frame(maxWidth: .infinity)
                } else if let me = cm.me, me.limitedNow {
                    HStack(alignment: .top, spacing: 10) {
                        Ico(name: "shield", size: 20).foregroundStyle(c.gold)
                        Text(Community.limitMsg(me.limitedUntil, me.limitNote)).font(F.plex(14)).foregroundStyle(c.text).fixedSize(horizontal: false, vertical: true)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(c.gold.opacity(0.08))).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.gold.opacity(0.35)))
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        Avatar(m: cm.me, size: 42)
                        TextField(reply > 0 ? tr("اكتب ردّك…") : tr("بماذا تفكر؟"), text: $text, axis: .vertical).font(F.plex(16)).lineLimit(4...12)
                    }
                    if !att.isEmpty { PostEmbed(e: att) }
                    ScrollView(.horizontal) { HStack { ForEach(media, id: \.self) { m in RemoteImage(raw: m.url).frame(width: 110, height: 110).clipShape(RoundedRectangle(cornerRadius: 14)) } } }
                    if let err { Text(err).font(F.plex(13)).foregroundStyle(c.danger) }
                    HStack {
                        PhotosPicker(selection: $pick, maxSelectionCount: 4, matching: .images) { Ico(name: "photo", size: 24.0).foregroundStyle(c.gold) }
                        Spacer()
                        Text("\((280 - text.count).ar)").font(F.plex(12)).foregroundStyle(text.count > 280 ? c.danger : c.muted)
                        GoldButton(title: busy ? tr("لحظات…") : (reply > 0 ? tr("ردّ") : tr("نشر"))) {
                            guard !busy else { return }
                            busy = true; err = nil
                            Task {
                                do { try await cm.post(text: text, media: media, embed: att, replyTo: reply, quoteOf: quote); ui.say(tr("نُشر ✓")); ui.path.removeLast() }
                                catch { err = Community.msg(error) }
                                busy = false
                            }
                        }
                    }
                }
            }.padding(18)
        }
        .background(Backdrop()).navigationTitle(reply > 0 ? tr("ردّ") : quote > 0 ? tr("اقتباس") : tr("منشور جديد")).navigationBarTitleDisplayMode(.inline)
        .task { await cm.loadMe() }
        .onChange(of: pick) { items in
            Task {
                for it in items { if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { do { media.append(try await cm.upload(img)) } catch { err = Community.msg(error) } } }
                pick = []
            }
        }
        .bzSheet(isPresented: $auth) { AuthSheet() }
    }
}

struct AuthSheet: View {
    @EnvironmentObject var cm: Community
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
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
                Text(mode == "forgot" ? tr("نسيت كلمة المرور") : tr("رمز التحقق")).font(F.amiri(26)).foregroundStyle(c.text)
                Text(mode == "forgot" ? tr("اكتب اسم المستخدم أو البريد المسجّل في حسابك، وسنرسل رمز تحقق من ٦ أرقام إلى بريدك.")
                     : tr("إن كان الحساب مرتبطًا ببريد، فقد أرسلنا إليه رمزًا من ٦ أرقام صالحًا ١٥ دقيقة. راجع البريد الوارد ومجلد الرسائل غير المرغوب فيها (Spam)."))
                    .font(F.plex(13.5)).foregroundStyle(c.muted).fixedSize(horizontal: false, vertical: true)
                if mode == "forgot" {
                    TextField(tr("اسم المستخدم أو البريد"), text: $handle).textInputAutocapitalization(.never).autocorrectionDisabled().padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                } else {
                    TextField(tr("رمز التحقق (٦ أرقام)"), text: Binding(get: { code }, set: { v in
                        let digits = v.map { ch -> Character in if let d = tr("٠١٢٣٤٥٦٧٨٩").firstIndex(of: ch) { return Character(String(tr("٠١٢٣٤٥٦٧٨٩").distance(from: tr("٠١٢٣٤٥٦٧٨٩").startIndex, to: d))) }; return ch }.filter { $0.isASCII && $0.isNumber }
                        code = String(String(digits).prefix(6)) }))
                        .keyboardType(.numberPad).textContentType(.oneTimeCode).multilineTextAlignment(.center).font(.system(size: 22, weight: .semibold, design: .rounded))
                        .environment(\.layoutDirection, .leftToRight).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                    SecureField(tr("كلمة المرور الجديدة (8 أحرف على الأقل)"), text: $pass).textContentType(.newPassword).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                }
                if let err { Text(err).font(F.plex(13)).foregroundStyle(c.danger) }
                GoldButton(title: busy ? tr("لحظات…") : (mode == "forgot" ? tr("إرسال الرمز") : tr("تغيير كلمة المرور"))) {
                    guard !busy else { return }
                    let login = handle.trimmingCharacters(in: .whitespaces)
                    if mode == "forgot" && login.isEmpty { err = tr("اكتب اسم المستخدم أو البريد."); return }
                    if mode == "code" && code.count != 6 { err = tr("اكتب الرمز المكوّن من ٦ أرقام."); return }
                    if mode == "code" && pass.count < 8 { err = tr("كلمة المرور 8 أحرف على الأقل."); return }
                    busy = true; err = nil
                    Task {
                        do {
                            if mode == "forgot" { try await cm.forgotSend(login); pass = ""; mode = "code" }
                            else {
                                let u = try await cm.forgotReset(login, code: code, password: pass)
                                do { try await cm.login(u, pass); ui.say(tr("تم تغيير كلمة المرور — أهلًا بك")); dismiss() }
                                catch { ui.say(tr("تم تغيير كلمة المرور — سجّل الدخول بها الآن")); mode = ""; signup = false }
                            }
                        } catch { err = Community.msg(error); if (error as? CmError)?.code == "code_expired" { code = "" } }
                        busy = false
                    }
                }.frame(maxWidth: .infinity)
                Button(mode == "code" ? tr("لم يصلك الرمز؟ أرسله مرة أخرى") : tr("رجوع إلى تسجيل الدخول")) {
                    if mode == "code" { Task { do { try await cm.forgotSend(handle.trimmingCharacters(in: .whitespaces)); ui.say(tr("أُرسل رمز جديد إن كان الحساب مرتبطًا ببريد")) } catch { ui.say(Community.msg(error)) } } }
                    else { mode = ""; err = nil }
                }.font(F.plex(14, .semibold)).foregroundStyle(c.gold).frame(maxWidth: .infinity)
            }.padding(22).font(F.plex(15))
        }.background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir)
    }
    private var authForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(signup ? tr("إنشاء حساب") : tr("تسجيل الدخول")).font(F.amiri(26)).foregroundStyle(c.text)
                HStack { Pill(title: tr("دخول"), on: !signup) { signup = false }; Pill(title: tr("حساب جديد"), on: signup) { signup = true } }
                if signup { field(tr("الاسم"), $name) }
                TextField(signup ? tr("اسم المستخدم (إنجليزي)") : tr("اسم المستخدم أو البريد"), text: Binding(get: { handle }, set: { v in
                    if signup { let ok = String(v.lowercased().replacingOccurrences(of: " ", with: "_").filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }.prefix(20)); rejected = ok.count < min(20, v.count); handle = ok } else { handle = v }
                })).textInputAutocapitalization(.never).autocorrectionDisabled().padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                if signup { Text(rejected ? tr("اسم المستخدم بالحروف الإنجليزية فقط — غيّر لغة لوحة المفاتيح إلى الإنجليزية") : tr("حروف إنجليزية وأرقام و _ (3–20)، واكتب اسمك العربي في خانة «الاسم»")).font(F.plex(11.5)).foregroundStyle(rejected ? c.danger : c.faint) }
                SecureField(signup ? tr("كلمة المرور (8 أحرف على الأقل)") : tr("كلمة المرور"), text: $pass).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                if signup {
                    TextField(tr("البريد الإلكتروني"), text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                }
                if signup { Text(tr("بإنشاء الحساب توافق على آداب المجتمع: لا محتوى مسيئًا أو مخالفًا أو إساءة لأحد. يمكنك الإبلاغ عن أي منشور وحظر أي حساب، وتراجع الإدارة البلاغات وتحذف المخالف وتوقف صاحبه.")).font(F.plex(11.5)).foregroundStyle(c.muted).fixedSize(horizontal: false, vertical: true) }
                if let err { Text(err).font(F.plex(13)).foregroundStyle(c.danger) }
                GoldButton(title: busy ? tr("لحظات…") : (signup ? tr("إنشاء الحساب") : tr("دخول"))) {
                    guard !busy else { return }
                    if signup && email.trimmingCharacters(in: .whitespaces).isEmpty { err = tr("اكتب بريدك الإلكتروني — نحتاجه لإرسال رمز استعادة الحساب إن نسيت كلمة المرور."); return }
                    busy = true; err = nil
                    Task {
                        do { if signup { try await cm.register(name: name, handle: handle, password: pass, email: email) } else { try await cm.login(handle.trimmingCharacters(in: .whitespaces), pass) }
                             ui.say(tr("أهلًا {0}", cm.me?.name ?? "")); dismiss() }
                        catch { err = Community.msg(error) }
                        busy = false
                    }
                }.frame(maxWidth: .infinity)
                if !signup { Button(tr("نسيت كلمة المرور؟")) { mode = "forgot"; err = nil }.font(F.plex(14, .semibold)).foregroundStyle(c.gold).frame(maxWidth: .infinity) }
                Link(tr("سياسة الخصوصية"), destination: URL(string: Repo.site + "privacy")!).font(F.plex(12)).foregroundStyle(c.faint)
            }.padding(22).font(F.plex(15))
        }.background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir)
    }
    private func field(_ p: String, _ b: Binding<String>) -> some View { TextField(p, text: b).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface)) }
}

/// «تقييد (إدارة)»: read-only for a set time, lifted automatically — admins or a role with «تقييد أعضاء المجتمع».
struct LimitSheet: View {
    let m: Member
    @EnvironmentObject var cm: Community
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Double = 24
    @State private var days = ""
    @State private var note = ""
    @State private var busy = false
    @State private var err: String?
    private let opts: [(Double, String)] = [(1, tr("ساعة")), (6, tr("٦ ساعات")), (24, tr("يوم")), (72, tr("٣ أيام")), (168, tr("أسبوع")), (720, tr("شهر")), (-1, tr("عدد أيام…"))]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("تقييد \u{2066}@{0}\u{2069}", m.handle)).font(F.amiri(24)).foregroundStyle(c.text)
                if m.limitedNow { Text(tr("مقيّد حاليًا حتى {0}.", Community.limitDate(m.limitedUntil))).font(F.plex(14)).foregroundStyle(c.gold) }
                Text(tr("المقيَّد يتصفح ويقرأ فقط: لا ينشر ولا يرد ولا يعيد النشر ولا يعجب ولا يتابع حتى تنتهي المدة، ثم يُرفع التقييد تلقائيًا.")).font(F.plex(13)).foregroundStyle(c.muted).fixedSize(horizontal: false, vertical: true)
                Text(tr("المدة")).font(F.plex(14, .bold)).foregroundStyle(c.text)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(opts, id: \.0) { o in Pill(title: o.1, on: hours == o.0) { hours = o.0 } }
                }
                if hours < 0 { TextField(tr("عدد الأيام (1–365)"), text: $days).keyboardType(.numberPad).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface)) }
                TextField(tr("السبب (يظهر له — اختياري)"), text: $note).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                if let err { Text(err).font(F.plex(13)).foregroundStyle(c.danger) }
                GoldButton(title: busy ? tr("لحظات…") : tr("تقييد الحساب"), icon: "shield") {
                    let h = hours < 0 ? Double((Int(days) ?? 0) * 24) : hours
                    if h <= 0 { err = tr("اكتب عدد أيام التقييد"); return }
                    send(h)
                }.frame(maxWidth: .infinity)
                GhostButton(title: tr("إلغاء التقييد")) { send(0) }.frame(maxWidth: .infinity)
            }.padding(20)
        }.background(Backdrop()).presentationDetents([.medium, .large])
    }
    private func send(_ h: Double) {
        guard !busy else { return }; busy = true; err = nil
        Task {
            do { let t = try await cm.limit(m.handle, hours: h, note: h > 0 ? note.trimmingCharacters(in: .whitespaces) : ""); ui.say(t > 0 ? tr("قُيّد @{0} حتى {1}", m.handle, Community.limitDate(t)) : tr("أُلغي تقييد @{0}", m.handle)); dismiss() }
            catch { err = Community.msg(error) }
            busy = false
        }
    }
}
struct EditProfileSheet: View {
    @EnvironmentObject var cm: Community
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
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
                Text(tr("تعديل الملف الشخصي")).font(F.amiri(24)).foregroundStyle(c.text)
                PhotosPicker(selection: $avatarPick, matching: .images) { HStack { Avatar(m: cm.me, size: 64); Text(tr("تغيير الصورة")).font(F.plex(14)).foregroundStyle(c.gold) } }
                TextField(tr("الاسم"), text: $name).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                TextField(tr("نبذة"), text: $bio, axis: .vertical).lineLimit(2...5).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                TextField(tr("المكان"), text: $location).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                TextField(tr("البريد الإلكتروني (لاستعادة الحساب)"), text: $email).textInputAutocapitalization(.never).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                if let err { Text(err).font(F.plex(13)).foregroundStyle(c.danger) }
                HStack {
                    GoldButton(title: busy ? tr("لحظات…") : tr("حفظ"), icon: "checkmark") {
                        guard let me = cm.me, !busy else { return }; busy = true
                        var f = ["name": name, "handle": me.handle, "bio": bio, "location": location, "website": "", "email": email]
                        if let a = avatarPath { f["avatar"] = a }
                        Task { do { try await cm.saveProfile(f); ui.say(tr("حُفظ ملفك الشخصي")); dismiss() } catch { err = Community.msg(error) }; busy = false }
                    }
                    GhostButton(title: tr("خروج"), icon: "rectangle.portrait.and.arrow.right") { Task { await cm.logout(); ui.say(tr("سُجّل خروجك")); dismiss() } }
                }
                Divider().overlay(c.line).padding(.vertical, 8)
                if !askDel {
                    Button { askDel = true } label: { Label(tr("حذف حسابي"), systemImage: "trash").font(F.plex(15, .semibold)).foregroundStyle(c.danger) }
                } else {
                    Text(tr("حذف الحساب نهائيًا")).font(F.plex(15, .bold)).foregroundStyle(c.danger)
                    Text(tr("سيُحذف حسابك وكل منشوراتك وردودك وصورك وإعجاباتك ومتابعاتك فورًا، ولا يمكن التراجع. اكتب كلمة المرور للتأكيد.")).font(F.plex(13)).foregroundStyle(c.muted)
                    SecureField(tr("كلمة المرور"), text: $delPass).padding(13).background(RoundedRectangle(cornerRadius: 14).fill(c.surface))
                    if let delErr { Text(delErr).font(F.plex(13)).foregroundStyle(c.danger) }
                    HStack {
                        GhostButton(title: tr("إلغاء")) { askDel = false; delPass = "" }
                        Button { Task { do { try await cm.deleteAccount(delPass); ui.say(tr("حُذف حسابك وكل بياناته")); dismiss() } catch { delErr = Community.msg(error) } } } label: {
                            Text(tr("احذف نهائيًا")).font(F.plex(15, .bold)).foregroundStyle(.white).padding(.horizontal, 20).frame(minHeight: 48).background(Capsule().fill(c.danger))
                        }
                    }
                }
                Link(tr("سياسة الخصوصية"), destination: URL(string: Repo.site + "privacy")!).font(F.plex(12)).foregroundStyle(c.faint)
            }.padding(22).font(F.plex(15))
        }
        .background(c.bg2.ignoresSafeArea()).environment(\.layoutDirection, L.dir)
        .onAppear { name = cm.me?.name ?? ""; bio = cm.me?.bio ?? ""; location = cm.me?.location ?? ""; email = cm.me?.email ?? "" }
        .onChange(of: avatarPick) { it in
            Task { if let d = try? await it?.loadTransferable(type: Data.self), let img = UIImage(data: d), let m = try? await cm.upload(img, kind: "avatar") { avatarPath = m.path; ui.say(tr("رُفعت الصورة — اضغط حفظ")) } }
        }
    }
}

var REPORT_REASONS: [String] { [tr("محتوى مسيء أو غير لائق"), tr("إساءة أو تحرش"), tr("رسائل مزعجة (سبام)"), tr("معلومات مضللة"), tr("انتحال شخصية"), tr("سبب آخر")] }
var BLOCK_NOTE: String { tr("لن يتمكن من متابعتك أو رؤية منشوراتك أو التفاعل معك، ولن ترى منشوراته. تُلغى المتابعة بينكما.") }
var REL_DONE: [String: (String, String)] { ["block": (tr("حُظر الحساب — لن يرى منشوراتك ولن يتفاعل معك"), tr("أُلغي الحظر")), "mute": (tr("كُتم الحساب — لن تظهر لك منشوراته"), tr("أُلغي الكتم"))] }

/// «الحظر والكتم»: the accounts I blocked or muted, with undo.
struct BlockedView: View {
    @EnvironmentObject var cm: Community
    /* UI actions only: reading it does not redraw this view on every tab or sheet change */ private var ui: UIState { UIState.shared! }
    @Environment(\.pal) private var c
    @State private var kind = "block"
    @State private var list: [Member]?
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $kind) { Text(tr("المحظورون")).tag("block"); Text(tr("المكتومون")).tag("mute") }.pickerStyle(.segmented).padding(16)
            if let list {
                if list.isEmpty { Empty(text: kind == "block" ? tr("لم تحظر أحدًا.") : tr("لم تكتم أحدًا."), icon: "hand.raised"); Spacer() }
                else {
                    List(list) { m in
                        HStack(spacing: 10) {
                            Avatar(m: m, size: 40)
                            VStack(alignment: .leading) { Text(m.name).font(F.plex(14.5, .bold)); Text("\u{2066}@\(m.handle)\u{2069}").font(F.plex(12)).foregroundStyle(c.faint) }
                            Spacer()
                            GhostButton(title: kind == "block" ? tr("إلغاء الحظر") : tr("إلغاء الكتم")) {
                                Task { do { try await cm.rel(m.handle, kind, false); self.list = self.list?.filter { $0.id != m.id }; ui.say(REL_DONE[kind]!.1) } catch { ui.say(Community.msg(error)) } }
                            }
                        }.listRowBackground(Color.clear)
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            } else { ProgressView().padding(40); Spacer() }
        }
        .task(id: kind) { list = nil; do { list = try await cm.rels(kind) } catch { list = []; ui.say(Community.msg(error)) } }
        .navigationTitle(tr("الحظر والكتم")).navigationBarTitleDisplayMode(.inline)
    }
}
