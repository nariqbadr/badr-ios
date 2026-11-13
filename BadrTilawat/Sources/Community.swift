import Foundation
import UIKit

struct Member: Identifiable, Hashable {
    let id: Int, handle: String, name: String, avatar: String, badges: [String], bio: String, cover: String, location: String
    let followers: Int, following: Int, posts: Int, iFollow: Bool, followsMe: Bool, email: String
    /// admin limit (read-only until this time); canLimit: this account may limit others (admin or «مشرف المجتمع»)
    let limitedUntil: Int, limitNote: String, canLimit: Bool
    /// my relation with this account: I blocked / muted it, or it blocked me
    let blocked: Bool, muted: Bool, blockedMe: Bool
    var limitedNow: Bool { Double(limitedUntil) > Date().timeIntervalSince1970 }
    init(_ j: J) {
        id = j["id"].int; handle = j["handle"].str; name = j["name"].str.isEmpty ? j["handle"].str : j["name"].str; avatar = j["avatar"].str
        var b = j["badges"].strings
        if b.isEmpty { switch j["verified"].int { case 1: b = ["verified"]; case 2: b = ["official"]; case 3, 9: b = ["owner"]; default: break } }
        badges = b; bio = j["bio"].str; cover = j["cover"].str; location = j["location"].str
        followers = j["followers"].int; following = j["following"].int; posts = j["posts"].int; iFollow = j["iFollow"].bool(); followsMe = j["followsMe"].bool(); email = j["email"].str
        limitedUntil = j["limitedUntil"].int; limitNote = j["limitNote"].str; canLimit = j["canLimit"].bool()
        blocked = j["rel"]["block"].bool(); muted = j["rel"]["mute"].bool(); blockedMe = j["rel"]["blockedMe"].bool()
    }
}
struct CMedia: Hashable { let type: String, url: String, path: String, w: Int, h: Int
    init(_ j: J) { type = j["type"].str; url = j["url"].str; path = j["path"].str; w = j["w"].int; h = j["h"].int }
    init(type: String, url: String, path: String, w: Int, h: Int) { self.type = type; self.url = url; self.path = path; self.w = w; self.h = h }
    var json: [String: Any] { ["type": type, "url": url, "path": path, "w": w, "h": h] }
}
final class Post: Identifiable, Hashable {
    let id: Int, author: Member?, text: String, media: [CMedia], embed: String, created: Date
    var likes: Int, reposts: Int, replies: Int, liked: Bool, reposted: Bool
    let quote: Post?, replyToHandle: String, mine: Bool
    init(_ j: J) {
        id = j["id"].int; author = j["author"].isNull ? nil : Member(j["author"]); text = j["text"].str; media = j["media"].array.map(CMedia.init); embed = j["embed"].str
        created = Date(timeIntervalSince1970: Double(j["created"].int)); likes = j["likes"].int; reposts = j["reposts"].int; replies = j["replies"].int
        liked = j["liked"].bool(); reposted = j["reposted"].bool(); quote = j["quote"].isNull ? nil : Post(j["quote"]); replyToHandle = j["replyTo"]["handle"].str; mine = j["mine"].bool()
    }
    static func == (a: Post, b: Post) -> Bool { a.id == b.id && a.likes == b.likes && a.liked == b.liked && a.reposts == b.reposts }
    func hash(into h: inout Hasher) { h.combine(id) }
}
struct FeedItem: Identifiable { let key: Int; let post: Post; let repostBy: Member?; var id: Int { key == 0 ? post.id : key } }

struct CmError: Error { let code: String; let data: J? }

/// «المجتمع»: the same endpoints and session (cookie + X-BZC-CSRF) as the website and the Android app.
@MainActor
final class Community: ObservableObject {
    static let shared = Community()
    @Published var me: Member?
    @Published var unread = 0
    @Published var relRev = 0
    @Published var allowSignup = true
    private var csrf = ""

