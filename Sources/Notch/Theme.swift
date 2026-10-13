import SwiftUI

enum ThemeKind: String, CaseIterable, Identifiable {
    case darkMatte
    case whiteMatte

    var id: String { rawValue }

    var title: String {
        switch self {
        case .darkMatte: return "Dark Matte"
        case .whiteMatte: return "White Matte"
        }
    }
}

/// Flat / matte palettes. No glass, no gradients — solid fills only.
struct Theme {
    let kind: ThemeKind
    let isDark: Bool
    /// Island background (below the notch band).
    let background: Color
    /// Tile fill.
    let tile: Color
    /// Primary text.
    let text: Color
    /// Secondary text, icons at rest, progress track.
    let secondaryText: Color
    /// Accent (light blue): every "active" or "new" state.
    let accent: Color

    static let darkMatte = Theme(
        kind: .darkMatte,
        isDark: true,
        background: Color(hex: 0x16181F),
        tile: Color(hex: 0x21242D),
        text: Color(hex: 0xE3E7EF),
        secondaryText: Color(hex: 0xA4ABBA),
        accent: Color(hex: 0x8FC7FF)
    )

    static let whiteMatte = Theme(
        kind: .whiteMatte,
        isDark: false,
        background: Color(hex: 0xF7F8FA),
        tile: Color(hex: 0xE9EBEF),
        text: Color(hex: 0x1E2129),
        secondaryText: Color(hex: 0x545A69),
        accent: Color(hex: 0x3B82D0)
    )

    static func of(_ kind: ThemeKind) -> Theme {
        switch kind {
        case .darkMatte: return .darkMatte
        case .whiteMatte: return .whiteMatte
        }
    }

    // MARK: - Derived

    /// Progress bar track (measured from the mockups: ~12% darker than the tile).
    var track: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.10) }
    /// Progress bar fill (measured: ~33% darker than the tile).
    var trackFill: Color { isDark ? Color.white.opacity(0.42) : Color.black.opacity(0.32) }

    /// Warnings only — muted, never used for "active".
    var warningYellow: Color { isDark ? Color(hex: 0xD9C179) : Color(hex: 0x9A7B22) }
    var warningOrange: Color { isDark ? Color(hex: 0xD9A06B) : Color(hex: 0xA2601F) }
    var warningRed: Color { isDark ? Color(hex: 0xE08B8B) : Color(hex: 0xB04A4A) }

    /// The physical notch band stays black in both themes.
    var notchBandColor: Color { .black }

    /// Hairline around tiles so they read as separate cards on a matte panel.
    var tileStroke: Color { isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05) }

    /// Fill for small controls sitting inside a tile.
    var control: Color { isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.05) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
