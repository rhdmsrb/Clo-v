import SwiftUI

/// Which screen the feed is serving: Home (everything, ranked) or the Vote tab
/// (only live posts the viewer has not voted on yet).
enum FeedStyle {
    case home, voteQueue
}

struct FeedView: View {
    var style: FeedStyle = .home

    @EnvironmentObject private var appState: AppState

    @State private var items: [FeedItemDTO] = []
    @State private var visibleItems: [FeedItemDTO] = []
    @State private var commentRevision: Int?
    @State private var commentItem: FeedItemDTO?
    @State private var notice: String?
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var likedIDs: Set<UUID> = []
    @State private var openedRoute: FitCheckRoute?
    @State private var followingIDs: Set<UUID> = []
    @State private var friendIDs: Set<UUID> = []
    @State private var graphRevision: Int?
    @State private var loggedImpressions: Set<UUID> = []
    @State private var pendingImpressions: [UUID] = []
    private static let impressionBatchSize = 10
    @State private var signalScores: [UUID: Int] = [:]
    @State private var nextCursor: API.HomeFeedCursor?
    @State private var nextOffset = 0
    @State private var canLoadMore = true
    @State private var showFriends = false
    @State private var isLoadingMore = false
    @State private var loadMoreFailed = false
    @State private var pendingFollowIDs: Set<UUID> = []
    @State private var pendingLikeIDs: Set<UUID> = []
    @State private var loadID = UUID()
    @State private var showSearch = false
    /// Selected Home filter chip (see `HomeFeedFilters`); unused in the vote queue.
    @State private var homeFilter = HomeFeedFilters.popular
    @State private var showNotifications = false
    @State private var unreadCount = 0
    @State private var firstPhotoDisplayed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tabBarClearance) private var tabBarClearance

    private static let pagePadding = Spacing.pageGutter
    private static let pageSize = 24
    private static let cardSpacing: CGFloat = 16
    /// Posts have no card surface any more, so they need more air between them.
    private static let postSpacing = Spacing.l
    private static let noticeDuration: Duration = .seconds(3)

    private var emptyFeedText: String {
        switch style {
        case .home: "Your feed is waiting for its first look. Post a Fit-Check to get started."
        case .voteQueue: "You’re all caught up. New looks to vote on will show up here."
        }
    }

    @ViewBuilder
    private var header: some View {
        switch style {
        case .home:
            HomeHeader(nickname: appState.profile?.nickname, unreadCount: unreadCount,
                       onSearch: { showSearch = true },
                       onNotifications: { showNotifications = true })
        case .voteQueue:
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Looks waiting on you")
                    .font(Theme.serifGreeting)
                    .foregroundStyle(Theme.mutedForeground)
                EditorialTitle("Cast your", emphasis: "vote")
                    .accessibilityIdentifier("vote.headline")
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }

    var body: some View {
        editorialFeed
        .navigationBarHidden(true)
        .navigationDestination(for: FitCheckRoute.self) { route in routeDestination(route) }
        .navigationDestination(item: $openedRoute) { route in routeDestination(route) }
        .navigationDestination(isPresented: $showFriends) { FriendsView() }
        .navigationDestination(isPresented: $showNotifications) {
            NotificationsView(onUnreadCountChanged: { unreadCount = $0 })
        }
        .sheet(isPresented: $showSearch) { searchSheet }
        .task(id: appState.contentRevision) { await loadUnreadCount() }
        .onChange(of: showNotifications) { _, showing in
            if !showing { Task { await loadUnreadCount() } }
        }
        .revisionTask(appState.homeFeedRevision) {
            if commentRevision != appState.homeFeedRevision {
                await load(refreshGraph: graphRevision != appState.homeFeedRevision)
            }
        }
        .sheet(item: $commentItem) { item in
            CommentThreadSheet(fitCheckId: item.id,
                               photoURLs: PostCardContent.photoURLs(item.fitCheckPhotos).map(\.absoluteString),
                               voterId: appState.userId, canComment: !isExpired(item.expiresAt)) { comments in
                commentRevision = appState.homeFeedRevision
                guard let comments else { return }
                let refs = comments.map { CommentRef(id: $0.id) }
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].fitCheckComments = refs
                    items[index].visibleCommentCount = refs.count
                }
                if let index = visibleItems.firstIndex(where: { $0.id == item.id }) {
                    visibleItems[index].fitCheckComments = refs
                    visibleItems[index].visibleCommentCount = refs.count
                }
            }
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
                onImpression: { logImpression(for: item) },
                onVoteChange: { photoId, total in applyVote(photoId: photoId, total: total, itemID: item.id) }
            )
        } else {
            FitCheckDetailView(fitCheckId: route.id)
        }
    }

    // MARK: - Editorial feed

    private var editorialFeed: some View {
        ScrollView {
            // Posts run edge to edge, so the page padding is applied per
            // section instead of on the whole column.
            VStack(alignment: .leading, spacing: Self.cardSpacing) {
                header.padding(.horizontal, Self.pagePadding)
                if style == .home {
                    FilterChipRow(options: HomeFeedFilters.options(stylePreferences: appState.profile?.stylePreferences ?? []),
                                  selection: $homeFilter, accessibilityLabel: "Feed filters")
                }
                feedList
                olderFitChecksButton.padding(.horizontal, Self.pagePadding)
            }
            .padding(.top, Spacing.s)
            .padding(.bottom, Self.cardSpacing)
        }
        .safeAreaPadding(.bottom, tabBarClearance)
        .background(PaperBackground().ignoresSafeArea())
        .statusBarBackdrop()
        .refreshable {
            await load(refreshGraph: true)
        }
        .onDisappear { flushImpressions() }
    }

    /// Explore, presented over Home. It hides its own navigation bar, so the sheet adds a close button.
    private var searchSheet: some View {
        NavigationStack {
            SearchExploreView()
                .environment(\.tabBarClearance, 0)
                .overlay(alignment: .topTrailing) {
                    FloatingIconButton(systemImage: "xmark", accessibilityLabel: "Close search",
                                       identifier: "search.close") { showSearch = false }
                        .padding(.trailing, Self.pagePadding)
                        .padding(.top, Spacing.s)
                }
        }
    }

    private func loadUnreadCount() async {
        if let count = await Log.attempt("Load unread count", {
            try await API.fetchUnreadNotificationCount(recipientId: appState.userId)
        }) {
            unreadCount = count
        }
    }

    @ViewBuilder
    private var noticeToast: some View {
        if let notice {
            Text(notice)
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.inverseText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .padding(.bottom, tabBarClearance + 12)
                .transition(.opacity)
                .accessibilityIdentifier("feed-notice")
                .onAppear { AccessibilityNotification.Announcement(notice).post() }
        }
    }

    /// Home applies the selected filter chip; the vote queue shows its list as is.
    private var shownItems: [FeedItemDTO] {
        guard style == .home else { return visibleItems }
        return HomeFeedFilters.apply(homeFilter, to: visibleItems, followingIDs: followingIDs)
    }

    private var feedList: some View {
        let shown = shownItems
        return AsyncStateView(isLoading: isLoading, error: error, isEmpty: shown.isEmpty,
                       emptyText: shown.isEmpty && !visibleItems.isEmpty
                           ? "No looks match this filter yet. Try another one."
                           : emptyFeedText,
                       topPadding: 40, hasLoaded: hasLoaded,
                       retry: { await load(refreshGraph: true) }, emptyIcon: "hanger",
                       emptyTitle: "No Fit-Checks yet",
                       emptyActionTitle: "Find friends", emptyAction: { showFriends = true },
                       skeleton: .cards) {
            LazyVStack(spacing: Self.postSpacing) {
                ForEach(shown) { item in
                    HomeFitCard(
                        item: item,
                        viewerId: appState.userId,
                        isLiked: likedIDs.contains(item.id),
                        isFollowing: followingIDs.contains(item.creatorId),
                        showsFollow: item.creatorId != appState.userId,
                        onToggleFollow: { follow in toggleFollow(item.creatorId, follow: follow) },
                        onLike: { like in try await setLiked(like, item: item) },
                        onComment: { commentItem = item },
                        onVoteChange: { photoId, total in applyVote(photoId: photoId, total: total, itemID: item.id) },
                        onPhotoDisplay: {
                            guard !firstPhotoDisplayed, item.id == visibleItems.first?.id else { return }
                            firstPhotoDisplayed = true
                            Log.performance.emitEvent("First home photo displayed")
                        }
                    )
                    .padding(.horizontal, Self.pagePadding)
                    .scrollTransition(.animated(Theme.settle), axis: .vertical) { [reduceMotion] view, phase in
                        view
                            .opacity(reduceMotion || phase.isIdentity ? 1 : 0.6)
                            .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.97)
                    }
                    .onAppear { logImpression(for: item) }
                }
                if FeedInvite.shouldShow(postCount: visibleItems.count, hasLoaded: hasLoaded) {
                    FeedInviteCard { showFriends = true }
                        .padding(.horizontal, Self.pagePadding)
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

    // MARK: - Derived state

    @State private var answered: Set<UUID> = []

    private func rankedItems(_ items: [FeedItemDTO]) -> [FeedItemDTO] {
        let ranked = FeedRanking.visibleItems(
            items: items,
            searchText: "",
            occasion: nil,
            mode: .forYou,
            sort: .forYou,
            stylePreferences: appState.profile?.stylePreferences ?? [],
            signalScores: signalScores
        )
        func varied(_ posts: [FeedItemDTO]) -> [FeedItemDTO] {
            var remaining = posts
            var result: [FeedItemDTO] = []
            while !remaining.isEmpty {
                let index = remaining.firstIndex { $0.creatorId != result.last?.creatorId } ?? 0
                result.append(remaining.remove(at: index))
            }
            return result
        }
        let unanswered = varied(ranked.filter { !answered.contains($0.id) })
        if style == .voteQueue { return unanswered.filter { $0.creatorId != appState.userId } }
        return unanswered + varied(ranked.filter { answered.contains($0.id) })
    }

    private func refreshVisibleItems() {
        visibleItems = rankedItems(items)
    }

    private func setItems(_ newItems: [FeedItemDTO]) {
        items = newItems
        refreshVisibleItems()
    }

    // MARK: - Loading

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

    /// Reloads the first page. The social graph and signal scores are only
    /// refreshed on initial load, pull-to-refresh, and content changes.
    private func load(refreshGraph: Bool) async {
        let interval = Log.performance.beginInterval("Home feed first page", id: Log.performance.makeSignpostID())
        defer { Log.performance.endInterval("Home feed first page", interval) }
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        error = nil
        loadMoreFailed = false
        defer { if loadID == requestID { isLoading = false } }
        do {
            if let page = try await API.fetchHomeFeedPage(limit: Self.pageSize) {
                guard !Task.isCancelled, loadID == requestID else { return }
                answered = page.answeredPosts
                signalScores = page.scores
                updateEngagement(from: page)
                nextCursor = page.nextCursor
                canLoadMore = page.nextCursor != nil
                setItems(page.items)
                hasLoaded = true
                // A later fallback must refresh the legacy social graph.
                graphRevision = nil
                return
            }
            let needsGraph = refreshGraph || graphRevision == nil
            async let freshScores = needsGraph ? fetchSignalScores() : signalScores
            let graph = needsGraph ? try await fetchSocialGraph() : (following: followingIDs, friends: friendIDs)
            let page = try await API.fetchFeedPage(offset: 0, limit: Self.pageSize,
                                                   search: "", occasion: nil,
                                                   followingIDs: nil,
                                                   friendIDs: graph.friends)
            let votes = try? await API.answeredPosts(page.items, viewer: appState.userId)
            let scores = await freshScores
            guard !Task.isCancelled, loadID == requestID else { return }
            if let votes { answered = votes }
            signalScores = scores
            followingIDs = graph.following
            friendIDs = graph.friends
            nextCursor = nil
            nextOffset = page.fetchedCount
            canLoadMore = page.fetchedCount == Self.pageSize
            setItems(page.items)
            hasLoaded = true
            Task { await loadLikedState(for: page.items, requestID: requestID) }
            if needsGraph { refreshSideData() }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            Log.app.error("Feed load failed: \(String(describing: error))")
            if loadID == requestID { self.error = "Couldn’t load this content. Please try again." }
        }
    }

    private func refreshSideData() {
        graphRevision = appState.homeFeedRevision
    }

    private func loadMoreIfNeeded() async {
        guard !isLoading, !isLoadingMore, canLoadMore else { return }
        loadMoreFailed = false
        isLoadingMore = true
        defer { isLoadingMore = false }
        // A reload replaces `items`; a page fetched
        // for the old query must not be appended to the new list.
        let requestID = loadID
        do {
            if let cursor = nextCursor,
               let page = try await API.fetchHomeFeedPage(after: cursor, limit: Self.pageSize) {
                guard !Task.isCancelled, loadID == requestID else { return }
                let existing = Set(items.map(\.id))
                let fresh = page.items.filter { !existing.contains($0.id) }
                answered.formUnion(page.answeredPosts)
                signalScores.merge(page.scores) { _, newer in newer }
                updateEngagement(from: page)
                items.append(contentsOf: fresh)
                visibleItems.append(contentsOf: rankedItems(fresh))
                nextCursor = page.nextCursor
                canLoadMore = page.nextCursor != nil
                return
            }
            let page = try await API.fetchFeedPage(offset: nextOffset, limit: Self.pageSize,
                                                   search: "", occasion: nil,
                                                   followingIDs: nil,
                                                   friendIDs: friendIDs)
            guard loadID == requestID else { return }
            let existing = Set(items.map(\.id))
            let fresh = page.items.filter { !existing.contains($0.id) }
            let votes = try? await API.answeredPosts(fresh, viewer: appState.userId)
            guard loadID == requestID else { return }
            answered.formUnion(votes ?? [])
            items.append(contentsOf: fresh)
            visibleItems.append(contentsOf: rankedItems(fresh))
            Task { await loadLikedState(for: fresh, requestID: requestID) }
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

    private func updateEngagement(from page: API.HomeFeedPage) {
        let authors = Set(page.items.map(\.creatorId)).subtracting(pendingFollowIDs)
        followingIDs.subtract(authors)
        followingIDs.formUnion(page.followedAuthors.intersection(authors))
        let posts = Set(page.items.map(\.id)).subtracting(pendingLikeIDs)
        likedIDs.subtract(posts)
        likedIDs.formUnion(page.likedPosts.intersection(posts))
    }

    /// Likes are best-effort: if the engagement tables are unavailable the feed
    /// still works and every post simply shows as not liked.
    private func loadLikedState(for loaded: [FeedItemDTO], requestID: UUID) async {
        let ids = loaded.map(\.id)
        guard !ids.isEmpty else { return }
        guard let liked = await Log.attempt("Load liked posts", {
            try await API.fetchLikedFitCheckIDs(among: ids, userId: appState.userId)
        }), !Task.isCancelled, loadID == requestID else { return }
        let posts = Set(ids).subtracting(pendingLikeIDs)
        likedIDs.subtract(posts)
        likedIDs.formUnion(liked.intersection(posts))
    }

    /// Throws so `LikeButton` can roll back its optimistic state.
    private func setLiked(_ like: Bool, item: FeedItemDTO) async throws {
        pendingLikeIDs.insert(item.id)
        defer { pendingLikeIDs.remove(item.id) }
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

    private func applyVote(photoId: UUID?, total: Int, itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = items[index]
        item.fitCheckVotes.removeAll { $0.voterId == appState.userId }
        if let photoId {
            answered.insert(itemID)
            item.fitCheckVotes.append(VoteRef(photoId: photoId, voterId: appState.userId))
        } else {
            answered.remove(itemID)
        }
        item.voteCount = total
        items[index] = item
        if let index = visibleItems.firstIndex(where: { $0.id == itemID }) { visibleItems[index] = item }
    }

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
