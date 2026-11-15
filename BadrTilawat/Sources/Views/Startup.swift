import SwiftUI

/// First launch: location (prayer times for the user's city) and notifications (adhan).
struct Onboarding: View {
    let done: () -> Void
    @EnvironmentObject var prayers: Prayers
    @Environment(\.pal) private var c
    @State private var busy = false
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 14) {
                Image("Logo").resizable().scaledToFit().frame(width: 80)
                Text(tr("أهلًا بك")).font(F.amiri(32)).foregroundStyle(c.goldGradient)
                Text(tr("لتكون مواقيت الصلاة والأذان دقيقة لمدينتك، يحتاج التطبيق بعض الأذونات:")).font(F.plex(15)).foregroundStyle(c.muted).multilineTextAlignment(.center).padding(.bottom, 8)
                need("mappin.and.ellipse", tr("الموقع"), busy ? tr("جارٍ تحديد مدينتك…") : (prayers.place.isEmpty ? tr("لحساب مواقيت الصلاة واتجاه القبلة لمدينتك") : prayers.place))
                need("bell.badge", tr("الإشعارات"), tr("تنبيه الأذان وقبل الصلاة"))
                GoldButton(title: busy ? tr("لحظات…") : tr("سماح ومتابعة"), icon: "checkmark") {
                    guard !busy else { return }
                    busy = true
                    Task {
                        _ = await prayers.locate()
                        _ = await prayers.requestNotifications()
                        prayers.schedule(); busy = false; finish()
                    }
                }.padding(.top, 10)
                Button(tr("لاحقًا")) { Task { if !prayers.hasPlace { _ = await prayers.locateByIp() }; finish() } }.font(F.plex(14)).foregroundStyle(c.muted)
            }.padding(26).frame(maxWidth: 460)
        }
    }
    private func finish() { UserDefaults.standard.set(true, forKey: "onboarded"); done() }
    private func need(_ icon: String, _ t: String, _ s: String) -> some View {
        HStack(spacing: 12) {
            Ico(name: icon, size: 22, color: c.gold).frame(width: 40, height: 40).background(Circle().fill(c.gold.opacity(0.14)))
            VStack(alignment: .leading) { Text(t).font(F.plex(15, .semibold)).foregroundStyle(c.text); Text(s).font(F.plex(12.5)).foregroundStyle(c.muted) }
            Spacer()
        }.padding(14).background(RoundedRectangle(cornerRadius: 18).fill(c.surface.opacity(0.7)))
    }
}

/// What the dashboard («التحكم في التطبيق») asks the app to show: a required update, a new version, a message.
struct AppMessages: View {
    let site: Site
    @Environment(\.pal) private var c
    @State private var seenUpd = UserDefaults.standard.integer(forKey: "updSeenIos")
    @State private var seenNotice = UserDefaults.standard.string(forKey: "noticeSeen") ?? ""
    var body: some View {
        let n = site.notice
        // version numbers of the iPhone app are separate from Android; only the message is shared
        if n.enabled && n.style == "popup" && (!n.title.isEmpty || !n.text.isEmpty) && seenNotice != n.id {
            card(image: n.image, title: n.title, text: n.text, action: n.link.isEmpty ? nil : (n.linkLabel.isEmpty ? tr("التفاصيل") : n.linkLabel), link: n.link) { UserDefaults.standard.set(n.id, forKey: "noticeSeen"); seenNotice = n.id }
        }
    }
    private func card(image: String, title: String, text: String, action: String?, link: String, close: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture(perform: close)
            VStack(spacing: 12) {
                if !image.isEmpty { RemoteImage(raw: image).aspectRatio(16 / 9, contentMode: .fill).clipShape(RoundedRectangle(cornerRadius: 18)) } else { Image("Logo").resizable().scaledToFit().frame(width: 64) }
                if !title.isEmpty { Text(title).font(F.amiri(24)).foregroundStyle(c.goldGradient).multilineTextAlignment(.center) }
                if !text.isEmpty { Text(text).font(F.plex(15)).foregroundStyle(c.muted).multilineTextAlignment(.center) }
                HStack {
                    GhostButton(title: tr("حسنًا"), action: close)
                    if let action, let u = URL(string: link) { GoldButton(title: action) { UIApplication.shared.open(u); close() } }
                }.padding(.top, 6)
            }
            .padding(22).frame(maxWidth: 400).background(RoundedRectangle(cornerRadius: 26).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 26).stroke(c.line)).padding(26)
        }
    }
}
