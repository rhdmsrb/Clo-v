import Testing
import SwiftUI
@testable import CLOV

/// The redesign swaps the default palette. Saved ids from before must keep
/// resolving to something sensible, and the old look must stay available.
struct ThemePaletteTests {
    @Test("The old default id 'rose' resolves to the new Clay default")
    func legacyDefaultResolvesToClay() {
        #expect(ThemePalette.resolve("rose") == .clay)
    }

    @Test("Unknown ids fall back to Clay")
    func unknownIdFallsBackToClay() {
        #expect(ThemePalette.resolve("not-a-palette") == .clay)
    }

    @Test("Clay and Classic are both offered, Clay first")
    func presetsOfferClayThenClassic() {
        #expect(ThemePalette.presets.prefix(2).map(\.id) == ["clay", "classic"])
    }

    @Test("Classic defines every role, so no color falls back to a generated hue")
    func classicCoversEveryRole() {
        let roles: [PaletteRole] = [
            .accent, .accentDeep, .accentTint, .background, .card, .cardElevated, .muted,
            .mutedForeground, .ink, .primaryButtonFill, .primaryButtonText, .accentForeground,
            .heroStart, .heroMid, .heroEnd
        ]
        #expect(roles.allSatisfy { ThemePalette.classicHex[$0] != nil })
    }

    @Test("Classic keeps the original burgundy accent")
    func classicKeepsBurgundy() {
        #expect(ThemePalette.classicHex[.accent]?.light == 0x782840)
    }

    @Test("Custom palettes still round-trip")
    func customStillResolves() {
        #expect(ThemePalette.resolve("custom:0.500").hue == 0.5)
    }

    static let styleCases: [(Double, Font.TextStyle)] = [
        (34, .largeTitle), (30, .title), (22, .title2), (17, .headline), (11, .caption2)
    ]

    @Test("Text sizes map to the nearest Dynamic Type style", arguments: styleCases)
    func nearestTextStyle(size: Double, expected: Font.TextStyle) {
        #expect(Theme.textStyle(nearest: CGFloat(size)) == expected)
    }
}
