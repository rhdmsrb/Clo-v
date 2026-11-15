import SwiftUI

/// Explore: search fit-checks, refine with Filters, browse a two-column grid.
/// Tapping a tile opens the vote screen.
struct SearchExploreView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var filter = ExploreFilter()
    @State private var results: [FeedItemDTO] = []
    /// `results` with the filter applied; recomputed only when either changes.
    @State private var displayed: [FeedItemDTO] = []
    @State private var nextOffset = 0
    @State private var canLoadMore = false
    @State private var isLoadingMore = false
    @State private var loadMoreError: String?
    /// Bumped on every fresh load so stale page responses are discarded.
    @State private var generation = 0
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var showFilters = false
    @State private var followingIDs: Set<UUID> = []
    @State private var friendIDs: Set<UUID> = []
    /// Friend/following IDs are fetched once per view lifetime (and on pull-to-refresh).
    @State private var hasLoadedRelationships = false
    @State private var relationshipsNotice: String?
    @State private var openedRoute: FitCheckRoute?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.isTabActive) private var isTabActive

    private static let pagePadding: CGFloat = 20
    private static let pageSize = 30
    private static let prefetchTileCount = 6
    private static let searchDebounce: Duration = .milliseconds(300)
    private var searchTerm: String { SearchTerm.sanitized(query) }
    private var requestKey: String { "\(searchTerm)|\(filter.occasion ?? "")" }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("Explore")
                    .font(Theme.displayFont).foregroundStyle(Theme.ink)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 10) {
                    searchField
                    filtersButton
                }
                AsyncStateView(isLoading: isLoading, error: error,
                               isEmpty: results.isEmpty,
                               emptyText: hasLoaded && error == nil
                                ? "No looks found. Try another search or filter."
                                : "No looks to explore yet. Check back when your circle starts posting.",
                               topPadding: 28, hasLoaded: hasLoaded, retry: { await load() }) {
                    if let relationshipsNotice { relationshipsBanner(relationshipsNotice) }
                    MasonryGrid(items: displayed, aspectRatio: { ExploreTileRatio.ratio(for: $0.id) },
                                onTap: { openedRoute = FitCheckRoute(id: $0.id, photoIndex: nil) }) { item in
                        tile(item)
                            .onAppear { prefetchIfNeeded(after: item) }
                    }
                }
                loadMoreFooter
            }
            .padding(Self.pagePadding)
            .padding(.bottom, 90)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .statusBarBackdrop()
        .navigationBarHidden(true)
        .onChange(of: isTabActive) { _, active in
            if !active { isSearchFocused = false }
        }
        .task(id: requestKey) {
            if hasLoaded {
                try? await Task.sleep(for: Self.searchDebounce)
                guard !Task.isCancelled else { return }
            }
            await load()
        }
        .refreshable { await load(refreshRelationships: true) }
        .sheet(isPresented: $showFilters) {
            ExploreFiltersSheet(initial: filter, availableTags: ExploreFilter.availableTags(in: results)) { applyFilter($0) }
        }
        .navigationDestination(for: FitCheckRoute.self) { route in routeDestination(route) }
        .navigationDestination(item: $openedRoute) { route in routeDestination(route) }
    }

    @ViewBuilder
    private func routeDestination(_ route: FitCheckRoute) -> some View {
        if let item = results.first(where: { $0.id == route.id }) {
            FitCheckReelView(
                item: item,
                voterId: appState.userId,
                isFollowing: followingIDs.contains(item.creatorId),
                initialPhotoIndex: route.photoIndex,
                onToggleFollow: { setFollowing($0, creatorId: item.creatorId) }
            )
        } else {
            FitCheckDetailView(fitCheckId: route.id)
        }
    }

    /// Optimistic; reverted if the server rejects it.
    private func setFollowing(_ follow: Bool, creatorId: UUID) {
        followingIDs = follow ? followingIDs.union([creatorId]) : followingIDs.subtracting([creatorId])
        Task {
            do {
                try await API.setFollowing(follow, followerId: appState.userId, followingId: creatorId)
            } catch {
                Log.app.error("Explore follow toggle failed: \(error.localizedDescription)")
                followingIDs = follow ? followingIDs.subtracting([creatorId]) : followingIDs.union([creatorId])
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedForeground)
                .accessibilityHidden(true)
            TextField("Search fit-checks", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .accessibilityIdentifier("search.query")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.mutedForeground)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.accessibilityLabel("Clear search")
            }
        }
        .font(Theme.body)
        .padding(.horizontal, 15).frame(minHeight: 52)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
    }

    private var filtersButton: some View {
        Button { showFilters = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease")
                    .accessibilityHidden(true)
                Text("Filters").lineLimit(1)
                if !filter.isDefault {
                    Text("\(filter.activeCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.background)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Theme.accentDeep, in: Circle())
                        .accessibilityHidden(true)
                }
            }
            .font(Theme.body)
            .foregroundStyle(filter.isDefault ? Theme.ink : Theme.accentDeep)
            .padding(.horizontal, 16)
            .frame(minHeight: Theme.minTapSize)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().stroke(filter.isDefault ? Theme.controlBorder : Theme.accentDeep, lineWidth: 1))
            .contentShape(Capsule())
        }
        .fixedSize(horizontal: true, vertical: false)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel("Filters")
        .accessibilityValue(filter.isDefault ? "None applied" : "\(filter.activeCount) applied")
        .accessibilityIdentifier("explore.filters")
    }

    private func relationshipsBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text(text).font(Theme.body).foregroundStyle(Theme.mutedForeground)
            Spacer(minLength: 0)
            Button("Retry") { Task { await load(refreshRelationships: true) } }
                .font(Theme.body.weight(.semibold))
                .frame(minHeight: Theme.minTapSize)
        }
        .accessibilityIdentifier("explore.relationships-notice")
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        if hasLoaded, let loadMoreError {
            HStack(spacing: 10) {
                Text(loadMoreError).font(Theme.body).foregroundStyle(Theme.mutedForeground)
                Spacer(minLength: 0)
                Button("Retry") { Task { await loadMore() } }
                    .font(Theme.body.weight(.semibold))
                    .frame(minHeight: Theme.minTapSize)
            }
        } else if hasLoaded, canLoadMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityLabel("Loading more looks")
                .task(id: nextOffset) { await loadMore() }
        }
    }

    private func tile(_ item: FeedItemDTO) -> some View {
        let url = PostCardContent.photoURLs(item.fitCheckPhotos).first
        return Color.clear
            .overlay {
                if let url {
                    CachedImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        case .loading: Theme.muted.overlay(ProgressView())
                        case .failure: Theme.muted.overlay(Image(systemName: "photo").foregroundStyle(Theme.mutedForeground))
                        }
                    }
                } else {
                    Theme.muted
                }
            }
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(PostCardContent.title(votePrompt: item.votePrompt, occasion: item.occasion))
            .accessibilityValue("by \(item.profiles?.nickname ?? "someone")")
            .accessibilityHint("Opens the Fit-Check to vote")
            .accessibilityIdentifier("explore-tile")
    }

    private func applyFilter(_ newFilter: ExploreFilter) {
        filter = newFilter
        displayed = newFilter.apply(to: results)
    }

    private func setResults(_ items: [FeedItemDTO]) {
        results = items
        displayed = filter.apply(to: items)
    }

    private func prefetchIfNeeded(after item: FeedItemDTO) {
        guard canLoadMore, !isLoadingMore, loadMoreError == nil,
              displayed.suffix(Self.prefetchTileCount).contains(where: { $0.id == item.id }) else { return }
        Task { await loadMore() }
    }

    /// Fetches friend/following IDs once; on failure keeps the previous IDs,
    /// logs, and shows an inline notice so the user knows results may be public-only.
    @MainActor
    private func ensureRelationships(force: Bool) async {
        guard force || !hasLoadedRelationships else { return }
        do {
            friendIDs = try await API.fetchFriendIDs(userId: appState.userId)
            followingIDs = try await API.fetchFollowingIDs(userId: appState.userId)
            hasLoadedRelationships = true
            relationshipsNotice = nil
        } catch is CancellationError {
            return
        } catch {
            Log.app.error("Explore relationship lookup failed: \(error.localizedDescription)")
            relationshipsNotice = "Couldn’t load your friends’ looks. Showing what we have."
        }
    }

    @MainActor
    private func load(refreshRelationships: Bool = false) async {
        isLoading = true
        error = nil
        loadMoreError = nil
        generation += 1
        let token = generation
        defer { isLoading = false }
        await ensureRelationships(force: refreshRelationships)
        guard !Task.isCancelled else { return }
        do {
            let page = try await API.fetchFeedPage(
                offset: 0, limit: Self.pageSize, search: searchTerm,
                occasion: filter.occasion, followingIDs: nil, friendIDs: friendIDs
            )
            guard token == generation else { return }
            setResults(page.items)
            nextOffset = page.fetchedCount
            canLoadMore = page.fetchedCount >= Self.pageSize
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load search results. Please try again."
        }
    }

    @MainActor
    private func loadMore() async {
        guard hasLoaded, canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreError = nil
        let token = generation
        defer { isLoadingMore = false }
        do {
            let page = try await API.fetchFeedPage(
                offset: nextOffset, limit: Self.pageSize, search: searchTerm,
                occasion: filter.occasion, followingIDs: nil, friendIDs: friendIDs
            )
            guard token == generation else { return }
            let known = Set(results.map(\.id))
            setResults(results + page.items.filter { !known.contains($0.id) })
            nextOffset += page.fetchedCount
            canLoadMore = page.fetchedCount >= Self.pageSize
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            Log.app.error("Explore load more failed: \(error.localizedDescription)")
            loadMoreError = "Couldn’t load more looks."
        }
    }
}
