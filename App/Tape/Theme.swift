import SwiftUI
import TapeCore

/// The same dark terminal palette as the web build. Up/down colours follow the user's
/// convention (green-up in most markets, red-up in CN/HK/TW/JP/KR; Kimi review U3), and every
/// coloured change also carries a ▲/▼ glyph so colour is never the only signal.
enum Theme {
    static let bg = Color(red: 0x0b / 255, green: 0x0f / 255, blue: 0x14 / 255)
    static let surface = Color(red: 0x12 / 255, green: 0x18 / 255, blue: 0x21 / 255)
    static let line = Color(red: 0x1b / 255, green: 0x24 / 255, blue: 0x2e / 255)
    static let border = Color(red: 0x23 / 255, green: 0x2d / 255, blue: 0x38 / 255)
    static let text = Color(red: 0xe8 / 255, green: 0xee / 255, blue: 0xf4 / 255)
    static let muted = Color(red: 0x93 / 255, green: 0xa1 / 255, blue: 0xaf / 255)
    static let dim = Color(red: 0x8b / 255, green: 0x9a / 255, blue: 0xab / 255)
    static let green = Color(red: 0x22 / 255, green: 0xc5 / 255, blue: 0x5e / 255)
    static let red = Color(red: 0xef / 255, green: 0x44 / 255, blue: 0x44 / 255)
    static let warn = Color(red: 0xf5 / 255, green: 0x9e / 255, blue: 0x0b / 255)
    static let selected = Color(red: 0x1e / 255, green: 0x2a / 255, blue: 0x36 / 255)
    static let highlight = Color(red: 0x2a / 255, green: 0x3a / 255, blue: 0x4c / 255)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func up(_ convention: UpColorConvention) -> Color { convention == .greenUp ? green : red }
    static func down(_ convention: UpColorConvention) -> Color { convention == .greenUp ? red : green }

    static func changeColor(_ change: Double?, convention: UpColorConvention) -> Color {
        guard let c = change, c.isFinite, c != 0 else { return muted }
        return c > 0 ? up(convention) : down(convention)
    }

    static func badgeColor(_ type: InstrumentType) -> Color {
        switch type {
        case .crypto: return Color(red: 0xa5 / 255, green: 0xb4 / 255, blue: 0xfc / 255)
        case .commodity: return Color(red: 0xfb / 255, green: 0xbf / 255, blue: 0x24 / 255)
        case .etf: return Color(red: 0x6e / 255, green: 0xe7 / 255, blue: 0xb7 / 255)
        default: return muted
        }
    }
}

struct TypeBadge: View {
    let type: InstrumentType
    var body: some View {
        Text(type.rawValue.uppercased())
            .font(Theme.mono(10, weight: .medium))
            .tracking(0.8)
            .foregroundStyle(Theme.badgeColor(type))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.badgeColor(type).opacity(0.5), lineWidth: 1))
    }
}

/// A signed change with its direction glyph, coloured by convention. `text` is the formatted
/// number (for example "+1.23%" or "-0.45"); the glyph is prepended so VoiceOver reads a
/// direction even when the number is unsigned.
struct ChangeText: View {
    let change: Double?
    let text: String
    let convention: UpColorConvention
    var font: Font = Theme.mono(12)

    var body: some View {
        let glyph = Direction.glyph(change)
        Text(glyph.isEmpty ? text : glyph + " " + text)
            .font(font)
            .foregroundStyle(Theme.changeColor(change, convention: convention))
            .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        guard let c = change, c.isFinite, c != 0 else { return "unchanged" }
        return (c > 0 ? "up " : "down ") + text
    }
}
