import SwiftUI

/// Friendly empty / error state: gradient-tint circle with an animated SF Symbol,
/// display title, muted body and an optional capsule call to action.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var isActionDisabled = false
    var tint: Color = Theme.accentDeep
    var action: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounceTrigger = 0

    private static let circleSize: CGFloat = 96
    private static let maxButtonWidth: CGFloat = 280

    var body: some View {
        VStack(spacing: 14) {
            iconCircle
            Text(title)
                .font(Theme.editorialFont(size: 28, relativeTo: .title2))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityAddTraits(.isHeader)
            if let message, !message.isEmpty {
                Text(message)
                    .font(Theme.body)
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle(isDisabled: isActionDisabled))
                    .frame(maxWidth: Self.maxButtonWidth)
                    .disabled(isActionDisabled)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .task {
            guard !reduceMotion else { return }
            bounceTrigger += 1
        }
    }

    private var iconCircle: some View {
        ZStack {
            Circle().fill(LinearGradient(
                colors: [Theme.accentTint, Theme.muted],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            Image(systemName: icon)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, options: .nonRepeating, value: bounceTrigger)
        }
        .frame(width: Self.circleSize, height: Self.circleSize)
        .accessibilityHidden(true)
    }
}

#Preview {
    EmptyStateView(icon: "tshirt", title: "No fits yet", message: "Post your first look.", actionTitle: "Post a fit") {}
        .padding()
        .background(Theme.background)
}
