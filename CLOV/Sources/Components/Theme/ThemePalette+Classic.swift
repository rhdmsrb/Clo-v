import Foundation

extension ThemePalette {
    /// The original hand-tuned burgundy look, as (light, dark) hex per role.
    /// Unchanged from the pre-redesign Theme so "Classic" matches it exactly.
    static let classicHex: [PaletteRole: (light: UInt32, dark: UInt32)] = [
        .accent: (0x782840, 0xE7A8B2),
        .accentDeep: (0x782840, 0xE7ABB6),
        .accentTint: (0xF3E4E4, 0x4A2933),
        .accentForeground: (0xFFFFFF, 0x30131C),
        .background: (0xFCF8F4, 0x1D1216),
        .card: (0xFFFCFA, 0x2A1A21),
        .cardElevated: (0xFFFCFA, 0x35222B),
        .muted: (0xF2EAE6, 0x3A2830),
        .mutedForeground: (0x6E5559, 0xD4BDC0),
        .ink: (0x3A2029, 0xF8EEF1),
        .primaryButtonFill: (0x782840, 0xE7A8B2),
        .primaryButtonText: (0xFFFFFF, 0x3A1A26),
        .heroStart: (0x421722, 0x29131A),
        .heroMid: (0x6A2338, 0x4D1C2B),
        .heroEnd: (0xA34C60, 0x782E43)
    ]
}
