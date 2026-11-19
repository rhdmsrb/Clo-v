import SwiftUI

/// Share / Analytics row under the profile header. Editing the profile lives in
/// Settings → Preferences, so it is not offered here.
struct ProfileActionTabs<ShareContent: View>: View {
    let onAnalytics: () -> Void
    let analyticsExpanded: Bool
    @ViewBuilder let share: () -> ShareContent

    private typealias Metrics = ProfileActionTabMetrics

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            pill { share() }
            pill {
                Button(action: onAnalytics) { Text("Analytics") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Analytics")
                    .accessibilityValue(analyticsExpanded ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier("profile.analytics")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Both actions share one pill so the row reads as two equal buttons.
    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(Theme.bodyEmphasis)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
            .frame(height: Metrics.height)
            .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                .stroke(Theme.controlBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
    }
}

private enum ProfileActionTabMetrics {
    static let height: CGFloat = 46
    static let spacing: CGFloat = 12
}
