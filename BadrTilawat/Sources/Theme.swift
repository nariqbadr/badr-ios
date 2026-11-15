import SwiftUI

/// The website's six palettes (assets/css/site.css) — the same as the Android app.
struct Palette: Equatable {
    let key: String, name: String
    let bg: Color, bg2: Color, surface: Color, surface2: Color, surface3: Color
    let text: Color, muted: Color, faint: Color, gold: Color, gold2: Color, onGold: Color
    let line: Color, lineSoft: Color, danger: Color, ok: Color
    let dark: Bool
    var stars: Bool { key == "stars" }
    /// the page gradient, top → bottom (its own for «فجر», «عنابي», «فضي» and «رخام الحرم»)
    var grad: [Color] {
        switch key {
        case "dawn": return [Color(hex: 0xFF140F2C), Color(hex: 0xFF2B1D48), Color(hex: 0xFF5B3157), Color(hex: 0xFFB8705E)]
        case "maroon": return [Color(hex: 0xFF3A1320), Color(hex: 0xFF1D0A10), Color(hex: 0xFF14060B)]
        case "silver": return [Color(hex: 0xFF1C2026), Color(hex: 0xFF16191D), Color(hex: 0xFF121417)]
        case "marble": return [Color(hex: 0xFFF7F5F1), Color(hex: 0xFFF4F2EE), Color(hex: 0xFFEDE9E2)]
        case "nightblue": return [Color(hex: 0xFF163352), Color(hex: 0xFF0E2032), Color(hex: 0xFF0B1A2A)]
        case "sky": return [Color(hex: 0xFFC4E1F7), Color(hex: 0xFFE2F0FB), Color(hex: 0xFFF1F8FD)]
        default: return [bg2, bg]
        }
    }
    var goldGradient: LinearGradient { LinearGradient(colors: [gold2, gold], startPoint: .topLeading, endPoint: .bottomTrailing) }
    var pattern: Color { gold.opacity(dark ? 0.085 : 0.10) }
}

