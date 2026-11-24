import SwiftUI

/// «اللغة»: every language in its own name; choosing one draws the whole app again in it.
struct LangSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var lang: Lang
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let c = Themes.get(store.theme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHead(title: tr("اللغة"))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Lang.all, id: \.0) { code, name in
                        let on = lang.code == code
                        Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { lang.set(code); Task { await Prayers.shared.renamePlace() } } } label: {
                            HStack {
                                Text(name).font(F.plex(15, on ? .bold : .medium)).foregroundStyle(on ? c.gold2 : c.text)
                                    .environment(\.layoutDirection, ["ar", "ur", "fa"].contains(code) ? .rightToLeft : .leftToRight)
                                Spacer(minLength: 4)
                                if on { SiteIcon(name: "check", size: 18, color: c.gold) }
                            }
                            .padding(.horizontal, 14).frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 14).fill(on ? c.gold.opacity(0.14) : c.surface))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? c.gold : c.line, lineWidth: on ? 1.5 : 1))
                        }.buttonStyle(Press())
                    }
                }.padding(.horizontal, 16)
                Text(tr("القرآن الكريم والأذكار تبقى بالعربية، ويظهر معنى الآيات بلغتك تحت كل آية."))
                    .font(F.plex(12.5)).foregroundStyle(c.muted).padding(16)
            }
        }
    }
}
