import SwiftUI

/// Top of the feed: a large, heavy serif wordmark with an italic serif outfit prompt under it.
/// (Search is its own tab; notifications live on Profile.)
struct HomeHeader: View {
    let nickname: String?

    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize: CGFloat = 54

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CLO·V")
                .font(.system(size: wordmarkSize, weight: .black, design: .serif))
                .kerning(-1.5)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("CLO V")
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("feed.logo")
            TimelineView(.everyMinute) { context in
                Text(HomeGreeting.text(date: context.date, nickname: nickname))
                    .font(Theme.serifGreeting)
                    .foregroundStyle(Theme.ink.opacity(0.85))
                    // Prompts are a full question, so let a long nickname wrap instead of truncating.
                    .lineLimit(2)
                    .accessibilityIdentifier("home.greeting")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

#Preview("Home header") {
    HomeHeader(nickname: "maya")
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarbleBackground())
}
