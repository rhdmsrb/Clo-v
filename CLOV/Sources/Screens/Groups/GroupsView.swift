import SwiftUI

struct GroupsView: View {
    @EnvironmentObject private var appState: AppState

    /// True when pushed inside another NavigationStack (e.g. from Profile).
    /// As a tab root (default) the view owns its NavigationStack.
    var embedded = false

    @State private var groups: [FashionGroup] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var addMode: GroupAddSheet.Mode?

    private static let titleSize: CGFloat = 32

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                AsyncStateView(isLoading: isLoading, error: error, topPadding: 20, hasLoaded: hasLoaded, retry: { await load() }) {
                    circlesSection
                }
            }
            .padding(20)
        }
        .clearsTabBar()
        .background(Theme.background)
        .accessibilityIdentifier("groups.root")
        .navigationDestination(for: UUID.self) { id in
            GroupDetailView(groupId: id, groupName: groups.first(where: { $0.id == id })?.name)
        }
        .sheet(item: $addMode) { mode in
            GroupAddSheet(initialMode: mode) { await load() }
        }
        .revisionTask(appState.contentRevision) { await load() }
        .refreshable { await load() }
    }

    /// One compact row: the title on the left, Join and Create on the right, so
    /// the first group is on screen without scrolling.
    private var header: some View {
        HStack(spacing: 8) {
            Text("Groups")
                .font(Theme.editorialFont(size: Self.titleSize, relativeTo: .title))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityAddTraits(.isHeader)
                .layoutPriority(1)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button { addMode = .join } label: { Label("Join", systemImage: "link") }
                    .buttonStyle(GroupHeaderButtonStyle(isPrimary: false))
                    .accessibilityLabel("Join a group")
                    .accessibilityIdentifier("groups.join")
                Button { addMode = .create } label: { Label("Create", systemImage: "plus") }
                    .buttonStyle(GroupHeaderButtonStyle(isPrimary: true))
                    .accessibilityLabel("Create a group")
                    .accessibilityIdentifier("groups.create")
            }
            .fixedSize()
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    @ViewBuilder private var circlesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if groups.isEmpty {
                EmptyStateView(
                    icon: "person.2",
                    title: "No groups yet",
                    message: "Create one or join with an invite code.",
                    actionTitle: "Create a group"
                ) { addMode = .create }
                .padding(.vertical, 12)
            } else {
                ForEach(groups) { group in
                    GroupCard(group: group, revision: appState.contentRevision)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            groups = try await API.fetchMyGroups(profileId: appState.userId)
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            Log.app.error("Groups load failed: \(String(describing: error))")
            self.error = "Couldn’t load this content. Please try again."
        }
    }
}

/// Compact Join / Create button for the Groups header.
private struct GroupHeaderButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label)
            .foregroundStyle(isPrimary ? Theme.primaryButtonText : Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: Theme.minTapSize)
            .background(isPrimary ? Theme.primaryButtonFill : Color.clear, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(isPrimary ? Color.clear : Theme.controlBorder, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule(style: .continuous))
    }
}

/// One group: a strip of its latest looks, the name, a member and live-look
/// summary, and member avatars. The invite code lives inside the group
/// (Members and Invite friends), not on every row. The preview loads per card
/// so the list appears immediately; a failed load leaves the plain card.
private struct GroupCard: View {
    let group: FashionGroup
    /// Changes when content changes elsewhere, so the preview reloads after a post.
    let revision: Int

    @State private var members: [GroupMemberDisplay]?
    @State private var liveCount: Int?
    @State private var thumbnails: [URL] = []

    private static let thumbnailCount = 3
    private static let thumbnailHeight: CGFloat = 120
    private static let thumbnailSpacing: CGFloat = 6
    private static let visibleAvatars = 4
    private static let avatarSize: CGFloat = 26
    private static let avatarOverlap: CGFloat = -8
    private static let avatarRingWidth: CGFloat = 2
    private static let cardPadding: CGFloat = 12

    private var summary: String {
        guard let members else { return "Private circle" }
        let people = "\(members.count) member\(members.count == 1 ? "" : "s")"
        guard let liveCount, liveCount > 0 else { return people }
        return "\(people) · \(liveCount) live"
    }

    var body: some View {
        NavigationLink(value: group.id) {
            VStack(alignment: .leading, spacing: 12) {
                thumbnailStrip
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                            .font(Theme.headline)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                        Text(summary)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                    Spacer(minLength: 8)
                    avatarStack
                }
            }
            .padding(Self.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.controlBorder.opacity(0.5), lineWidth: 1))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .task(id: revision) { await loadPreview() }
    }

    private var thumbnailStrip: some View {
        HStack(spacing: Self.thumbnailSpacing) {
            ForEach(0..<Self.thumbnailCount, id: \.self) { index in
                thumbnail(at: index)
            }
        }
        .frame(height: Self.thumbnailHeight)
        .overlay {
            if liveCount == 0 {
                Text("No live looks yet")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private func thumbnail(at index: Int) -> some View {
        Color.clear
            .overlay {
                if thumbnails.indices.contains(index) {
                    CachedImage(url: thumbnails[index]) { phase in
                        switch phase {
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        default: Theme.muted
                        }
                    }
                } else {
                    Theme.muted
                }
            }
            .clipped()
    }

    private var avatarStack: some View {
        HStack(spacing: Self.avatarOverlap) {
            ForEach((members ?? []).prefix(Self.visibleAvatars)) { member in
                AvatarView(url: member.avatarUrl, nickname: member.nickname, size: Self.avatarSize)
                    .overlay(Circle().stroke(Theme.card, lineWidth: Self.avatarRingWidth))
            }
        }
        .accessibilityHidden(true)
    }

    private func loadPreview() async {
        async let membersTask = Log.attempt("Load group members") { try await API.fetchGroupMembers(groupId: group.id) }
        async let feedTask = Log.attempt("Load group preview") { try await API.fetchGroupFeed(groupId: group.id) }
        let (loadedMembers, loadedFeed) = await (membersTask, feedTask)
        guard !Task.isCancelled else { return }
        if let loadedMembers { members = loadedMembers }
        if let loadedFeed {
            liveCount = loadedFeed.count
            thumbnails = loadedFeed.prefix(Self.thumbnailCount)
                .compactMap { PostCardContent.photoURLs($0.fitCheckPhotos).first }
        }
    }
}

/// Invite code shown as a capsule; tapping copies it to the pasteboard.
struct InviteCodeCapsule: View {
    let code: String
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let resetDelay: Duration = .seconds(2)

    var body: some View {
        Button {
            UIPasteboard.general.string = code
            withAnimation(Theme.animation(Theme.snap, reduceMotion: reduceMotion)) { copied = true }
            AccessibilityNotification.Announcement("Invite code copied").post()
            Task {
                try? await Task.sleep(for: Self.resetDelay)
                withAnimation(Theme.animation(Theme.snap, reduceMotion: reduceMotion)) { copied = false }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .accessibilityHidden(true)
                Text(copied ? "Copied" : code)
                    .monospaced()
            }
            .font(Theme.label)
            .foregroundStyle(Theme.accentDeep)
            .padding(.horizontal, 14)
            .frame(minHeight: Theme.minTapSize)
            .background(Theme.accentTint, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Theme.accentDeep.opacity(0.4), lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Invite code \(code)")
        .accessibilityHint("Copies the code")
    }
}
