@preconcurrency import SwiftUI
import PhotosUI

/// Where the profile menu and Analytics button navigate.
private enum ProfileDestination: Hashable {
    case wardrobe, groups, friends, yourWeek, privacy, appearance
}

private enum ProfileSegment: String, CaseIterable, Identifiable {
    case live = "Live"
    case ended = "Ended"
    case saved = "Saved"
    var id: String { rawValue }
}

@MainActor
struct AccountView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var avatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var terminateTarget: UUID?
    @State private var deleteTarget: UUID?
    @State private var isDeletingAccount = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var showingEditProfile = false
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
    @State private var savedUnavailable = false

    private static let heroAvatarSize: CGFloat = 72
    private static let savedPageSize = 60
    /// MyFitCheck carries no photo dimensions, so tiles vary deterministically by index.
    private static let tileRatios: [CGFloat] = [0.75, 1.0, 0.7, 0.9, 1.1, 0.8, 0.65, 1.0]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topRow
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
                actionButtons
                    .padding(.bottom, -12)
                Picker("Posts", selection: $segment) {
                    ForEach(ProfileSegment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .frame(maxWidth: .infinity)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityIdentifier("profile.segment")

                AsyncStateView(isLoading: isLoading, error: error, topPadding: 20, hasLoaded: hasLoaded, retry: { await load() }) {
                    postsGrid
                }
            }
            .padding(20)
            // Leave room for the floating tab bar.
            .padding(.bottom, 88)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 82)
        }
        .background(Theme.background)
        .accessibilityIdentifier("profile.root")
        .revisionTask(appState.contentRevision) { await load() }
        .refreshable { await load() }
        .navigationDestination(item: $destination) { destinationView($0) }
        .navigationDestination(item: $openedRoute) { FitCheckVoteLoader(fitCheckId: $0.id) }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(profile: appState.profile)
        }
        .sheet(item: $groupAddMode) { mode in
            GroupAddSheet(initialMode: mode) { await load() }
        }
        .sheet(item: $selectedFollowList) { list in
            ProfileFollowListView(userId: appState.userId, initialList: list)
                .environmentObject(appState)
        }
        .alert("Delete your account?", isPresented: $showingDeleteAccountConfirmation) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your profile, Fit-Checks, photos, votes, comments, friends, and wardrobe items. This can't be undone.")
        }
        .confirmationDialog(
            "End voting on this Fit-Check?",
            isPresented: Binding(get: { terminateTarget != nil }, set: { if !$0 { terminateTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("End voting", role: .destructive) {
                if let id = terminateTarget { Task { await terminate(id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Voting closes immediately and can't be reopened.")
        }
        .confirmationDialog(
            "Delete this Fit-Check?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = deleteTarget { Task { await delete(id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes it along with its photos, votes, and comments. This can't be undone.")
        }
    }

    // MARK: - Header

    @MainActor private var topRow: some View {
        let nickname = appState.profile?.nickname
        return HStack(spacing: 14) {
            PhotosPicker(selection: $avatarItem, matching: .images) {
                ZStack {
                    AvatarView(url: appState.profile?.avatarUrl, nickname: nickname, size: Self.heroAvatarSize, ringed: true)
                    if isUploadingAvatar { ProgressView().tint(.white) }
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
            menu
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
        }
    }

    private var actionButtons: some View {
        ProfileActionTabs(
            onEdit: { showingEditProfile = true },
            onAnalytics: { destination = .yourWeek }
        ) {
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
        switch segment {
        case .live: liveVotes
        case .ended: archivedVotes
        case .saved: savedPosts
        }
    }

    private var emptyText: String {
        switch segment {
        case .live: "No live votes yet — post a Fit-Check to get started."
        case .ended: "Completed Fit-Checks will land here."
        case .saved: savedUnavailable ? "Saved posts aren't available right now." : "Posts you save will show up here."
        }
    }

    @ViewBuilder
    private var postsGrid: some View {
        if visiblePosts.isEmpty {
            Text(emptyText)
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        } else {
            let ratios = Dictionary(uniqueKeysWithValues: visiblePosts.enumerated().map { ($1.id, Self.tileRatios[$0 % Self.tileRatios.count]) })
            MasonryGrid(
                items: visiblePosts,
                aspectRatio: { ratios[$0.id] ?? Self.tileRatios[0] },
                onTap: { openedRoute = FitCheckRoute(id: $0.id) }
            ) { post in
                postTile(post)
            }
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
                .contextMenu {
                    if canTerminate {
                        Button("Terminate") { terminateTarget = post.id }
                    }
                    Button("Delete", role: .destructive) { deleteTarget = post.id }
                }
                .accessibilityAction(named: "Terminate \(title)") { if canTerminate { terminateTarget = post.id } }
                .accessibilityAction(named: "Delete \(title)") { deleteTarget = post.id }
        }
    }

    // MARK: - Loading and actions

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        async let followersTask = API.fetchFollowerIDs(userId: appState.userId)
        async let followingTask = API.fetchFollowingIDs(userId: appState.userId)
        async let friendsTask = API.fetchFriendIDs(userId: appState.userId)
        do {
            let all = try await API.fetchMyFitChecksWithStatus(creatorId: appState.userId)
            liveVotes = all.filter { $0.status == "live" && !isExpired($0.expiresAt) }
            archivedVotes = all.filter { $0.status == "archived" || isExpired($0.expiresAt) }
            // Friendships are mutual, so friends count as both followers and
            // following (the feed already treats them this way).
            let friendIDs = try await friendsTask
            followerIDs = try await followersTask.union(friendIDs)
            followingIDs = try await followingTask.union(friendIDs)
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load this content. Please try again."
        }
        await loadGroups()
        await loadSaved()
    }

    /// Groups and Saved are secondary: failures degrade quietly instead of blocking the profile.
    private func loadGroups() async {
        groups = (try? await API.fetchMyGroups(profileId: appState.userId)) ?? groups
    }

    private func loadSaved() async {
        do {
            let page = try await API.fetchSavedFeed(userId: appState.userId, offset: 0, limit: Self.savedPageSize)
            savedPosts = page.items.map { item in
                MyFitCheck(
                    id: item.id,
                    caption: item.votePrompt ?? item.caption,
                    status: "saved",
                    thumbnailURL: item.fitCheckPhotos.min(by: { $0.position < $1.position })?.imageUrl
                )
            }
            savedUnavailable = false
        } catch is CancellationError {
            return
        } catch {
            savedPosts = []
            savedUnavailable = true
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

@MainActor
struct StyleInsightsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var report: WeeklyStyleReport?
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("YOUR WEEK")
                    .font(Theme.micro)
                    .tracking(1.5)
                    .foregroundStyle(Theme.accentDeep)
                Text("Style momentum")
                    .font(Theme.editorialFont(size: 34))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                Text("A quick look at how you showed up this week.")
                    .font(Theme.font(.subheadline))
                    .foregroundStyle(Theme.mutedForeground)

                AsyncStateView(isLoading: isLoading, error: error, topPadding: 16, hasLoaded: hasLoaded, retry: { await load() }) {
                    if let report {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 14) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(Theme.iconCoral)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(report.currentStreak)-day streak")
                                        .font(Theme.title)
                                        .foregroundStyle(Theme.ink)
                                    Text(report.currentStreak == 0 ? "Start with one small style action today." : "Keep the momentum going.")
                                        .font(Theme.font(.caption))
                                        .foregroundStyle(Theme.mutedForeground)
                                }
                                Spacer()
                            }
                            .accessibilityElement(children: .combine)
                            .softCard()

                            LazyVGrid(columns: columns, spacing: 12) {
                                metric("Votes", value: report.votesCast, icon: "hand.thumbsup.fill")
                                metric("Fit-Checks", value: report.fitChecksPosted, icon: "camera.fill")
                                metric("Comments", value: report.commentsWritten, icon: "bubble.left.fill")
                                metric("New pieces", value: report.wardrobePiecesAdded, icon: "hanger")
                            }

                            if let occasion = report.topOccasion {
                                HStack {
                                    Text("Your top vibe: \(occasion)")
                                        .font(Theme.bodyEmphasis)
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                }
                                .softCard(radius: Theme.tileRadius, padding: 14)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Your week")
        .navigationBarTitleDisplayMode(.inline)
        .revisionTask(appState.contentRevision) { await load() }
        .refreshable { await load() }
    }

    private func metric(_ title: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accentDeep)
                .accessibilityHidden(true)
            Text("\(value)")
                .font(Theme.editorialFont(size: 28, relativeTo: .title2))
                .foregroundStyle(Theme.ink)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            Text(title)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .softCard(radius: Theme.tileRadius, padding: 14)
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            report = try await API.fetchWeeklyStyleReport(userId: appState.userId)
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load your weekly report. Please try again."
        }
    }
}

/// My-votes row shape — needs `status` and a position-1 thumbnail,
/// which the shared FeedItemDTO doesn't carry.
struct MyFitCheck: Identifiable {
    let id: UUID
    let caption: String?
    let status: String
    var expiresAt: Date? = nil
    let thumbnailURL: String?
}

@MainActor
private struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var nickname: String
    @State private var styles: Set<String>
    @State private var isSaving = false
    @State private var error: String?

    private static let styleOptions = ["Streetwear", "Casual", "Formal", "Athletic", "Vintage", "Minimalist", "Bohemian", "Glam"]

    init(profile: Profile?) {
        _nickname = State(initialValue: profile?.nickname ?? "")
        _styles = State(initialValue: Set(profile?.stylePreferences ?? []))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LabeledField(label: "NICKNAME") {
                        TextField("Your nickname", text: $nickname)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Text("WHAT'S YOUR STYLE?")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.mutedForeground)
                    FlowLayout(spacing: 8) {
                        ForEach(Self.styleOptions, id: \.self) { style in
                            ChipToggle(label: style, selected: styles.contains(style)) {
                                if styles.contains(style) { styles.remove(style) }
                                else { styles.insert(style) }
                            }
                        }
                    }
                    if let error { Text(error).font(Theme.label).foregroundStyle(Theme.danger) }
                    Button(isSaving ? "Saving…" : "Save profile") { Task { await save() } }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: isSaving))
                        .disabled(isSaving)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() async {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "^[A-Za-z0-9_]{3,20}$", options: .regularExpression) != nil else {
            error = "Nickname must be 3–20 letters, numbers, or underscores."
            return
        }
        guard !styles.isEmpty else { error = "Pick at least one style."; return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await API.saveOnboarding(nickname: trimmed, styles: styles.sorted())
            await appState.refreshProfile()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Opens the hold-to-vote screen for a post known only by id (profile tiles,
/// `clov://vote/<id>` links). Fetches the post, shows `FitCheckReelView` when
/// it is live and unexpired, and otherwise (ended, archived, blocked, not
/// found, or a load failure) falls back to `FitCheckDetailView`, which owns
/// the "Voting has ended" and error states.
struct FitCheckVoteLoader: View {
    let fitCheckId: UUID
    @EnvironmentObject private var appState: AppState

    private enum Phase {
        case loading
        case reel(FeedItemDTO)
        case fallback
    }

    @State private var phase: Phase = .loading
    @State private var isFollowingCreator = false

    var body: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .task(id: fitCheckId) { await load() }
        case .reel(let item):
            FitCheckReelView(
                item: item,
                voterId: appState.userId,
                isFollowing: isFollowingCreator,
                onToggleFollow: { setFollowing($0, creatorId: item.creatorId) }
            )
        case .fallback:
            FitCheckDetailView(fitCheckId: fitCheckId)
        }
    }

    private func load() async {
        guard let detail = try? await API.fetchFitCheckDetail(id: fitCheckId),
              detail.status == "live", !isExpired(detail.expiresAt) else {
            phase = .fallback
            return
        }
        // Without the real votes the reel would show a voter as "hasn't voted",
        // so a failed fetch falls back to the detail screen instead.
        let votes: [VoteRef]
        do {
            votes = try await API.fetchVotes(fitCheckId: fitCheckId)
        } catch {
            Log.app.error("FitCheckVoteLoader votes fetch failed: \(error.localizedDescription)")
            phase = .fallback
            return
        }
        let following = (try? await API.fetchFollowingIDs(userId: appState.userId)) ?? []
        isFollowingCreator = following.contains(detail.creatorId)
        phase = .reel(FeedItemDTO(
            id: detail.id,
            creatorId: detail.creatorId,
            caption: detail.caption,
            occasion: detail.occasion,
            audience: detail.audience,
            votePrompt: detail.votePrompt,
            createdAt: Date(),
            expiresAt: detail.expiresAt,
            fitCheckPhotos: detail.fitCheckPhotos,
            fitCheckVotes: votes,
            fitCheckComments: [],
            profiles: detail.profiles,
            isPublic: detail.isPublic
        ))
    }

    private func setFollowing(_ follow: Bool, creatorId: UUID) {
        isFollowingCreator = follow
        Task {
            do {
                try await API.setFollowing(follow, followerId: appState.userId, followingId: creatorId)
            } catch {
                isFollowingCreator = !follow
            }
        }
    }
}
