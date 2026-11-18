import SwiftUI

/// Section title with an optional trailing text action ("See all").
/// Pass `emphasis` to set one word in serif italic: "Trending *now*".
struct SectionHeader: View {
    let title: String
    var emphasis: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            heading
            Spacer(minLength: Spacing.s)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Theme.label)
                        .foregroundStyle(Theme.accentDeep)
                        .frame(minHeight: Theme.minTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var heading: some View {
        if let emphasis {
            EditorialTitle(title, emphasis: emphasis, font: Theme.title)
        } else {
            Text(title)
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.m) {
        SectionHeader(title: "Trending", actionTitle: "See all") {}
        SectionHeader(title: "Trending", emphasis: "now", actionTitle: "See all") {}
    }
    .padding(Spacing.m)
    .background(Theme.background)
}
