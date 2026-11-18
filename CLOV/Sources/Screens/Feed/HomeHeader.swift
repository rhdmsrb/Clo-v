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

/// Top of Home: serif wordmark with floating search and notification buttons, an
/// italic serif greeting, and the editorial headline.
struct HomeHeader: View {
    let nickname: String?
    let unreadCount: Int
    let onSearch: () -> Void
    let onNotifications: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .center, spacing: Spacing.s) {
                Text("CLO·V")
                    .font(Theme.editorialFont(size: 34, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel("CLO V")
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("feed.logo")
                Spacer(minLength: Spacing.s)
                FloatingIconButton(systemImage: "magnifyingglass", accessibilityLabel: "Search",
                                   identifier: "home.search", action: onSearch)
                FloatingIconButton(systemImage: "bell", accessibilityLabel: "Notifications",
                                   badgeCount: unreadCount, identifier: "home.notifications",
                                   action: onNotifications)
            }
            TimelineView(.everyMinute) { context in
                Text(HomeGreeting.text(hour: Calendar.current.component(.hour, from: context.date), nickname: nickname))
                    .font(Theme.serifGreeting)
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
                    .accessibilityIdentifier("home.greeting")
            }
            EditorialTitle("Today’s", emphasis: "best", "fits")
                .padding(.top, Spacing.m)
                .accessibilityIdentifier("home.headline")
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

#Preview("Home header") {
    HomeHeader(nickname: "maya", unreadCount: 3, onSearch: {}, onNotifications: {})
        .padding(Spacing.m)
        .background(PaperBackground())
}
