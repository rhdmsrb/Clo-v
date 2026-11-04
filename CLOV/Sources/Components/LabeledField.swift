import SwiftUI

/// Border widths live outside the generic `LabeledField` (generic types can't hold static stored properties).
private enum LabeledFieldBorder {
    static let restingWidth: CGFloat = 1
    static let focusedWidth: CGFloat = 2
}

/// A visible label above a rounded form control. Surface is `muted` (or
/// `background` when `insetStyle`) with a 1pt `controlBorder`; when
/// `isFocused` the border becomes a 2pt `accentDeep` ring. `errorMessage`
/// renders below in `danger` with an icon so it is not color-only.
///
/// `insetStyle` is for a field that already sits inside a `.softCard()`.
struct LabeledField<Content: View>: View {
    var label: String? = nil
    var radius: CGFloat = Theme.fieldRadius
    var padding: CGFloat = 16
    var insetStyle: Bool = false
    var isFocused: Bool = false
    var errorMessage: String? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let hasError = errorMessage != nil
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                Text(label)
                    .font(Theme.label)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
                .font(Theme.body)
                .padding(padding)
                .frame(minHeight: Theme.minTapSize)
                .background(insetStyle ? Theme.background : Theme.muted, in: shape)
                .overlay(shape.stroke(borderColor(hasError: hasError),
                                      lineWidth: isFocused || hasError ? LabeledFieldBorder.focusedWidth : LabeledFieldBorder.restingWidth))
                .animation(Theme.animation(Theme.snap, reduceMotion: reduceMotion), value: isFocused)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func borderColor(hasError: Bool) -> Color {
        if hasError { return Theme.danger }
        return isFocused ? Theme.accentDeep : Theme.controlBorder
    }
}