extension Color {
    init(hex: UInt32) {
        let a = Double((hex >> 24) & 0xFF) / 255, r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

enum Themes {
    private static func p(_ k: String, _ n: String, _ c: [UInt32], _ dark: Bool) -> Palette {
        Palette(key: k, name: n, bg: Color(hex: c[0]), bg2: Color(hex: c[1]), surface: Color(hex: c[2]), surface2: Color(hex: c[3]), surface3: Color(hex: c[4]),
                text: Color(hex: c[5]), muted: Color(hex: c[6]), faint: Color(hex: c[7]), gold: Color(hex: c[8]), gold2: Color(hex: c[9]), onGold: Color(hex: c[10]),
                line: Color(hex: c[11]), lineSoft: Color(hex: c[12]), danger: Color(hex: c[13]), ok: Color(hex: c[14]), dark: dark)
    }
    static let all: [Palette] = [
        p("dark", tr("ليلي زمردي"), [0xFF0C1715, 0xFF0F1D1B, 0xFF13241F, 0xFF182D28, 0xFF1E3630, 0xFFECE4D2, 0xFFA3ADA6, 0xFF6F7D76, 0xFFC9A45C, 0xFFE3C88D, 0xFF14201D, 0x2EC9A45C, 0x14ECE4D2, 0xFFE07A5F, 0xFF7CC4A0], true),
        p("stars", tr("ليل ونجوم"), [0xFF070920, 0xFF0B0E2B, 0xFF12163A, 0xFF181D48, 0xFF222859, 0xFFEEECFF, 0xFFA9A6CF, 0xFF716E9A, 0xFFC4B3FF, 0xFFE3DBFF, 0xFF140F33, 0x38C4B3FF, 0x14EEECFF, 0xFFE07A5F, 0xFF7CC4A0], true),
        p("dawn", tr("فجر"), [0xFF1B1533, 0xFF221A3D, 0xFF2E2148, 0xFF3A2A58, 0xFF4D3566, 0xFFFBEFE6, 0xFFD1B8C4, 0xFF9C8199, 0xFFF2B48A, 0xFFFFD2B2, 0xFF2A1420, 0x40F2B48A, 0x17FBEFE6, 0xFFE07A5F, 0xFF7CC4A0], true),
        p("maroon", tr("عنابي"), [0xFF1D0A10, 0xFF260D15, 0xFF33121C, 0xFF3F1723, 0xFF4F1E2D, 0xFFF6EBE2, 0xFFC4A6A0, 0xFF8F716D, 0xFFD8B46A, 0xFFF0D59A, 0xFF1D0A10, 0x3DD8B46A, 0x14F6EBE2, 0xFFE07A5F, 0xFF7CC4A0], true),
        p("silver", tr("فضي"), [0xFF16191D, 0xFF1B1F24, 0xFF22272D, 0xFF2A3037, 0xFF343B43, 0xFFEEF1F4, 0xFFA3ACB6, 0xFF6D7680, 0xFFC9D2DC, 0xFFE9EEF3, 0xFF15181C, 0x33C9D2DC, 0x12EEF1F4, 0xFFE07A5F, 0xFF7CC4A0], true),
        p("nightblue", tr("ليل أزرق"), [0xFF0E2032, 0xFF132A40, 0xFF17314A, 0xFF1D3A56, 0xFF244563, 0xFFEAF4FB, 0xFF9FB7C9, 0xFF6C8599, 0xFF8FCAF2, 0xFFB7DDF7, 0xFF0E2032, 0x388FCAF2, 0x14EAF4FB, 0xFFE07A5F, 0xFF7CC4A0], true),
        p("navy", tr("كحلي"), [0xFF08141B, 0xFF0B1A22, 0xFF0F2230, 0xFF132A3A, 0xFF1A3446, 0xFFE6F0F2, 0xFF93AAB3, 0xFF64808B, 0xFF5EC2BB, 0xFF8FE0D8, 0xFF062027, 0x385EC2BB, 0x14E6F0F2, 0xFFE07A5F, 0xFF7CC4A0], true),
        p("black", tr("أسود فاخر"), [0xFF070707, 0xFF0D0D0D, 0xFF141414, 0xFF1B1B1B, 0xFF262626, 0xFFF1ECE2, 0xFFA8A29A, 0xFF6F6A63, 0xFFD4B26A, 0xFFECD39B, 0xFF141006, 0x38D4B26A, 0x14F1ECE2, 0xFFE07A5F, 0xFF7CC4A0], true),
        p("parchment", tr("رقّ ذهبي"), [0xFFEFE5D2, 0xFFE6DAC2, 0xFFF7F0E2, 0xFFECE2CD, 0xFFDFD2B6, 0xFF3A2C18, 0xFF6E5D43, 0xFF998A70, 0xFF8A6A2E, 0xFF6D5220, 0xFFFBF5E8, 0x4D8A6A2E, 0x1A3A2C18, 0xFFB4502F, 0xFF3D7D52], false),
        p("marble", tr("رخام الحرم"), [0xFFF4F2EE, 0xFFEBE8E2, 0xFFFBFAF7, 0xFFF1EEE8, 0xFFE2DDD3, 0xFF2A2620, 0xFF6B645A, 0xFF9A9388, 0xFFA8843C, 0xFF8A6A28, 0xFFFFFAF0, 0x47A8843C, 0x142A2620, 0xFFC0533A, 0xFF2F8A5D], false),
        p("sky", tr("سماء"), [0xFFE2F0FB, 0xFFD4E8F7, 0xFFF5FAFF, 0xFFE7F2FC, 0xFFD3E6F5, 0xFF15304A, 0xFF4E687E, 0xFF8199AC, 0xFF2F7DBB, 0xFF1F68A3, 0xFFFFFFFF, 0x38286496, 0x1715304A, 0xFFC0533A, 0xFF2F8A5D], false),
        p("light", tr("نهاري"), [0xFFF3EEE3, 0xFFEBE4D5, 0xFFFBF8F1, 0xFFF2ECDF, 0xFFE8E0CD, 0xFF1C2B27, 0xFF5B6863, 0xFF8A948F, 0xFF94712F, 0xFF7A5B22, 0xFFFFFAF0, 0x387A5B22, 0x171C2B27, 0xFFC0533A, 0xFF2F8A5D], false),
    ]
    static func get(_ k: String) -> Palette { all.first { $0.key == k } ?? all[0] }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue: Palette = Themes.all[0] }
extension EnvironmentValues {
    var pal: Palette { get { self[PaletteKey.self] } set { self[PaletteKey.self] = newValue } }
}

/// The site's fonts (bundled): IBM Plex Sans Arabic for text, Amiri for titles, Amiri Quran for ayahs.
enum F {
    static func plex(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        let n: String
        switch w {
        case .bold, .heavy, .black: n = "IBMPlexSansArabic-Bold"
        case .semibold: n = "IBMPlexSansArabic-SemiBold"
        case .medium: n = "IBMPlexSansArabic-Medium"
        default: n = "IBMPlexSansArabic-Regular"
        }
        return .custom(n, size: size)
    }
    static func amiri(_ size: CGFloat, bold: Bool = true) -> Font { .custom(bold ? "Amiri-Bold" : "Amiri-Regular", size: size) }
    static func quran(_ size: CGFloat) -> Font { .custom("AmiriQuran-Regular", size: size) }
}
