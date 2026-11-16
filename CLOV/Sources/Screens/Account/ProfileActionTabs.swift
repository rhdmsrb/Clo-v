import SwiftUI

/// Edit / Share / Analytics row from the hand sketch: Share is a folder-style
/// tab that rises above its neighbours, and the content line curves up into it.
struct ProfileActionTabs<ShareContent: View>: View {
    let onEdit: () -> Void
    let onAnalytics: () -> Void
    @ViewBuilder let share: () -> ShareContent

    private typealias Metrics = ProfileActionTabMetrics

    var body: some View {
        ZStack(alignment: .bottom) {
            ProfileTabOutline(rise: Metrics.rise)
                .fill(Theme.accentTint)
            ProfileTabOutline(rise: Metrics.rise)
                .stroke(Theme.controlBorder, lineWidth: 1.5)
            HStack(alignment: .bottom, spacing: 0) {
                sideButton("Edit", label: "Edit profile", id: "profile.edit", action: onEdit)
                share()
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.accentDeep)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
                    .frame(height: Metrics.totalHeight - 4)
                    .contentShape(Rectangle())
                sideButton("Analytics", label: "Analytics", id: "profile.analytics", action: onAnalytics)
            }
        }
        .frame(height: Metrics.totalHeight)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func sideButton(_ title: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
                .frame(height: Metrics.sideHeight)
                .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
                .padding(.horizontal, Metrics.sideInset)
                .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Baseline across the full width that bumps up over the middle third.
private struct ProfileTabOutline: Shape {
    let rise: CGFloat

    func path(in rect: CGRect) -> Path {
        let base = rect.maxY - 2
        let left = rect.width / 3
        let right = rect.width * 2 / 3
        let flare: CGFloat = 18
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: base))
        path.addLine(to: CGPoint(x: left - flare, y: base))
        path.addCurve(
            to: CGPoint(x: left + 8, y: rect.minY + 1),
            control1: CGPoint(x: left - 2, y: base),
            control2: CGPoint(x: left - 2, y: rect.minY + 1)
        )
        path.addLine(to: CGPoint(x: right - 8, y: rect.minY + 1))
        path.addCurve(
            to: CGPoint(x: right + flare, y: base),
            control1: CGPoint(x: right + 2, y: rect.minY + 1),
            control2: CGPoint(x: right + 2, y: base)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: base))
        return path
    }
}

private enum ProfileActionTabMetrics {
    static let rise: CGFloat = 8
    static let sideHeight: CGFloat = 46
    static let totalHeight: CGFloat = 62
    static let sideInset: CGFloat = 16
}
