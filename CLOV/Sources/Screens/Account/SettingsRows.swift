import SwiftUI
import UserNotifications

/// Label for one settings row: tinted icon, title, optional detail, optional chevron.
/// Wrap it in a `NavigationLink` or `Button`; the whole row is the tap target.
struct SettingsRowLabel: View {
    let icon: String
    let title: String
    var detail: String?
    var tint: Color = Theme.iconCoral
    var titleColor: Color = Theme.ink
    var showsChevron = true
    /// Shown instead of the chevron for rows that leave the app (links, iOS Settings).
    var isExternal = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(Theme.headline)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.leading)
                if let detail {
                    Text(detail)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: isExternal ? "arrow.up.right" : "chevron.right")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: Theme.minTapSize)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Titled group of rows on one card. Put `SettingsDivider()` between rows.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.micro)
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.mutedForeground)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0, content: content)
                .softCard(radius: Theme.tileRadius, padding: 12)
        }
    }
}

/// Hairline between rows, inset to line up with the row text.
struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 48)
    }
}

/// Where the app stands on push notifications, mapped from the system status.
enum PushPermission: Equatable {
    case unknown, notDetermined, denied, allowed

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized, .provisional, .ephemeral: self = .allowed
        @unknown default: self = .unknown
        }
    }

    var summary: String {
        switch self {
        case .unknown: "Checking…"
        case .notDetermined: "Get told when people vote or comment"
        case .denied: "Off. Turn on in iOS Settings"
        case .allowed: "On"
        }
    }
}
