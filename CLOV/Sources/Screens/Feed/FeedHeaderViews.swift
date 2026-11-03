import SwiftUI

/// Plain header icon button (44x44 tap area) used in the Discover header.
struct FeedIconButton: View {
    let systemImage: String
    var tint: Color = Theme.ink
    let accessibilityLabel: String
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FeedIconBadge(systemImage: systemImage, tint: tint)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

struct FeedIconBadge: View {
    let systemImage: String
    var tint: Color = Theme.ink

    private static let tapSize: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: Self.tapSize, height: Self.tapSize)
            .contentShape(Rectangle())
    }
}

struct FeedBellIcon: View {
    let unreadCount: Int

    private static let maxBadgeCount = 9
    private static let badgeMinSize: CGFloat = 18

    var body: some View {
        ZStack(alignment: .topTrailing) {
            FeedIconBadge(systemImage: "bell")
            if unreadCount > 0 {
                Text(unreadCount > Self.maxBadgeCount ? "\(Self.maxBadgeCount)+" : "\(unreadCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accentForeground)
                    .lineLimit(1)
                    .padding(4)
                    .frame(minWidth: Self.badgeMinSize, minHeight: Self.badgeMinSize)
                    .background(Theme.accent)
                    .clipShape(Circle())
                    .offset(x: -4, y: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unreadCount > 0 ? "Notifications, \(unreadCount) unread" : "Notifications")
    }
}

struct FeedModeChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isSelected ? Theme.ink : Theme.mutedForeground)
                .padding(.horizontal, 4)
                .frame(minHeight: FeedLayout.minHitSize)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isSelected ? Theme.ink : .clear)
                        .frame(height: 2)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("feedMode_\(label.replacingOccurrences(of: " ", with: ""))")
    }
}

struct FeedOccasionChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    private static let underlineOpacity = 0.7

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isSelected ? Theme.accentSecondary : Theme.mutedForeground)
                .padding(.horizontal, 6)
                .frame(minHeight: FeedLayout.minHitSize)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isSelected ? Theme.accentSecondary.opacity(Self.underlineOpacity) : .clear)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct FeedSortMenu: View {
    @Binding var sort: FeedSortOption

    var body: some View {
        Menu {
            Button("Recommended", systemImage: "sparkles") { sort = .forYou }
            Button("Newest", systemImage: "clock") { sort = .newest }
            Button("Most voted", systemImage: "chart.bar.fill") { sort = .votes }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Theme.iconPlum)
                    .accessibilityHidden(true)
                Text(sort.title).lineLimit(1)
            }
            .fixedSize()
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.ink)
            .frame(minHeight: FeedLayout.minHitSize)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Sort: \(sort.title)")
    }
}

struct FeedSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedForeground)
                .accessibilityHidden(true)
            TextField("Search people, looks, occasions", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
