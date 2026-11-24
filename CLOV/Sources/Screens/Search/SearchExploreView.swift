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
    @State private var recents = RecentSearches()
    @FocusState private var isSearchFocused: Bool
    @Environment(\.isTabActive) private var isTabActive

    private static let pagePadding: CGFloat = 20
    private static let gridColumns = 3
    private static let gridSpacing: CGFloat = 12
    private static let pageSize = 30
    private static let recentStore = RecentSearchStore()
    /// Shown until the user has searches of their own.
    private static let suggestions = ["Wedding guest", "Interview", "Date night", "Brunch", "Travel fit", "Streetwear"]
    private static let prefetchTileCount = 6
    private static let searchDebounce: Duration = .milliseconds(300)
    private var searchTerm: String { SearchTerm.sanitized(query) }
    private var requestKey: String { "\(searchTerm)|\(filter.occasion ?? "")" }
    /// The search or a filter is narrowing the results.
    private var isNarrowed: Bool { !searchTerm.isEmpty || !filter.isDefault }
    private var isEmptyResult: Bool { displayed.isEmpty && !canLoadMore }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.m) {
                Text("Explore")
                    .font(Theme.font(.title2, weight: .bold)).foregroundStyle(Theme.ink)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 10) {
                    searchField
                    filtersButton
                }
                searchSuggestions
                ExploreQuickFilters(filter: filter, onChange: applyFilter)
                    .padding(.horizontal, -Self.pagePadding)
                Divider()
                // A narrowed search that finds nothing gets its own empty state (below);
                // this one is only for an Explore with nothing posted at all.
                AsyncStateView(isLoading: isLoading, error: error,
                               isEmpty: isEmptyResult && !isNarrowed,
                               emptyText: "No looks to explore yet. Check back when your circle starts posting.",
                               topPadding: 28, hasLoaded: hasLoaded, retry: { await load() }) {
                    if let relationshipsNotice { relationshipsBanner(relationshipsNotice) }
                    if isEmptyResult {
                        SearchNoResultsView(term: searchTerm, activeFilterCount: filter.activeCount,
                                            ideas: Self.suggestions, onSearch: applySearch,
                                            onClearFilters: { applyFilter(ExploreFilter()) })
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gridSpacing), count: Self.gridColumns),
                              spacing: Spacing.l) {
                        ForEach(displayed) { item in
                            Button { openedRoute = FitCheckRoute(id: item.id, photoIndex: nil) } label: {
                                VStack(alignment: .leading, spacing: Spacing.xs + 2) {
                                    tile(item)
                                        .aspectRatio(3 / 4, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
                                    tileFooter(item)
                                }
                            }
                            .buttonStyle(InstantPressStyle())
                            .onAppear { prefetchIfNeeded(after: item) }
                        }
                    }
                }
                loadMoreFooter
            }
            .padding(Self.pagePadding)
        }
        .clearsTabBar()
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.card)
        .statusBarBackdrop(Theme.card)
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
        .task { recents = Self.recentStore.load(for: appState.userId) }
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
                .onSubmit { record(query) }
                .accessibilityIdentifier("search.query")
            if !query.isEmpty {
                Button { query = ""; isSearchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.mutedForeground)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.accessibilityLabel("Clear search")
            }
        }
        .font(Theme.body)
        .padding(.horizontal, 15).frame(minHeight: Theme.minTapSize + 4)
        .background(Theme.muted, in: Capsule(style: .continuous))
    }

    // MARK: - Recent searches and suggestions

    /// Recent searches (or a few ideas to try) while the field is focused and
    /// empty. Hidden once the user types, so it never competes with results.
    @ViewBuilder
    private var searchSuggestions: some View {
        if isSearchFocused, searchTerm.isEmpty {
            if recents.terms.isEmpty {
                suggestionGroup(title: "TRY SEARCHING", terms: Self.suggestions, icon: "magnifyingglass", isRecent: false)
            } else {
                suggestionGroup(title: "RECENT", terms: recents.terms, icon: "clock.arrow.circlepath", isRecent: true)
            }
        }
    }

    private func suggestionGroup(title: String, terms: [String], icon: String, isRecent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(Theme.micro).tracking(1.1)
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if isRecent {
                    Button("Clear") { update(recents.cleared()) }
                        .font(Theme.label)
                        .foregroundStyle(Theme.accentDeep)
                        .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Clear recent searches")
                        .accessibilityIdentifier("search.clearRecents")
                }
            }
            FlowLayout(spacing: 8) {
                ForEach(terms, id: \.self) { term in
                    Button { applySearch(term) } label: {
                        Label(term, systemImage: icon)
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: false, font: Theme.label, horizontalPadding: 14))
                    .contextMenu {
                        if isRecent {
                            Button("Remove", systemImage: "xmark", role: .destructive) { update(recents.removing(term)) }
                        }
                    }
                    .accessibilityIdentifier("\(isRecent ? "recent" : "suggestion")_\(term)")
                }
            }
        }
    }

    private func applySearch(_ term: String) {
        query = term
        isSearchFocused = false
        record(term)
    }

    private func record(_ term: String) {
        update(recents.adding(term))
    }

    private func update(_ updated: RecentSearches) {
        recents = updated
        Self.recentStore.save(updated, for: appState.userId)
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
                    CachedImage(url: url, size: .thumbnail) { phase in
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
            .accessibilityValue(tileAccessibilityValue(item))
            .accessibilityHint("Opens the Fit-Check to vote")
            .accessibilityIdentifier("explore-tile")
    }

    /// Author under the tile, like a label under a product shot, with the like count
    /// when there is one. Sized and inked to stay readable under the photo.
    private func tileFooter(_ item: FeedItemDTO) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(item.profiles?.nickname ?? "someone")
                .font(Theme.font(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let likes = PostCardContent.displayLikeCount(item.likeCount) {
                Label("\(likes)", systemImage: "heart")
                    .labelStyle(CompactLabelStyle())
                    .font(Theme.font(.footnote, weight: .medium))
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .accessibilityHidden(true)
    }

    private func tileAccessibilityValue(_ item: FeedItemDTO) -> String {
        let author = "by \(item.profiles?.nickname ?? "someone")"
        guard let likes = PostCardContent.displayLikeCount(item.likeCount) else { return author }
        return "\(author), \(likes) \(likes == 1 ? "like" : "likes")"
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
        defer { if token == generation { isLoading = false } }
        await ensureRelationships(force: refreshRelationships)
        guard !Task.isCancelled else { return }
        do {
            let page = try await API.fetchFeedPage(
                offset: 0, limit: Self.pageSize, search: searchTerm,
                occasion: filter.occasion, followingIDs: nil, friendIDs: friendIDs
            )
            guard token == generation, !Task.isCancelled else { return }
            setResults(page.items)
            nextOffset = page.fetchedCount
            canLoadMore = page.fetchedCount >= Self.pageSize
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            guard token == generation, !Task.isCancelled else { return }
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
