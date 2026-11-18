import SwiftUI

/// Pure wording for the countdown badge, unit tested.
enum CountdownText {
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3_600
    private static let day: TimeInterval = 86_400

    /// "ends in 2d", "ends in 5h", "ends in 12m", "ends in <1m", or "Ended".
    static func label(remaining: TimeInterval) -> String {
        guard remaining > 0 else { return "Ended" }
        if remaining >= day { return "ends in \(Int(remaining / day))d" }
        if remaining >= hour { return "ends in \(Int(remaining / hour))h" }
        if remaining >= minute { return "ends in \(Int(remaining / minute))m" }
        return "ends in <1m"
    }

    /// Short form for a boxed badge: "2d", "5h", "12m", "<1m", or "Ended".
    static func compact(remaining: TimeInterval) -> String {
        let full = label(remaining: remaining)
        return full.hasPrefix("ends in ") ? String(full.dropFirst("ends in ".count)) : full
    }

    /// Spoken form: "Voting ends in 5 hours".
    static func accessibilityLabel(remaining: TimeInterval) -> String {
        guard remaining > 0 else { return "Voting ended" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.day, .hour, .minute]
        let amount = formatter.string(from: max(remaining, minute)) ?? ""
        return "Voting ends in \(amount)"
    }
}

/// Small pill with an hourglass and the time left ("ends in 5h"). Re-renders once a
/// minute; hidden for posts with no expiry.
struct CountdownBadge: View {
    let expiresAt: Date?
    /// `.onPhoto`: white pill over a photo. `.onSurface`: gray pill on a card.
    /// `.boxed`: a square-cornered white tag with the short form ("5h"), editorial style.
    var style: Style = .onPhoto

    enum Style { case onPhoto, onSurface, boxed }

    private static let refresh: TimeInterval = 60

    var body: some View {
        if let expiresAt {
            TimelineView(.periodic(from: .now, by: Self.refresh)) { context in
                let remaining = expiresAt.timeIntervalSince(context.date)
                Label(style == .boxed ? CountdownText.compact(remaining: remaining) : CountdownText.label(remaining: remaining),
                      systemImage: remaining > 0 ? "hourglass" : "checkmark.seal")
                    .font(Theme.font(style == .boxed ? .subheadline : .caption, weight: style == .boxed ? .bold : .semibold))
                    .monospacedDigit()
                    .labelStyle(CompactLabelStyle())
                    // On a photo the tag is always white, so its text stays dark in dark mode too.
                    .foregroundStyle(style == .onSurface ? Theme.ink : Color.black)
                    .padding(.horizontal, Spacing.s + 2)
                    .padding(.vertical, Spacing.xs + 1)
                    .background(background, in: RoundedRectangle(cornerRadius: style == .boxed ? 2 : 100, style: .continuous))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(CountdownText.accessibilityLabel(remaining: remaining))
                    .accessibilityIdentifier("countdown-badge")
            }
        }
    }

    private var background: Color {
        switch style {
        case .onPhoto: Color.white.opacity(0.92)
        case .onSurface: Theme.muted
        case .boxed: Color.white
        }
    }
}

/// Icon and title with a tight gap, for badges and tags.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xs) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

#Preview("Countdown badges") {
    VStack(spacing: Spacing.m) {
        CountdownBadge(expiresAt: .now.addingTimeInterval(5 * 3_600 + 60))
        CountdownBadge(expiresAt: .now.addingTimeInterval(12 * 60 + 5), style: .onSurface)
        CountdownBadge(expiresAt: .now.addingTimeInterval(-10))
        CountdownBadge(expiresAt: .now.addingTimeInterval(5 * 3_600 + 60), style: .boxed)
    }
    .padding(Spacing.l)
    .background(Color.gray)
}
