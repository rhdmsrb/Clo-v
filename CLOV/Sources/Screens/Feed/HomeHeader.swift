import SwiftUI

/// Pure greeting wording for the Home header, unit tested.
enum HomeGreeting {
    /// "Good morning, maya" / "Good afternoon" / "Good evening" / "Up late" by hour (0...23).
    static func text(hour: Int, nickname: String?) -> String {
        let salutation: String
        switch hour {
        case 5..<12: salutation = "Good morning"
        case 12..<17: salutation = "Good afternoon"
        case 17..<23: salutation = "Good evening"
        default: salutation = "Up late"
        }
        let name = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? salutation : "\(salutation), \(name)"
    }
}

/// Top of the feed: a large, heavy serif wordmark with an italic serif greeting under it.
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
                Text(HomeGreeting.text(hour: Calendar.current.component(.hour, from: context.date), nickname: nickname))
                    .font(Theme.serifGreeting)
                    .foregroundStyle(Theme.ink.opacity(0.85))
                    .lineLimit(1)
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
