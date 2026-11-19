import SwiftUI

/// Fit-Checks / Followers / Following stats (spec D13). Followers and Following open their lists.
struct ProfileStatsRow: View {
    let fitChecks: Int
    let followers: Int
    let following: Int
    let onFollowers: () -> Void
    let onFollowing: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 4) { stats }
        } else {
            HStack(spacing: 0) { stats }
        }
    }

    @ViewBuilder
    private var stats: some View {
        stat(fitChecks, "Fit-Checks", action: nil)
        stat(followers, "Followers", action: onFollowers)
        stat(following, "Following", action: onFollowing)
    }

    @ViewBuilder
    private func stat(_ value: Int, _ label: String, action: (() -> Void)?) -> some View {
        let count = Text("\(value)").font(Theme.headline).foregroundStyle(Theme.ink)
        let name = Text(label).font(Theme.caption).foregroundStyle(Theme.mutedForeground)
        let content = Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    name
                    Spacer(minLength: 0)
                    count.monospacedDigit()
                    if action != nil {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.mutedForeground)
                            .accessibilityHidden(true)
                    }
                }
            } else {
                VStack(spacing: 2) {
                    count
                    name
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// "+ Group", "+ Join", then one circle per group that opens its feed.
struct ProfileGroupsRow: View {
    let groups: [FashionGroup]
    let onCreate: () -> Void
    let onJoin: () -> Void

    private static let circleSize: CGFloat = 52
    /// Labels sit under fixed-size circles, so cap their growth.
    private static let maxLabelSize = DynamicTypeSize.xxxLarge

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                addButton("Group", accessibilityLabel: "Create group", id: "profile.addGroup", action: onCreate)
                addButton("Join", accessibilityLabel: "Join group", id: "profile.joinGroup", action: onJoin)
                ForEach(groups) { group in
                    NavigationLink { GroupDetailView(groupId: group.id) } label: { circle(group) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("profile.groupsRow")
    }

    private func addButton(_ title: String, accessibilityLabel: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.accentDeep)
                    .frame(width: Self.circleSize, height: Self.circleSize)
                    .overlay(Circle().strokeBorder(Theme.accentDeep, lineWidth: 1.5))
                Text(title)
                    .font(Theme.micro)
                    .dynamicTypeSize(...Self.maxLabelSize)
                    .foregroundStyle(Theme.ink)
            }
            .frame(minWidth: Theme.minTapSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(id)
    }

    private func circle(_ group: FashionGroup) -> some View {
        VStack(spacing: 4) {
            Text(String(group.name.prefix(1)).uppercased())
                .font(Theme.headline)
                .foregroundStyle(Theme.accentForeground)
                .frame(width: Self.circleSize, height: Self.circleSize)
                .background(Theme.accent, in: Circle())
            Text(group.name)
                .font(Theme.micro)
                .foregroundStyle(Theme.ink)
                .dynamicTypeSize(...Self.maxLabelSize)
                .lineLimit(1)
                .frame(maxWidth: Self.circleSize + 16)
        }
        .frame(minWidth: Theme.minTapSize)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Group \(group.name)")
    }
}
