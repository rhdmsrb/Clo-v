import SwiftUI

/// Top of the feed: a compact serif wordmark (accent dot between CLO and V)
/// with a small italic serif outfit prompt under it.
/// (Search is its own tab; notifications live on Profile.)
struct HomeHeader: View {
    let nickname: String?

    @ScaledMetric(relativeTo: .title) private var wordmarkSize: CGFloat = 30
    private static let wordmarkKerning: CGFloat = -0.6

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            wordmark
            TimelineView(.everyMinute) { context in
                Text(HomeGreeting.text(date: context.date, nickname: nickname))
                    .font(Theme.font(.subheadline).italic())
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.mutedForeground)
                    // Prompts are a full question, so let a long nickname wrap instead of truncating.
                    .lineLimit(2)
                    .accessibilityIdentifier("home.greeting")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var wordmark: some View {
        (Text("CLO") + Text("·").foregroundStyle(Theme.accent) + Text("V"))
            .font(.system(size: wordmarkSize, weight: .black, design: .serif))
            .kerning(Self.wordmarkKerning)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .accessibilityLabel("CLO V")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("feed.logo")
    }
}

#Preview("Home header") {
    HomeHeader(nickname: "maya")
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarbleBackground())
}
