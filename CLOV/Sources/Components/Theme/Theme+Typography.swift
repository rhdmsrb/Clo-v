import SwiftUI

// SF Pro for UI text and New York (the system serif) for editorial headlines.
// Every font is relative to a Dynamic Type text style, so it scales.
extension Theme {
    static let micro = font(.caption2, weight: .semibold)
    static let microMedium = font(.caption2, weight: .medium)
    static let caption = font(.caption, weight: .medium)
    static let label = font(.footnote, weight: .semibold)
    static let bodyEmphasis = font(.subheadline, weight: .semibold)
    static let body = font(.body)
    static let headline = font(.headline, weight: .semibold)
    /// Section titles (sans).
    static let title = font(.title2, weight: .semibold)

    /// Large serif headline (New York, 34pt largeTitle). Pair with `EditorialTitle`
    /// to set one word in italic.
    static let display = Font.system(.largeTitle, design: .serif)
    /// Serif italic label that sits on photos ("Date night", "Campus").
    static let serifLabel = Font.system(.subheadline, design: .serif).italic()
    /// Serif italic line under the wordmark ("Good evening, Maya").
    static let serifGreeting = Font.system(.title3, design: .serif).italic()

    /// Serif display face for headings that used the old display font.
    static var displayFont: Font { editorialFont(size: 30, relativeTo: .title2) }

    /// New York at the Dynamic Type style closest to `size`. The `relativeTo`
    /// argument is kept for source compatibility; the size picks the style so
    /// the font keeps scaling with the user's text size.
    static func editorialFont(size: CGFloat, relativeTo _: Font.TextStyle = .largeTitle,
                              weight: Font.Weight = .semibold) -> Font {
        .system(textStyle(nearest: size), design: .serif, weight: weight)
    }

    /// SF Pro at the default size of a text style, scaling with Dynamic Type.
    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, weight: weight)
    }

    /// Default iOS point sizes, largest first, used to map a size to a text style.
    private static let styleSizes: [(Font.TextStyle, CGFloat)] = [
        (.largeTitle, 34), (.title, 28), (.title2, 22), (.title3, 20),
        (.headline, 17), (.subheadline, 15), (.footnote, 13), (.caption, 12), (.caption2, 11)
    ]

    static func textStyle(nearest size: CGFloat) -> Font.TextStyle {
        styleSizes.min { abs($0.1 - size) < abs($1.1 - size) }?.0 ?? .body
    }
}

/// A headline with exactly one emphasised word in serif italic, e.g.
/// `EditorialTitle("Today's", emphasis: "best", "fits")`.
/// The rest of the line uses `font`; the emphasised word keeps its size.
struct EditorialTitle: View {
    let leading: String
    let emphasis: String
    let trailing: String
    var font: Font = Theme.display
    var color: Color = Theme.ink

    init(_ leading: String, emphasis: String, _ trailing: String = "",
         font: Font = Theme.display, color: Color = Theme.ink) {
        self.leading = leading
        self.emphasis = emphasis
        self.trailing = trailing
        self.font = font
        self.color = color
    }

    var body: some View {
        styledText
            .foregroundStyle(color)
            .accessibilityLabel(plainText)
            .accessibilityAddTraits(.isHeader)
    }

    private var styledText: Text {
        let lead = leading.isEmpty ? Text("") : Text(leading + " ").font(font)
        let word = Text(emphasis).font(font).italic().fontDesign(.serif)
        let tail = trailing.isEmpty ? Text("") : Text(" " + trailing).font(font)
        return lead + word + tail
    }

    private var plainText: String {
        [leading, emphasis, trailing].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

#Preview("Editorial titles") {
    VStack(alignment: .leading, spacing: Spacing.m) {
        EditorialTitle("Today's", emphasis: "best", "fits")
        EditorialTitle("Your", emphasis: "weekly", "recap", font: Theme.font(.title2, weight: .bold))
        Text("Good evening, Maya").font(Theme.serifGreeting).foregroundStyle(Theme.mutedForeground)
        Text("Body copy in SF Pro").font(Theme.body)
    }
    .padding(Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.background)
}
