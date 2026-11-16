import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var localWeather = LocalWeatherPromptModel()

    @State private var items: [FeedItemDTO] = []
    @State private var visibleItems: [FeedItemDTO] = []
    @State private var sort: FeedSortOption = .forYou
    @State private var mode: FeedMode = .forYou
    @State private var searchText = ""
    @State private var committedSearch = ""
    @State private var selectedOccasion: String?
    @State private var isSearchExpanded = false
    @State private var searchTask: Task<Void, Never>?
    @State private var commentItem: FeedItemDTO?
    @State private var notice: String?
    @Namespace private var occasionIndicator
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    /// Set while pull-to-refresh is running, so its own spinner isn't doubled.
    @State private var isPullRefreshing = false
    @State private var unreadCount = 0
    @State private var likedIDs: Set<UUID> = []
    @State private var openedRoute: FitCheckRoute?
    @State private var showChallenge = false
    // Open on the browsable Fit-Check feed. The immersive, one-look-at-a-time
    // reel remains available from the feed's Watch Fit-Checks control.
    @State private var showSwipeFeed = false
    @State private var followingIDs: Set<UUID> = []
    @State private var friendIDs: Set<UUID> = []
    @State private var graphRevision: Int?
    @State private var loggedImpressions: Set<UUID> = []
    @State private var pendingImpressions: [UUID] = []
    private static let impressionBatchSize = 10
    @State private var signalScores: [UUID: Int] = [:]
    @State private var nextOffset = 0
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var loadMoreFailed = false
    @State private var pendingFollowIDs: Set<UUID> = []
    @State private var loadID = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tabBarClearance) private var tabBarClearance

    private static let pagePadding: CGFloat = 20
    private static let pageSize = 24
    private static let cardSpacing: CGFloat = 16
    /// Posts have no card surface any more, so they need more air between them.
    private static let postSpacing: CGFloat = 28
    private static let searchDebounce: Duration = .milliseconds(300)
    private static let noticeDuration: Duration = .seconds(3)
    private static let reloadingOpacity = 0.5
    private static let reloadingIndicatorTopPadding: CGFloat = 24
    private static let occasionOptions: [(label: String, symbol: String)] = [
        ("Everyday", "sun.max"), ("Work", "briefcase"), ("Date", "heart"), ("Interview", "person.text.rectangle"),
        ("Party", "party.popper"), ("Travel", "airplane"), ("Wedding", "sparkles")
    ]

    /// Everything that requires re-fetching the item list. The social graph
    /// is only re-fetched when `revision` changes.
    private struct ReloadKey: Equatable {
        let revision: Int
        let mode: FeedMode
        let occasion: String?
        let search: String
    }

    private var reloadKey: ReloadKey {
        ReloadKey(revision: appState.contentRevision, mode: mode, occasion: selectedOccasion, search: committedSearch)
    }

    private var emptyFeedText: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedOccasion != nil {
            return "No looks match that. Try another search or occasion."
        }
        return mode == .following
            ? "No looks from your circle yet."
            : "Your feed is waiting for its first look. Post a Fit-Check to get started."
    }

    /// A filter, search or mode change is fetching while the previous results
    /// are still on screen.
    private var isReloadingFilters: Bool { isLoading && hasLoaded && !isPullRefreshing }

    var body: some View {
        Group {
            if showSwipeFeed { swipeFeed } else { editorialFeed }
        }
        .navigationBarHidden(true)
        .navigationDestination(for: FitCheckRoute.self) { route in routeDestination(route) }
        .navigationDestination(item: $openedRoute) { route in routeDestination(route) }
        .revisionTask(reloadKey) { await load(refreshGraph: graphRevision != appState.contentRevision) }
        .onChange(of: sort) { _, _ in refreshVisibleItems() }
        .onChange(of: mode) { _, _ in refreshVisibleItems() }
        .onChange(of: selectedOccasion) { _, _ in refreshVisibleItems() }
        .onChange(of: searchText) { _, _ in
            refreshVisibleItems()
            debounceSearch()
        }
        .sheet(item: $commentItem) { item in
            CommentThreadSheet(fitCheckId: item.id,
                               photoURLs: PostCardContent.photoURLs(item.fitCheckPhotos).map(\.absoluteString),
                               voterId: appState.userId, canComment: !isExpired(item.expiresAt))
                .presentationDetents([.large])
        }
        .overlay(alignment: .bottom) { noticeToast }
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: Self.noticeDuration)
            if !Task.isCancelled { notice = nil }
        }
        .onChange(of: appState.profile?.stylePreferences) { _, _ in refreshVisibleItems() }
    }

    /// The hold-to-vote screen when the post is in the loaded feed (the usual
    /// case for a card tap); the detail screen for links from elsewhere.
    @ViewBuilder
    private func routeDestination(_ route: FitCheckRoute) -> some View {
        if let item = items.first(where: { $0.id == route.id }) {
            FitCheckReelView(
                item: item,
                voterId: appState.userId,
                isFollowing: followingIDs.contains(item.creatorId),
                initialPhotoIndex: route.photoIndex,
                onToggleFollow: { toggleFollow(item.creatorId, follow: $0) },
                onEvent: { logEvent(item, event: $0) },
                onImpression: { logImpression(for: item) }
            )
        } else {
            FitCheckDetailView(fitCheckId: route.id)
        }
    }

    // MARK: - Swipe feed

    private var swipeFeed: some View {
        SwipeFeedView(
            items: visibleItems,
            voterId: appState.userId,
            followingIDs: followingIDs,
            isFollowingMode: mode == .following,
            isLoading: isLoading,
            hasLoaded: hasLoaded,
            error: error,
            onModeChange: { following in mode = following ? .following : .forYou },
            onBrowse: { withAnimation(Theme.animation(Theme.settle, reduceMotion: reduceMotion)) { showSwipeFeed = false } },
            onClose: { withAnimation(Theme.animation(Theme.settle, reduceMotion: reduceMotion)) { showSwipeFeed = false } },
            onToggleFollow: { creatorId, follow in toggleFollow(creatorId, follow: follow) },
            onEvent: { item, event in logEvent(item, event: event) },
            onImpression: { item in logImpression(for: item) },
            onLoadMore: { Task { await loadMoreIfNeeded() } },
            onRefresh: { await load(refreshGraph: true) },
            onRetry: { await load(refreshGraph: true) }
        )
        .background(.black)
        .ignoresSafeArea()
    }

    // MARK: - Editorial feed

    private var editorialFeed: some View {
        ScrollView {
            // Posts run edge to edge, so the page padding is applied per
            // section instead of on the whole column.
            VStack(alignment: .leading, spacing: Self.cardSpacing) {
                occasionRow
                // With posts on screen the challenge sits after the first one
                // (see `feedList`), so a photo is the first thing people see.
                if visibleItems.isEmpty { challengeCard.padding(.horizontal, Self.pagePadding) }
                feedList
                    .opacity(isReloadingFilters ? Self.reloadingOpacity : 1)
                    .overlay(alignment: .top) { reloadingIndicator }
                    .animation(Theme.animation(Theme.quick, reduceMotion: reduceMotion), value: isReloadingFilters)
                olderFitChecksButton.padding(.horizontal, Self.pagePadding)
            }
            .padding(.vertical, Self.cardSpacing)
        }
        .safeAreaPadding(.bottom, tabBarClearance)
        .background(Theme.background)
        .safeAreaInset(edge: .top, spacing: 0) { pinnedFilters }
        .refreshable {
            isPullRefreshing = true
            defer { isPullRefreshing = false }
            await load(refreshGraph: true)
        }
        .onDisappear { flushImpressions() }
        .sheet(isPresented: $showChallenge) {
            CreateFitCheckView(initialOccasion: DailyChallenge.today.occasion)
        }
    }

    /// Shown over the dimmed list while new results load, so a filter change
    /// never looks like the app ignored the tap.
    @ViewBuilder
    private var reloadingIndicator: some View {
        if isReloadingFilters {
            ProgressView()
                .padding(.top, Self.reloadingIndicatorTopPadding)
                .accessibilityLabel("Updating Fit-Checks")
        }
    }

    private var challengeCard: some View {
        DailyChallengeCard(
            challenge: localWeather.conditions.map(DailyChallenge.forWeather) ?? .today,
            weather: localWeather.conditions,
            isWeatherLoading: localWeather.isLoading,
            locationDenied: localWeather.locationDenied,
            errorMessage: localWeather.errorMessage,
            onUseWeather: { localWeather.requestWeather() },
            onJoin: { showChallenge = true }
        )
    }

    /// Icon buttons stop growing past `xxxLarge` so they never crowd the segments.
    private var headerButtons: some View {
        HStack(spacing: 8) {
            FeedIconButton(
                systemImage: "play.rectangle",
                accessibilityLabel: "Watch Fit-Checks",
                accessibilityIdentifier: "watchFeedButton"
            ) {
                withAnimation(Theme.animation(Theme.settle, reduceMotion: reduceMotion)) { showSwipeFeed = true }
            }
            FeedIconButton(
                systemImage: isSearchExpanded ? "xmark" : "magnifyingglass",
                accessibilityLabel: isSearchExpanded ? "Close search" : "Search Fit-Checks"
            ) {
                if isSearchExpanded { searchText = "" }
                withAnimation(Theme.animation(Theme.snap, reduceMotion: reduceMotion)) { isSearchExpanded.toggle() }
            }
            NavigationLink {
                NotificationsView(onRead: {
                    appState.contentDidChange()
                    Task { await loadUnreadCount() }
                })
            } label: {
                FeedBellIcon(unreadCount: unreadCount)
            }
            .buttonStyle(InstantPressStyle())
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .fixedSize()
    }

    /// Filters stay visible while the feed scrolls; opaque so text never
    /// sits on a blur.
    private var pinnedFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            // One row: For You / Following on the left, tools on the right.
            HStack(spacing: 8) {
                modeRow
                headerButtons
            }
            .padding(.horizontal, Self.pagePadding)
            if isSearchExpanded {
                FeedSearchField(text: $searchText).padding(.horizontal, Self.pagePadding)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background.ignoresSafeArea(edges: .top))
    }

    private var modeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                FeedModeSegments(mode: $mode) { select($0) }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        // The sort button's soft shadow would otherwise be cut off into a faint
        // box at the scroll view's edge.
        .scrollClipDisabled()
    }

    private var occasionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Sort lives with the other filters, so the top row stays short.
                if mode == .forYou { FeedSortMenu(sort: $sort) }
                FeedOccasionChip(label: "All", symbol: "square.grid.2x2", isSelected: selectedOccasion == nil,
                                 namespace: occasionIndicator) { selectedOccasion = nil }
                ForEach(Self.occasionOptions, id: \.label) { option in
                    FeedOccasionChip(label: option.label, symbol: option.symbol,
                                     isSelected: selectedOccasion == option.label,
                                     namespace: occasionIndicator) { selectedOccasion = option.label }
                }
            }
        }
        // Edge to edge so the last visible chip is cut by the screen, not the page padding.
        .contentMargins(.horizontal, Self.pagePadding, for: .scrollContent)
        // Keeps the sort button's soft shadow from being cut into a faint box.
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var noticeToast: some View {
        if let notice {
            Text(notice)
                .font(Theme.bodyEmphasis)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.ink.opacity(0.92), in: Capsule())
                .padding(.bottom, tabBarClearance + 12)
                .transition(.opacity)
                .accessibilityIdentifier("feed-notice")
                .onAppear { AccessibilityNotification.Announcement(notice).post() }
        }
    }

    private var feedList: some View {
        AsyncStateView(isLoading: isLoading, error: error, isEmpty: visibleItems.isEmpty,
                       emptyText: emptyFeedText, topPadding: 40, hasLoaded: hasLoaded,
                       retry: { await load(refreshGraph: true) }, emptyIcon: "hanger",
                       emptyTitle: "No Fit-Checks yet", emptyActionTitle: "Post a Fit-Check",
                       emptyAction: { showChallenge = true }, skeleton: .cards) {
            LazyVStack(spacing: Self.postSpacing) {
                ForEach(visibleItems) { item in
                    FeedPostCard(
                        item: item,
                        isLiked: likedIDs.contains(item.id),
                        viewerId: appState.userId,
                        isFollowing: followingIDs.contains(item.creatorId),
                        showsFollow: item.creatorId != appState.userId,
                        onToggleFollow: { follow in toggleFollow(item.creatorId, follow: follow) },
                        onLike: { like in try await setLiked(like, item: item) },
                        onOpen: { openedRoute = FitCheckRoute(id: item.id, photoIndex: $0) },
                        onComment: { commentItem = item }
                    )
                    .scrollTransition(.animated(Theme.settle), axis: .vertical) { [reduceMotion] view, phase in
                        view
                            .opacity(reduceMotion || phase.isIdentity ? 1 : 0.6)
                            .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.97)
                    }
                    .onAppear { logImpression(for: item) }
                    if item.id == visibleItems.first?.id {
                        challengeCard.padding(.horizontal, Self.pagePadding)
                    }
                }
                loadMoreFooter
            }
        }
    }

    /// Tail of the list: a spinner while paging, a retry row after a failed
    /// page, otherwise an invisible sentinel that requests the next page when
    /// it scrolls into view.
    @ViewBuilder
    private var loadMoreFooter: some View {
        if isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else if loadMoreFailed {
            HStack {
                Text("Couldn’t load more.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.mutedForeground)
                Button("Retry") { Task { await loadMoreIfNeeded() } }
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.accentDeep)
                    .frame(minHeight: FeedLayout.minHitSize)
            }
            .frame(maxWidth: .infinity)
        } else if canLoadMore {
            Color.clear
                .frame(height: 1)
                .onAppear { Task { await loadMoreIfNeeded() } }
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var olderFitChecksButton: some View {
        if hasLoaded && visibleItems.isEmpty && canLoadMore {
            Button("Search older Fit-Checks") { Task { await loadMoreIfNeeded() } }
                .buttonStyle(OutlineButtonStyle())
        }
    }

    // MARK: - Selection and derived state

    private func select(_ newMode: FeedMode) {
        guard mode != newMode else { return }
        mode = newMode
    }

    private func refreshVisibleItems() {
        let ranked = FeedRanking.visibleItems(
            items: items,
            searchText: searchText,
            occasion: selectedOccasion,
            mode: mode,
            sort: sort,
            stylePreferences: appState.profile?.stylePreferences ?? [],
            signalScores: signalScores
        )
        visibleItems = ranked
    }

    private func setItems(_ newItems: [FeedItemDTO]) {
        items = newItems
        refreshVisibleItems()
    }

    private func debounceSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled else { return }
            committedSearch = searchText
        }
    }

    // MARK: - Loading

    private func loadUnreadCount() async {
        // A badge failure must not hide an otherwise usable feed.
        if let count = await Log.attempt("Load unread count", { try await API.fetchUnreadNotificationCount(recipientId: appState.userId) }) {
            unreadCount = count
        }
    }

    /// Scores are fetched alongside a reload and applied together with the new
    /// items, so visible cards are never re-ranked underneath the user.
    private func fetchSignalScores() async -> [UUID: Int] {
        do { return try await API.fetchFeedSignalScores(userId: appState.userId) } catch {
            Log.app.error("Load feed signal scores failed: \(error.localizedDescription)")
            return signalScores
        }
    }

    private func fetchSocialGraph() async throws -> (following: Set<UUID>, friends: Set<UUID>) {
        async let followingTask = API.fetchFollowingIDs(userId: appState.userId)
        async let friendsTask = API.fetchFriendIDs(userId: appState.userId)
        let following = try await followingTask
        let friends: Set<UUID>
        do { friends = try await friendsTask } catch {
            Log.app.error("Load friend IDs failed: \(error.localizedDescription)")
            friends = friendIDs // keep the last known list instead of hiding friends-only posts
        }
        return (following, friends)
    }

    /// Reloads the first page. The social graph, signal scores and unread
    /// count are only refreshed when `refreshGraph` is set (initial load,
    /// pull-to-refresh, content changes) so typing a search or changing
    /// filters only re-fetches items.
    private func load(refreshGraph: Bool) async {
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        error = nil
        nextOffset = 0
        canLoadMore = true
        loadMoreFailed = false
        defer { if loadID == requestID { isLoading = false } }
        do {
            let needsGraph = refreshGraph || graphRevision == nil
            async let freshScores = needsGraph ? fetchSignalScores() : signalScores
            let graph = needsGraph ? try await fetchSocialGraph() : (following: followingIDs, friends: friendIDs)
            let page = try await API.fetchFeedPage(offset: 0, limit: Self.pageSize,
                                                   search: committedSearch, occasion: selectedOccasion,
                                                   followingIDs: mode == .following ? graph.following : nil,
                                                   friendIDs: graph.friends)
            let scores = await freshScores
            guard loadID == requestID else { return }
            signalScores = scores
            followingIDs = graph.following
            friendIDs = graph.friends
            nextOffset = page.fetchedCount
            canLoadMore = page.fetchedCount == Self.pageSize
            setItems(page.items)
            hasLoaded = true
            Task { await loadLikedState(for: page.items) }
            if needsGraph { refreshSideData() }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            if loadID == requestID { self.error = "Couldn’t load this content. Please try again." }
        }
    }

    private func refreshSideData() {
        graphRevision = appState.contentRevision
        Task { await loadUnreadCount() }
    }

    private func loadMoreIfNeeded() async {
        guard !isLoading, !isLoadingMore, canLoadMore else { return }
        loadMoreFailed = false
        isLoadingMore = true
        defer { isLoadingMore = false }
        // A reload (search, filter, refresh) replaces `items`; a page fetched
        // for the old query must not be appended to the new list.
        let requestID = loadID
        do {
            let page = try await API.fetchFeedPage(offset: nextOffset, limit: Self.pageSize,
                                                   search: committedSearch, occasion: selectedOccasion,
                                                   followingIDs: mode == .following ? followingIDs : nil,
                                                   friendIDs: friendIDs)
            guard loadID == requestID else { return }
            let existing = Set(items.map(\.id))
            let fresh = page.items.filter { !existing.contains($0.id) }
            setItems(items + fresh)
            Task { await loadLikedState(for: fresh) }
            nextOffset += page.fetchedCount
            canLoadMore = page.fetchedCount == Self.pageSize
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            // Pagination is additive. Keep the loaded feed usable and offer an
            // explicit retry instead of re-requesting in a loop.
            if loadID == requestID { loadMoreFailed = true }
        }
    }

    // MARK: - Likes

    /// Likes are best-effort: if the engagement tables are unavailable the feed
    /// still works and every post simply shows as not liked.
    private func loadLikedState(for loaded: [FeedItemDTO]) async {
        let ids = loaded.map(\.id)
        guard let liked = await Log.attempt("Load liked posts", {
            try await API.fetchLikedFitCheckIDs(among: ids, userId: appState.userId)
        }) else { return }
        likedIDs.formUnion(liked)
    }

    /// Throws so `LikeButton` can roll back its optimistic state.
    private func setLiked(_ like: Bool, item: FeedItemDTO) async throws {
        do {
            if like {
                try await API.likeFitCheck(id: item.id, userId: appState.userId)
                likedIDs.insert(item.id)
            } else {
                try await API.unlikeFitCheck(id: item.id, userId: appState.userId)
                likedIDs.remove(item.id)
            }
        } catch {
            if !(error is CancellationError) {
                Log.app.error("Like toggle failed: \(error.localizedDescription)")
                withAnimation(Theme.animation(Theme.quick, reduceMotion: reduceMotion)) {
                    notice = friendlyMessage(for: error, fallback: "Couldn’t update your like. Please try again.")
                }
            }
            throw error
        }
    }

    // MARK: - Actions

    private func toggleFollow(_ creatorId: UUID, follow: Bool) {
        guard pendingFollowIDs.insert(creatorId).inserted else { return }
        setFollowing(creatorId, follow)
        Task {
            defer { pendingFollowIDs.remove(creatorId) }
            do {
                try await API.setFollowing(follow, followerId: appState.userId, followingId: creatorId)
                logEventForCreator(creatorId, event: follow ? "follow" : "unfollow")
            } catch {
                // Only undo our own optimistic change.
                if followingIDs.contains(creatorId) == follow { setFollowing(creatorId, !follow) }
                withAnimation(Theme.animation(Theme.quick, reduceMotion: reduceMotion)) {
                    notice = "Couldn’t update your following list. Please try again."
                }
            }
        }
    }

    private func setFollowing(_ creatorId: UUID, _ follow: Bool) {
        followingIDs = follow ? followingIDs.union([creatorId]) : followingIDs.subtracting([creatorId])
    }

    private func logImpression(for item: FeedItemDTO) {
        guard loggedImpressions.insert(item.id).inserted else { return }
        pendingImpressions.append(item.id)
        if pendingImpressions.count >= Self.impressionBatchSize { flushImpressions() }
    }

    private func flushImpressions() {
        guard !pendingImpressions.isEmpty else { return }
        let ids = pendingImpressions
        pendingImpressions = []
        let userId = appState.userId
        Task {
            _ = await Log.attempt("Log feed impressions") {
                try await API.logFeedEvents(userId: userId, fitCheckIds: ids, event: "impression")
            }
        }
    }

    private func logEvent(_ item: FeedItemDTO, event: String) {
        Task {
            _ = await Log.attempt("Log feed event") {
                try await API.logFeedEvent(userId: appState.userId, fitCheckId: item.id, event: event)
            }
        }
    }

    private func logEventForCreator(_ creatorId: UUID, event: String) {
        guard let item = items.first(where: { $0.creatorId == creatorId }) else { return }
        logEvent(item, event: event)
    }
}

/// Covers the status bar with the screen background so scrolled content
/// never runs under (and collides with) the clock and battery. Drawn as an
/// overlay, so it does not change layout.
private struct StatusBarBackdrop: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            GeometryReader { proxy in
                Theme.background
                    .frame(height: proxy.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
            }
            .frame(height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func statusBarBackdrop() -> some View { modifier(StatusBarBackdrop()) }
}
