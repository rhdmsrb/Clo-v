import SwiftUI

/// Round tinted icon button used in the Discover header.
struct FeedIconButton: View {
    let systemImage: String
    let tint: Color
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
    let tint: Color

    private static let diameter: CGFloat = 42
    private static let backgroundOpacity = 0.12

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: Self.diameter, height: Self.diameter)
            .background(tint.opacity(Self.backgroundOpacity), in: Circle())
    }
}

struct FeedBellIcon: View {
    let unreadCount: Int

    private static let maxBadgeCount = 9

    private var tint: Color { unreadCount > 0 ? Theme.iconCoral : Theme.iconApricot }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            FeedIconBadge(systemImage: "bell", tint: tint)
            if unreadCount > 0 {
                Text(unreadCount > Self.maxBadgeCount ? "\(Self.maxBadgeCount)+" : "\(unreadCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Theme.iconCoral)
                    .clipShape(Circle())
                    .offset(x: 4, y: -4)
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
                .foregroundStyle(isSelected ? Theme.ink : Theme.mutedForeground)
                .padding(.horizontal, 4)
                .frame(minHeight: FeedLayout.minHitSize)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isSelected ? Theme.accent : .clear)
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
                .foregroundStyle(isSelected ? Theme.accent : Theme.mutedForeground)
                .padding(.horizontal, 6)
                .frame(minHeight: FeedLayout.minHitSize)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isSelected ? Theme.accent.opacity(Self.underlineOpacity) : .clear)
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
                Text(sort.title)
            }
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
