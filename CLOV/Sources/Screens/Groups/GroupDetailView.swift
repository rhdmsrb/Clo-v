import SwiftUI

/// Group Feed (spec 5.6): header with the group name, a member avatar row that
/// hides on scroll down and returns on scroll up, and large first-photo cards.
struct GroupDetailView: View {
    let groupId: UUID
    /// Name known from the route (e.g. the Groups list), shown while loading or if loading fails.
    var groupName: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState

    @State private var group: FashionGroup?
    @State private var members: [GroupMemberDisplay] = []
    @State private var isMember = false
    @State private var items: [FeedItemDTO] = []
    @State private var followingIDs: Set<UUID> = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var showCreate = false
    @State private var showRename = false
    @State private var showLeave = false
    @State private var showDelete = false
    @State private var showMembers = false
    @State private var memberToRemove: GroupMemberDisplay?
    @State private var newName = ""
    @State private var avatarRowVisible = true
    @State private var lastScrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 36

    private static let scrollSpace = "groupFeedScroll"
    private static let visibleMemberLimit = 4

    private var isOwner: Bool { group?.creatorId == appState.userId }

    var body: some View {
        dialogHost
            .background(Theme.background)
            .accessibilityIdentifier("groupFeed.root")
            .navigationBarBackButtonHidden(false)
            .navigationDestination(for: FitCheckRoute.self) { route in routeDestination(route) }
            .fullScreenCover(isPresented: $showCreate) {
                CreateFitCheckView(preselectedGroup: group)
            }
            .sheet(isPresented: $showMembers) {
                if let group { membersSheet(group) }
            }
            .revisionTask(appState.contentRevision) { await load() }
            .refreshable { await load() }
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            header
            if isMember, group != nil { memberRow }
            feedScroll
        }
    }

    @ViewBuilder private var header: some View {
        if isMember, let group {
            topBar(name: group.name, group: group)
        } else if !hasLoaded, let name = group?.name ?? groupName {
            topBar(name: name, group: nil)
        }
    }

    private var feedScroll: some View {
        ScrollView {
            scrollOffsetReader
            VStack(alignment: .leading, spacing: 16) {
                AsyncStateView(isLoading: isLoading, error: error, topPadding: 60, hasLoaded: hasLoaded, retry: { await load() }) {
                    if isMember { looksSection } else { membersOnlyState }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .background(GeometryReader { Color.clear.preference(key: ContentHeightKey.self, value: $0.size.height) })
        }
        .clearsTabBar()
        .background(GeometryReader { Color.clear.preference(key: ViewportHeightKey.self, value: $0.size.height) })
        .coordinateSpace(name: Self.scrollSpace)
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .onPreferenceChange(ViewportHeightKey.self) { viewportHeight = $0 }
        .onPreferenceChange(ScrollOffsetKey.self) { handleScroll($0) }
    }

    private var membersOnlyState: some View {
        EmptyStateView(
            icon: "lock",
            title: "Members only",
            message: "You're not a member of \(group?.name ?? "this group"). Ask a member for the invite code."
        )
        .padding(.top, 40)
    }

    @ViewBuilder
    private func routeDestination(_ route: FitCheckRoute) -> some View {
        if let item = items.first(where: { $0.id == route.id }) {
            FitCheckReelView(item: item, voterId: appState.userId,
                             isFollowing: followingIDs.contains(item.creatorId),
                             initialPhotoIndex: route.photoIndex,
                             onToggleFollow: { setFollowing($0, creatorId: item.creatorId) })
        } else {
            FitCheckDetailView(fitCheckId: route.id)
        }
    }

    private var dialogHost: some View {
        mainColumn
            .alert("Rename group", isPresented: $showRename) {
                TextField("Group name", text: $newName)
                Button("Save") { Task { await rename() } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Leave this group?", isPresented: $showLeave) {
                Button("Leave group", role: .destructive) { Task { await leave() } }
            }
            .confirmationDialog("Delete this group?", isPresented: $showDelete) {
                Button("Delete group", role: .destructive) { Task { await deleteBoard() } }
            } message: {
                Text("Members will lose access. Posts in this group will no longer appear in a group.")
            }
            .confirmationDialog("Remove this member?", isPresented: Binding(
                get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }
            )) {
                Button("Remove member", role: .destructive) {
                    if let memberToRemove { Task { await remove(memberToRemove) } }
                }
            }
    }

    // MARK: - Scroll-driven avatar row

    private var scrollOffsetReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named(Self.scrollSpace)).minY)
        }
        .frame(height: 0)
    }

    private func handleScroll(_ offset: CGFloat) {
        let result = AvatarRowScrollRule.evaluate(
            offset: offset, lastOffset: lastScrollOffset,
            contentHeight: contentHeight, viewportHeight: viewportHeight
        )
        lastScrollOffset = result.anchor
        guard let shouldShow = result.shouldShow, shouldShow != avatarRowVisible else { return }
        withAnimation(Theme.animation(Theme.snap, reduceMotion: reduceMotion)) { avatarRowVisible = shouldShow }
    }

    // MARK: - Header

    private func topBar(name: String, group: FashionGroup?) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(Theme.editorialFont(size: 28, relativeTo: .title))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityAddTraits(.isHeader)
                if let date = group?.createdAt {
                    Text("Created \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            Spacer(minLength: 8)
            if let group {
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                        .font(Theme.bodyEmphasis)
                        .foregroundStyle(Theme.ink)
                        .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                        .background(Theme.muted, in: Circle())
                }
                .accessibilityLabel("Post to group")
                optionsMenu(group)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func optionsMenu(_ group: FashionGroup) -> some View {
        Menu {
            Button("Members") { showMembers = true }
            ShareLink(item: GroupInvite.text(for: group)) { Text("Invite friends") }
            if isOwner {
                Button("Rename group") { newName = group.name; showRename = true }
                Button("Delete group", role: .destructive) { showDelete = true }
            } else {
                Button("Leave group", role: .destructive) { showLeave = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(Theme.ink)
                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Group options")
    }

    private var memberRowHeight: CGFloat { max(avatarSize, Theme.minTapSize) + 8 }

    private var memberRow: some View {
        memberRowButton
            .frame(height: avatarRowVisible ? memberRowHeight : 0, alignment: .top)
            .clipped()
            .opacity(avatarRowVisible ? 1 : 0)
            .accessibilityHidden(!avatarRowVisible)
    }

    private var memberRowButton: some View {
        Button { showMembers = true } label: {
            HStack(spacing: 10) {
                ForEach(Array(members.prefix(Self.visibleMemberLimit))) { member in
                    AvatarView(url: member.avatarUrl, nickname: member.nickname, size: avatarSize)
                }
                Text("\(members.count) member\(members.count == 1 ? "" : "s")")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.mutedForeground)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .frame(minHeight: Theme.minTapSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(members.count) members")
        .accessibilityHint("Shows the member list")
        .accessibilityIdentifier("groupFeed.memberRow")
    }

    // MARK: - Members sheet

    private func membersSheet(_ group: FashionGroup) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    InviteCodeCapsule(code: group.inviteCode)
                    ForEach(members) { member in memberRowItem(member, group: group) }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showMembers = false } } }
        }
    }

    private func memberRowItem(_ member: GroupMemberDisplay, group: FashionGroup) -> some View {
        HStack(spacing: 10) {
            AvatarView(url: member.avatarUrl, nickname: member.nickname, size: avatarSize)
            Text(member.nickname ?? "Someone").font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
            if member.id == group.creatorId {
                Text("Owner")
                    .font(Theme.micro)
                    .foregroundStyle(Theme.accentDeep)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accentTint, in: Capsule(style: .continuous))
            }
            Spacer()
            if isOwner && member.id != appState.userId {
                Button("Remove") { memberToRemove = member }
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
                    .frame(minHeight: Theme.minTapSize)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Remove \(member.nickname ?? "member")")
            }
        }
    }

    // MARK: - Feed

    @ViewBuilder private var looksSection: some View {
        if items.isEmpty {
            EmptyStateView(
                icon: "photo.on.rectangle",
                title: "No looks yet",
                message: "No looks in this group yet. Add the first one.",
                actionTitle: "+ Post to group"
            ) { showCreate = true }
            .padding(.vertical, 20)
        } else {
            LazyVStack(spacing: 24) {
                ForEach(items) { item in GroupFeedCard(item: item) }
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            // fetchMyGroups only returns groups the user belongs to, so it doubles as the membership check.
            let mine = try await API.fetchMyGroups(profileId: appState.userId)
            group = mine.first(where: { $0.id == groupId })
            isMember = group != nil
            guard isMember else { hasLoaded = true; return }
            async let membersTask = API.fetchGroupMembers(groupId: groupId)
            async let feedTask = API.fetchGroupFeed(groupId: groupId)
            members = try await membersTask
            items = try await feedTask
            followingIDs = await Log.attempt("Load following IDs") {
                try await API.fetchFollowingIDs(userId: appState.userId)
            } ?? followingIDs
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = friendlyMessage(for: error, fallback: "Couldn’t load this content. Please try again.")
        }
    }

    private func setFollowing(_ follow: Bool, creatorId: UUID) {
        followingIDs = follow ? followingIDs.union([creatorId]) : followingIDs.subtracting([creatorId])
        Task {
            do {
                try await API.setFollowing(follow, followerId: appState.userId, followingId: creatorId)
            } catch {
                followingIDs = follow ? followingIDs.subtracting([creatorId]) : followingIDs.union([creatorId])
                self.error = friendlyMessage(for: error, fallback: "Couldn’t update following. Please try again.")
            }
        }
    }

    private func rename() async {
        do {
            try await API.renameGroup(id: groupId, name: newName)
            appState.contentDidChange()
            await load()
        } catch { self.error = friendlyMessage(for: error, fallback: "Couldn’t rename the group. Please try again.") }
    }

    private func leave() async {
        do {
            try await API.leaveGroup(id: groupId, profileId: appState.userId)
            appState.contentDidChange()
            dismiss()
        } catch { self.error = friendlyMessage(for: error, fallback: "Couldn’t leave the group. Please try again.") }
    }

    private func deleteBoard() async {
        do {
            try await API.deleteGroup(id: groupId)
            appState.contentDidChange()
            dismiss()
        } catch { self.error = friendlyMessage(for: error, fallback: "Couldn’t delete the group. Please try again.") }
    }

    private func remove(_ member: GroupMemberDisplay) async {
        do {
            try await API.removeGroupMember(groupId: groupId, profileId: member.id)
            memberToRemove = nil
            await load()
        } catch { self.error = friendlyMessage(for: error, fallback: "Couldn’t remove that member. Please try again.") }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// YouTube-style card: large first photo, then author avatar, title and metadata.
private struct GroupFeedCard: View {
    let item: FeedItemDTO

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 36

    private static let photoAspect: CGFloat = 4.0 / 3.0

    @State private var photoIndex = 0

    private var photoURLs: [URL] { PostCardContent.photoURLs(item.fitCheckPhotos) }

    private var title: String {
        let prompt = item.votePrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !prompt.isEmpty { return prompt }
        let caption = item.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return caption.isEmpty ? "Untitled" : caption
    }

    private var metadata: String {
        let author = item.profiles?.nickname ?? "Someone"
        let when = item.createdAt.formatted(.relative(presentation: .named))
        return "\(author) · \(when)"
    }

    var body: some View {
        NavigationLink(value: FitCheckRoute(id: item.id)) {
            VStack(alignment: .leading, spacing: 10) {
                // Ticks once at expiry so ended posts stop rotating.
                TimelineView(.expiry(item.expiresAt)) { _ in
                    PhotoCarousel(urls: photoURLs, currentIndex: $photoIndex,
                                  autoAdvance: !isExpired(item.expiresAt),
                                  accessibilityIdentifier: "groupFeed.photoCarousel")
                        .aspectRatio(Self.photoAspect, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .accessibilityHidden(true)
                HStack(alignment: .top, spacing: 10) {
                    AvatarView(url: item.profiles?.avatarUrl, nickname: item.profiles?.nickname, size: avatarSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.bodyEmphasis)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(metadata)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this Fit-Check")
        .accessibilityIdentifier("groupFeed.card")
    }
}
