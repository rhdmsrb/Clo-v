@preconcurrency import SwiftUI
import PhotosUI

/// Where the profile menu navigates.
private enum ProfileDestination: Hashable {
    case wardrobe, groups, friends, yourWeek, privacy, appearance, settings, notifications
}

@MainActor
struct AccountView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isTabActive) private var isTabActive
    @Environment(\.scenePhase) private var scenePhase

    @State private var unreadCount = 0
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var avatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var terminateTarget: UUID?
    @State private var deleteTarget: UUID?
    @State private var isDeletingAccount = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var showingAnalytics = false
    @State private var followerIDs: Set<UUID> = []
    @State private var followingIDs: Set<UUID> = []
    @State private var selectedFollowList: ProfileFollowList?
    @State private var destination: ProfileDestination?
    @State private var openedRoute: FitCheckRoute?
    @State private var segment: ProfileSegment = .live
    @State private var groups: [FashionGroup] = []
    @State private var groupAddMode: GroupAddSheet.Mode?
    @State private var liveVotes: [MyFitCheck] = []
    @State private var archivedVotes: [MyFitCheck] = []
    @State private var savedPosts: [MyFitCheck] = []
    @State private var savedState: SavedLoadState = .notLoaded
    @State private var isLoadingSaved = false

    private static let heroAvatarSize: CGFloat = 72
    private static let savedPageSize = 60

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topRow
                statsAndGroups
                actionButtons
                    .padding(.bottom, -12)
                if showingAnalytics {
                    StyleInsightsView(inline: true)
                    WardrobeInsightsView()
                }
                segmentPicker
                AsyncStateView(isLoading: isLoading, error: error, topPadding: 20, hasLoaded: hasLoaded, retry: { await load() }) {
                    postsGrid
                }
            }
            .padding(20)
        }
        .clearsTabBar()
        .background(Theme.background)
        .accessibilityIdentifier("profile.root")
        .revisionTask(appState.contentRevision) { await load() }
        .task(id: isTabActive && scenePhase == .active) {
            guard isTabActive, scenePhase == .active else { return }
            await loadUnreadCount()
        }
        .refreshable {
            async let reloadInbox: Void = loadUnreadCount()
            await load()
            await reloadInbox
        }
        .onChange(of: segment) { _, newSegment in
            if newSegment == .saved && savedState == .notLoaded { Task { await loadSaved() } }
        }
        .navigationDestination(item: $destination) { destinationView($0) }
        .navigationDestination(item: $openedRoute) { ProfilePostView(fitCheckId: $0.id) }
        .navigationDestination(for: FitCheckRoute.self) { FitCheckVoteLoader(fitCheckId: $0.id) }
        .sheet(item: $groupAddMode) { mode in
            GroupAddSheet(initialMode: mode) { await load() }
        }
        .sheet(item: $selectedFollowList) { list in
            ProfileFollowListView(userId: appState.userId, initialList: list)
                .environmentObject(appState)
        }
        .modifier(ProfileConfirmations(
            showDeleteAccount: $showingDeleteAccountConfirmation,
            terminateTarget: $terminateTarget,
            deleteTarget: $deleteTarget,
            onDeleteAccount: { Task { await deleteAccount() } },
            onTerminate: { id in Task { await terminate(id) } },
            onDelete: { id in Task { await delete(id) } }
        ))
    }

    private var statsAndGroups: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProfileStatsRow(
                fitChecks: liveVotes.count + archivedVotes.count,
                followers: followerIDs.count,
                following: followingIDs.count,
                onFollowers: { selectedFollowList = .followers },
                onFollowing: { selectedFollowList = .following }
            )
            ProfileGroupsRow(
                groups: groups,
                onCreate: { groupAddMode = .create },
                onJoin: { groupAddMode = .join }
            )
        }
    }

    private var segmentPicker: some View {
        Picker("Posts", selection: $segment) {
            ForEach(ProfileSegment.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityIdentifier("profile.segment")
    }

    // MARK: - Header

    @ViewBuilder
    private var topRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                headerActions.frame(maxWidth: .infinity, alignment: .trailing)
                HStack(spacing: 14) { profileIdentity }
            }
        } else {
            HStack(spacing: 14) {
                profileIdentity
                headerActions
            }
        }
    }

    @ViewBuilder
    @MainActor private var profileIdentity: some View {
        let nickname = appState.profile?.nickname
        let avatarURL = appState.profile?.avatarUrl
        let avatarSize = Self.heroAvatarSize
        let uploading = isUploadingAvatar
        PhotosPicker(selection: $avatarItem, matching: .images) {
            ZStack {
                AvatarView(url: avatarURL, nickname: nickname, size: avatarSize, ringed: true)
                if uploading { ProgressView().tint(.white) }
            }
            .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
            .contentShape(Circle())
        }
        .onChange(of: avatarItem) { _, newItem in
            Task { await uploadAvatar(newItem) }
        }
        .accessibilityLabel("Change profile photo")

        Text(nickname ?? "Your profile")
            .font(Theme.editorialFont(size: 28, relativeTo: .title))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            Button { destination = .notifications } label: {
                FeedBellIcon(unreadCount: unreadCount)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .buttonStyle(InstantPressStyle())
            .accessibilityLabel("Notifications")
            .accessibilityValue(unreadCount > 0 ? "\(unreadCount) unread" : "")
            .accessibilityIdentifier("profile.notifications")

            menu
        }
    }

    private func loadUnreadCount() async {
        guard destination != .notifications else { return }
        do {
            let count = try await API.fetchUnreadNotificationCount(recipientId: appState.userId)
            guard !Task.isCancelled, destination != .notifications else { return }
            unreadCount = count
        } catch {
            if !Task.isCancelled {
                Log.app.error("Load unread notifications failed: \(error.localizedDescription)")
            }
        }
    }

    private var menu: some View {
        Menu {
            Button("Wardrobe", systemImage: "hanger") { destination = .wardrobe }
                .accessibilityIdentifier("profileShortcut_Wardrobe")
            Button("Groups", systemImage: "person.3") { destination = .groups }
                .accessibilityIdentifier("profileShortcut_Groups")
            Button("Friends", systemImage: "person.2") { destination = .friends }
                .accessibilityIdentifier("profileShortcut_Friends")
            Button("Your week", systemImage: "chart.bar") { destination = .yourWeek }
                .accessibilityIdentifier("yourWeekButton")
            Button("Privacy", systemImage: "lock.shield") { destination = .privacy }
                .accessibilityIdentifier("profileShortcut_Privacy")
            Button("Appearance", systemImage: "paintpalette") { destination = .appearance }
                .accessibilityIdentifier("profileShortcut_Appearance")
            Button("Settings", systemImage: "gearshape") { destination = .settings }
                .accessibilityIdentifier("settingsButton")
            Divider()
            Button("Log out", systemImage: "rectangle.portrait.and.arrow.right") {
                Task { await appState.signOut() }
            }
            .accessibilityIdentifier("profile.logout")
            Button("Delete account", systemImage: "trash", role: .destructive) {
                showingDeleteAccountConfirmation = true
            }
            .disabled(isDeletingAccount)
            .accessibilityIdentifier("profile.deleteAccount")
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.ink)
                .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                .background(Theme.muted, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel("Profile menu")
        .accessibilityIdentifier("profile.menu")
    }

    @ViewBuilder
    private func destinationView(_ destination: ProfileDestination) -> some View {
        switch destination {
        case .wardrobe: WardrobeView()
        case .groups: GroupsView(embedded: true)
        case .friends: FriendsView()
        case .yourWeek: StyleInsightsView()
        case .privacy: PrivacyView()
        case .appearance: AppearanceView()
        case .settings: SettingsView()
        case .notifications: NotificationsView { unreadCount = $0 }
        }
    }

    private var actionButtons: some View {
        ProfileActionTabs(onAnalytics: { showingAnalytics.toggle() }, analyticsExpanded: showingAnalytics) {
            ShareLink(item: shareText) { Text("Share") }
                .accessibilityLabel("Share profile")
                .accessibilityIdentifier("profile.share")
        }
    }

    /// No profile deep link exists yet (see ShareURL, spec D12), so share text.
    private var shareText: String {
        let name = appState.profile?.nickname ?? "me"
        return "Check out \(name) on CLO·V"
    }

    // MARK: - Posts grid

    private var visiblePosts: [MyFitCheck] {
        ProfilePosts.posts(for: segment, live: liveVotes, ended: archivedVotes, saved: savedPosts)
    }

    @ViewBuilder
    private var postsGrid: some View {
        if visiblePosts.isEmpty {
            emptyState
        } else {
            let ratios = ProfilePosts.ratios(for: visiblePosts)
            MasonryGrid(
                items: visiblePosts,
                aspectRatio: { ratios[$0.id] ?? ProfilePosts.tileRatios[0] },
                onTap: { openedRoute = FitCheckRoute(id: $0.id) }
            ) { post in
                postTile(post)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if segment == .saved && isLoadingSaved {
            ProgressView().frame(maxWidth: .infinity).padding(18)
        } else {
            VStack(spacing: 12) {
                Text(ProfilePosts.emptyText(for: segment, saved: savedState))
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                if segment == .saved && (savedState == .failed || savedState == .unavailable) {
                    Button("Retry") { Task { await loadSaved() } }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("profile.savedRetry")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private func postTile(_ post: MyFitCheck) -> some View {
        let title = post.caption ?? "Fit-Check"
        let tile = RemoteImage(url: post.thumbnailURL ?? "", label: title)
        if segment == .saved {
            tile
        } else {
            let canTerminate = post.status == "live" && !isExpired(post.expiresAt)
            tile
                .overlay(alignment: .topTrailing) { overflowMenu(post, canTerminate: canTerminate, title: title) }
                .contextMenu { postActions(post, canTerminate: canTerminate) }
                .accessibilityAction(named: "Terminate \(title)") { if canTerminate { terminateTarget = post.id } }
                .accessibilityAction(named: "Delete \(title)") { deleteTarget = post.id }
        }
    }

    @ViewBuilder
    private func postActions(_ post: MyFitCheck, canTerminate: Bool) -> some View {
        if let url = ShareURL.make(fitCheckId: post.id) {
            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        if canTerminate {
            Button("End voting", systemImage: "stop.circle") { terminateTarget = post.id }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = post.id }
    }

    /// Visible alternative to the long-press menu.
    private func overflowMenu(_ post: MyFitCheck, canTerminate: Bool, title: String) -> some View {
        Menu {
            postActions(post, canTerminate: canTerminate)
        } label: {
            Image(systemName: "ellipsis")
                .font(Theme.bodyEmphasis)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.45), in: Circle())
                .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options for \(title)")
        .accessibilityIdentifier("profile.tileMenu")
    }

    // MARK: - Loading and actions

    /// The grid spinner is released after the main fetch; groups load concurrently
    /// and Saved loads only while its segment is selected.
    private func load() async {
        isLoading = true
        error = nil
        async let groupsLoad: Void = loadGroups()
        await loadProfileData()
        isLoading = false
        if segment == .saved { await loadSaved() }
        await groupsLoad
    }

    private func loadProfileData() async {
        async let followersTask = API.fetchFollowerIDs(userId: appState.userId)
        async let followingTask = API.fetchFollowingIDs(userId: appState.userId)
        async let friendsTask = API.fetchFriendIDs(userId: appState.userId)
        do {
            let all = try await API.fetchMyFitChecksWithStatus(creatorId: appState.userId)
            liveVotes = ProfilePosts.live(all, isExpired: isExpired)
            archivedVotes = ProfilePosts.ended(all, isExpired: isExpired)
            // Friendships are mutual, so friends count as both followers and
            // following (the feed already treats them this way).
            let friendIDs = try await friendsTask
            followerIDs = try await followersTask.union(friendIDs)
            followingIDs = try await followingTask.union(friendIDs)
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            Log.app.error("Account load failed: \(String(describing: error))")
            self.error = "Couldn’t load this content. Please try again."
        }
    }

    /// Groups and Saved are secondary: failures degrade quietly instead of blocking the profile.
    private func loadGroups() async {
        groups = (try? await API.fetchMyGroups(profileId: appState.userId)) ?? groups
    }

    private func loadSaved() async {
        isLoadingSaved = true
        defer { isLoadingSaved = false }
        do {
            let page = try await API.fetchSavedFeed(userId: appState.userId, offset: 0, limit: Self.savedPageSize)
            savedPosts = ProfilePosts.deduplicated(page.items.map { item in
                MyFitCheck(
                    id: item.id,
                    caption: item.votePrompt ?? item.caption,
                    status: "saved",
                    thumbnailURL: item.fitCheckPhotos.min(by: { $0.position < $1.position })?.imageUrl
                )
            })
            savedState = .loaded
        } catch is CancellationError {
            return
        } catch {
            savedPosts = []
            savedState = SavedLoadState.classify(error)
        }
    }

    private func terminate(_ id: UUID) async {
        do {
            try await API.terminateFitCheck(id: id, creatorId: appState.userId)
            Haptics.impact(.medium)
            await load()
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
        }
    }

    private func delete(_ id: UUID) async {
        do {
            try await API.deleteFitCheck(id: id, creatorId: appState.userId)
            Haptics.impact(.medium)
            await load()
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        error = nil
        do {
            try await API.deleteAccount()
            appState.accountDeleted()
        } catch {
            self.error = error.localizedDescription
        }
        isDeletingAccount = false
    }

    private func uploadAvatar(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            let image = try await item.loadImage()
            _ = try await API.updateAvatar(id: appState.userId, image: image)
            Haptics.success()
            await appState.refreshProfile()
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
        }
    }
}
