import SwiftUI

/// Lets the user pick the app's color palette and light/dark preference.
/// Choices persist in AppStorage and apply live (see `ThemePalette`).
struct AppearanceView: View {
    @AppStorage(AppearanceKey.paletteID) private var paletteID = ThemePalette.rose.id
    @AppStorage(AppearanceKey.colorScheme) private var colorSchemeRaw = AppearanceMode.system.rawValue

    private let swatchColumns = [GridItem(.adaptive(minimum: 88), spacing: 12)]
    private var selected: ThemePalette { ThemePalette.resolve(paletteID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                previewCard
                SectionHeader(title: "Color palette")
                LazyVGrid(columns: swatchColumns, spacing: 12) {
                    ForEach(ThemePalette.presets) { palette in
                        swatchButton(palette)
                    }
                }
                customPicker
                SectionHeader(title: "Appearance")
                modePicker
                if paletteID != ThemePalette.rose.id {
                    Button("Reset to Rose") { select(.rose) }
                        .buttonStyle(OutlineButtonStyle())
                        .accessibilityIdentifier("resetPaletteButton")
                }
            }
            .padding(20)
            // Clear the floating tab bar so the last control scrolls fully above it.
            .padding(.bottom, 88)
        }
        .background(Theme.background)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Preview

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(Theme.caption)
                .foregroundStyle(Theme.mutedForeground)
            Text("Today’s look")
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Text("Selected")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.accentDeep)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Theme.accentTint, in: Capsule())
                Text("Chip")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Theme.muted, in: Capsule())
            }
            Text("Post a Fit-Check")
                .font(Theme.bodyEmphasis)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
                .background(Theme.heroGradient, in: Capsule())
        }
        .softCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(selected.name) palette")
    }

    // MARK: Palette choices

    private func swatchButton(_ palette: ThemePalette) -> some View {
        let isSelected = palette.id == paletteID
        return Button { select(palette) } label: {
            VStack(spacing: 8) {
                Circle()
                    .fill(palette.swatch)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.accentForeground)
                        }
                    }
                Text(palette.name)
                    .font(Theme.label)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .stroke(isSelected ? Theme.accentDeep : Theme.controlBorder, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        }
        .buttonStyle(InstantPressStyle())
        .accessibilityLabel(palette.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("palette_\(palette.id)")
    }

    private var customPicker: some View {
        ColorPicker(selection: customColor, supportsOpacity: false) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Custom color").font(Theme.headline).foregroundStyle(Theme.ink)
                Text("Build a palette from any color")
                    .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                .stroke(selected.isCustom ? Theme.accentDeep : Theme.controlBorder, lineWidth: selected.isCustom ? 2 : 1)
        }
        .accessibilityIdentifier("customColorPicker")
    }

    /// Only the hue is kept: the palette generator picks safe lightness and
    /// saturation, so any chosen color stays readable.
    private var customColor: Binding<Color> {
        Binding(
            get: { Color(hue: selected.hue ?? 0.95, saturation: 0.5, brightness: 0.93) },
            set: { newColor in
                var hue: CGFloat = 0
                guard UIColor(newColor).getHue(&hue, saturation: nil, brightness: nil, alpha: nil) else { return }
                select(.custom(hue: Double(hue)))
            }
        )
    }

    private var modePicker: some View {
        Picker("Appearance", selection: $colorSchemeRaw) {
            ForEach(AppearanceMode.allCases) { mode in
                Text(mode.title).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("appearanceModePicker")
    }

    private func select(_ palette: ThemePalette) {
        paletteID = palette.id
    }
}
