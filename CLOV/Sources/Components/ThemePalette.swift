import SwiftUI
import UIKit

// User-selectable color palettes.
//
// A palette is encoded as a short string ("rose", "ocean", "custom:0.620") so it
// can be stored in AppStorage and carried through the UIKit trait system. That
// lets `Theme`'s dynamic colors re-resolve live when it changes, without
// rebuilding any view (and so without losing navigation state).
//
// Non-default palettes are generated from one hue so contrast stays safe
// whatever the user picks: text roles are always dark/light enough on their
// surfaces. "rose" keeps the hand-tuned original values.

/// Semantic color roles that vary by palette.
enum PaletteRole {
    case accent, accentDeep, accentTint
    case background, card, cardElevated, muted, mutedForeground, ink
    case primaryButtonFill, accentForeground
    case heroStart, heroMid, heroEnd
}

struct ThemePalette: Equatable, Identifiable {
    static let customPrefix = "custom:"

    let id: String
    let name: String
    /// 0...1 hue; nil for the hand-tuned default.
    let hue: Double?
    /// Scales every saturation; 0 gives a neutral grayscale palette.
    let saturation: Double

    static let rose = ThemePalette(id: "rose", name: "Rose", hue: nil, saturation: 1)
    static let presets: [ThemePalette] = [
        rose,
        ThemePalette(id: "ocean", name: "Ocean", hue: 0.57, saturation: 1),
        ThemePalette(id: "forest", name: "Forest", hue: 0.38, saturation: 1),
        ThemePalette(id: "lavender", name: "Lavender", hue: 0.74, saturation: 1),
        ThemePalette(id: "sunset", name: "Sunset", hue: 0.06, saturation: 1),
        ThemePalette(id: "mono", name: "Mono", hue: 0.0, saturation: 0)
    ]

    static func custom(hue: Double) -> ThemePalette {
        let clamped = min(max(hue, 0), 1)
        return ThemePalette(id: customPrefix + String(format: "%.3f", clamped), name: "Custom", hue: clamped, saturation: 1)
    }

    /// Unknown or malformed ids fall back to the default so a bad stored value never breaks the UI.
    static func resolve(_ id: String) -> ThemePalette {
        if let preset = presets.first(where: { $0.id == id }) { return preset }
        if id.hasPrefix(customPrefix), let hue = Double(id.dropFirst(customPrefix.count)) {
            return custom(hue: hue)
        }
        return rose
    }

    var isCustom: Bool { id.hasPrefix(Self.customPrefix) }

    /// Swatch used in the picker, always the palette's accent.
    var swatch: Color {
        // The default keeps its hand-tuned rose rather than the generated hue-0 red.
        hue == nil ? Color(red: 0xE4 / 255, green: 0x91 / 255, blue: 0xA6 / 255) : Color(uiColor: color(.accent, dark: false))
    }

    // MARK: Color generation

    /// nil means "use the hand-tuned default for this role".
    func color(_ role: PaletteRole, dark: Bool) -> UIColor {
        let hue = CGFloat(hue ?? 0)
        let k = CGFloat(saturation)
        func tone(_ s: CGFloat, _ b: CGFloat) -> UIColor {
            UIColor(hue: hue, saturation: min(s * k, 1), brightness: b, alpha: 1)
        }
        switch role {
        case .accent: return tone(0.48, 0.93)
        case .accentDeep: return dark ? tone(0.30, 0.96) : tone(0.50, 0.40)
        case .accentTint: return dark ? tone(0.45, 0.26) : tone(0.12, 0.99)
        case .background: return dark ? tone(0.30, 0.12) : tone(0.03, 0.985)
        case .card: return dark ? tone(0.30, 0.16) : UIColor.white
        case .cardElevated: return dark ? tone(0.30, 0.20) : UIColor.white
        case .muted: return dark ? tone(0.28, 0.22) : tone(0.06, 0.96)
        case .mutedForeground: return dark ? tone(0.12, 0.83) : tone(0.15, 0.40)
        case .ink: return dark ? tone(0.05, 0.97) : tone(0.45, 0.20)
        case .primaryButtonFill: return dark ? tone(0.48, 0.93) : tone(0.40, 0.42)
        case .accentForeground: return tone(0.60, 0.20)
        case .heroStart: return dark ? tone(0.60, 0.16) : tone(0.60, 0.26)
        case .heroMid: return dark ? tone(0.50, 0.28) : tone(0.40, 0.42)
        case .heroEnd: return dark ? tone(0.50, 0.38) : tone(0.55, 0.50)
        }
    }
}

// MARK: - Trait bridge

/// Carries the selected palette id through UIKit's trait collection.
struct PaletteTrait: UITraitDefinition {
    static let defaultValue = ThemePalette.rose.id
    static let affectsColorAppearance = true
    static let identifier = "app.clov.palette"
}

/// SwiftUI environment value mirrored into the trait collection, so dynamic
/// colors resolved by SwiftUI see the current palette.
private struct PaletteIDKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    static let defaultValue = ThemePalette.rose.id

    static func read(from traitCollection: UITraitCollection) -> String {
        traitCollection[PaletteTrait.self]
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: String) {
        mutableTraits[PaletteTrait.self] = value
    }
}

extension EnvironmentValues {
    var paletteID: String {
        get { self[PaletteIDKey.self] }
        set { self[PaletteIDKey.self] = newValue }
    }
}

/// Persisted appearance choices, shared by the app root and the settings screen.
enum AppearanceKey {
    static let paletteID = "appearance.paletteID"
    static let colorScheme = "appearance.colorScheme"
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