    static let badges: [(String, String, String)] = [("owner", "مالك الموقع", "crown.fill"), ("admin", "إدارة الموقع", "shield.fill"), ("mod", "مشرف", "shield.lefthalf.filled"),
        ("official", "حساب رسمي", "checkmark.seal.fill"), ("verified", "حساب موثّق", "checkmark.seal.fill"), ("reciter", "قارئ", "mic.fill"),
        ("teacher", "معلّم ومحفّظ", "book.fill"), ("supporter", "داعم للموقع", "heart.fill"), ("founder", "عضو مؤسس", "star.fill")]

    static let errors: [String: String] = [
        "c_login_required": "سجّل الدخول أولًا.", "csrf": "انتهت الجلسة — حاول مرة أخرى.", "c_disabled": "المجتمع متوقف حاليًا.", "c_signup_closed": "التسجيل مغلق حاليًا.",
        "c_name_required": "اكتب اسمك.", "c_bad_handle": "اسم المستخدم من 3 إلى 20 حرفًا إنجليزيًا أو أرقام أو _ فقط.",
        "c_handle_taken": "اسم المستخدم هذا مسجّل مسبقًا. إن كان حسابك فسجّل الدخول، وإلا فاختر اسمًا آخر.", "c_handle_staff": "اسم المستخدم هذا مسجّل مسبقًا.",
        "password_too_short": "كلمة المرور 8 أحرف على الأقل.", "c_bad_email": "البريد غير صحيح.", "c_email_taken": "هذا البريد مسجّل بحساب آخر.",
        "c_email_required": "اكتب بريدك الإلكتروني — نحتاجه لإرسال رمز استعادة الحساب إن نسيت كلمة المرور.", "mail_not_ready": "إرسال البريد غير مفعّل في الموقع بعد — تواصل مع إدارة الموقع.", "mail_failed": "تعذّر إرسال البريد الآن — حاول بعد قليل.",
        "too_many": "محاولات كثيرة — انتظر قليلًا ثم حاول مجددًا.", "bad_code": "رمز التحقق غير صحيح.", "code_expired": "انتهت صلاحية الرمز — اطلب رمزًا جديدًا.",
        "invalid_login": "اسم المستخدم أو كلمة المرور غير صحيحة.", "locked": "محاولات كثيرة — انتظر ربع ساعة.", "c_suspended": "هذا الحساب موقوف.",
        "c_slow_down": "أنت تنشر بسرعة — انتظر قليلًا.", "c_too_long": "المنشور أطول من المسموح.", "c_empty": "اكتب شيئًا أو أضف صورة.",
        "c_post_gone": "هذا المنشور لم يعد موجودًا.", "c_limited": "حسابك مقيّد مؤقتًا من الإدارة.", "c_cant_limit": "لا يمكن تقييد هذا الحساب.", "forbidden": "ليس لديك صلاحية لهذا الإجراء.", "file_too_large": "الملف أكبر من المسموح.", "type_not_allowed": "نوع الملف غير مدعوم.", "network": "تعذّر الاتصال — تحقق من الإنترنت.",
    ]
    static func limitDate(_ t: Int) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ar"); f.dateFormat = "d MMMM 'في' h:mm a"
        return f.string(from: Date(timeIntervalSince1970: Double(t)))
    }
    static func limitMsg(_ until: Int, _ note: String) -> String {
        "حسابك مقيّد مؤقتًا من الإدارة حتى \(limitDate(until))" + (note.isEmpty ? "" : " — \(note)") + ". يمكنك التصفح والقراءة فقط."
    }
    static func msg(_ e: Error) -> String {
        if let c = e as? CmError, c.code == "c_limited", let d = c.data, d["until"].int > 0 { return limitMsg(d["until"].int, d["note"].str) }
        return (e as? CmError).flatMap { errors[$0.code] } ?? "حدث خطأ — حاول مرة أخرى."
    }

    func api(_ action: String, query: [String: String] = [:], form: [String: String]? = nil, file: (name: String, mime: String, data: Data)? = nil, retry: Bool = true) async throws -> J {
        var u = Repo.ajax + "?action=bz&do=" + action
        for (k, v) in query { u += "&\(k)=" + Repo.enc(v) }
        var req = URLRequest(url: URL(string: u)!)
        if !csrf.isEmpty { req.setValue(csrf, forHTTPHeaderField: "X-BZC-CSRF") }
        if form != nil || file != nil {
            let b = "----bz\(UUID().uuidString)"
            var body = Data()
            for (k, v) in form ?? [:] { body.append("--\(b)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!) }
            if let f = file {
                body.append("--\(b)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(f.name)\"\r\nContent-Type: \(f.mime)\r\n\r\n".data(using: .utf8)!)
                body.append(f.data); body.append("\r\n".data(using: .utf8)!)
            }
            body.append("--\(b)--\r\n".data(using: .utf8)!)
            req.httpMethod = "POST"; req.setValue("multipart/form-data; boundary=\(b)", forHTTPHeaderField: "Content-Type"); req.httpBody = body
            req.timeoutInterval = 180
        }
        let d: Data, code: Int
        do { let (x, r) = try await Repo.shared.session.data(for: req); d = x; code = (r as? HTTPURLResponse)?.statusCode ?? 0 } catch { throw CmError(code: "network", data: nil) }
        let j = J(data: d)
        if j.isNull { throw CmError(code: "network", data: nil) }
        if code >= 400 || j["ok"].raw as? Bool == false {
            let err = j["error"].str.isEmpty ? "error" : j["error"].str
            if retry && (err == "csrf" || err == "c_login_required") && form != nil { await loadMe(); if me != nil { return try await api(action, query: query, form: form, file: file, retry: false) } }
            throw CmError(code: err, data: j)
        }
        return j
    }

    func loadMe() async {
        guard let j = try? await api("c_me", retry: false) else { return }
        csrf = j["csrf"].str; me = j["me"].isNull ? nil : Member(j["me"]); unread = j["unread"].int
        allowSignup = j["cfg"]["allowSignup"].bool(true)
    }
    private func session(_ j: J) { csrf = j["csrf"].str; me = j["me"].isNull ? nil : Member(j["me"]) }
    func login(_ handle: String, _ password: String) async throws { session(try await api("c_login", form: ["handle": handle, "password": password, "newHandle": ""])) }
    /// «نسيت كلمة المرور»: a 6-digit code to the account's e-mail, then the new password (returns the username to sign in with).
    func forgotSend(_ login: String) async throws { _ = try await api("forgot_send", form: ["who": "member", "login": login]) }
    func forgotReset(_ login: String, code: String, password: String) async throws -> String {
        let j = try await api("forgot_reset", form: ["who": "member", "login": login, "code": code, "password": password]); return j["login"].str.isEmpty ? login : j["login"].str }
    func register(name: String, handle: String, password: String, email: String) async throws { session(try await api("c_register", form: ["name": name, "handle": handle, "password": password, "email": email])) }
    func logout() async { _ = try? await api("c_logout", form: [:], retry: false); clear() }
    func deleteAccount(_ password: String) async throws { _ = try await api("c_delete_account", form: ["password": password], retry: false); clear() }
    private func clear() { HTTPCookieStorage.shared.cookies?.filter { $0.name.hasPrefix("bzc") }.forEach { HTTPCookieStorage.shared.deleteCookie($0) }; csrf = ""; me = nil; unread = 0 }

    struct Page { let items: [FeedItem]; let next: Int; let user: Member?; var blocked = false }
    private func page(_ j: J) -> Page {
        Page(items: j["items"].array.map { FeedItem(key: $0["key"].int, post: Post($0["post"]), repostBy: $0["repostBy"].isNull ? nil : Member($0["repostBy"])) }, next: j["next"].int, user: j["user"].isNull ? nil : Member(j["user"]), blocked: j["blocked"].bool())
    }
    func feed(_ tab: String, before: Int) async throws -> Page { page(try await api("c_feed", query: ["tab": tab, "before": "\(before)"])) }
    func user(_ handle: String, before: Int) async throws -> Page { page(try await api("c_user", query: ["handle": handle, "tab": "posts", "before": "\(before)"])) }
    /// One page (30) of followers / following / verified followers, optionally filtered by name or handle.
    func people(_ handle: String, list: String, off: Int, q: String) async throws -> (people: [Member], next: Int, user: Member?) {
        let j = try await api("c_people", query: ["handle": handle, "list": list, "off": "\(off)", "q": q])
        return (j["people"].array.map(Member.init), j["next"].int, j["user"].isNull ? nil : Member(j["user"]))
    }
    func thread(_ id: Int) async throws -> (Post, [Post]) {
        let j = try await api("c_thread", query: ["id": "\(id)", "view": "1"])
        return (Post(j["post"]), j["replies"].array.map(Post.init))
    }
    /// like / repost / follow return an error message to show (e.g. «حسابك مقيّد…»), or nil
    @discardableResult func like(_ p: Post) async -> String? { let on = !p.liked; p.liked = on; p.likes += on ? 1 : -1; objectWillChange.send()
        do { let j = try await api("c_like", form: ["id": "\(p.id)", "on": on ? "1" : "0"]); p.likes = j["likes"].int; objectWillChange.send(); return nil }
        catch { p.liked = !on; p.likes += on ? -1 : 1; objectWillChange.send(); return Community.msg(error) } }
    @discardableResult func repost(_ p: Post) async -> String? { let on = !p.reposted; p.reposted = on; p.reposts += on ? 1 : -1; objectWillChange.send()
        do { let j = try await api("c_repost", form: ["id": "\(p.id)", "on": on ? "1" : "0"]); p.reposts = j["reposts"].int; objectWillChange.send(); return nil }
        catch { p.reposted = !on; p.reposts += on ? -1 : 1; objectWillChange.send(); return Community.msg(error) } }
    @discardableResult func follow(_ handle: String, _ on: Bool) async -> String? {
        do { _ = try await api("c_follow", form: ["handle": handle, "on": on ? "1" : "0"]); return nil } catch { return Community.msg(error) } }
    /// admin limit: hours = 0 lifts it; returns the new end time
    func limit(_ handle: String, hours: Double, note: String) async throws -> Int {
        try await api("c_limit", form: ["handle": handle, "hours": "\(hours)", "note": note])["limitedUntil"].int }
    func delete(_ p: Post) async throws { _ = try await api("c_delete", form: ["id": "\(p.id)"]) }
    func report(_ p: Post, _ reason: String) async throws { _ = try await api("c_report", form: ["id": "\(p.id)", "reason": reason]) }
    /// block / mute (on = false undoes it); bumps relRev so open lists reload without that account
    func rel(_ handle: String, _ kind: String, _ on: Bool) async throws { _ = try await api("c_rel", form: ["handle": handle, "kind": kind, "on": on ? "1" : "0"]); relRev += 1 }
    func rels(_ kind: String) async throws -> [Member] { try await api("c_rels", query: ["kind": kind])["people"].array.map(Member.init) }
    func post(text: String, media: [CMedia], embed: String, replyTo: Int, quoteOf: Int) async throws {
        let m = String(data: (try? JSONSerialization.data(withJSONObject: media.map { $0.json })) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
        _ = try await api("c_post", form: ["text": text, "media": m, "embed": embed, "replyTo": "\(replyTo)", "quoteOf": "\(quoteOf)"])
    }
    func saveProfile(_ f: [String: String]) async throws { let j = try await api("c_profile_save", form: f); if !j["csrf"].str.isEmpty { csrf = j["csrf"].str }; await loadMe() }
    /// Images are scaled to ≤2048 px JPEG first, like the site.
    func upload(_ img: UIImage, kind: String = "post") async throws -> CMedia {
        let max: CGFloat = kind == "avatar" ? 800 : 2048
        let k = min(1, max / Swift.max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * k, height: img.size.height * k)
        let scaled = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        guard let d = scaled.jpegData(compressionQuality: 0.86) else { throw CmError(code: "type_not_allowed", data: nil) }
        let r = try await api("c_upload", form: ["kind": kind], file: ("image.jpg", "image/jpeg", d))
        return CMedia(type: "image", url: r["url"].str, path: r["path"].str, w: r["w"].int, h: r["h"].int)
    }
    static func num(_ n: Int) -> String { n >= 1000 ? String(format: "%.1fK", Double(n) / 1000).replacingOccurrences(of: ".0K", with: "K") : n.ar }
}
