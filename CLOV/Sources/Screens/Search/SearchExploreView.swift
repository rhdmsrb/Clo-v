import SwiftUI

/// Explore: search fit-checks, refine with Filters, browse a two-column grid.
/// Tapping a tile opens the vote screen.
struct SearchExploreView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var filter = ExploreFilter()
    @State private var results: [FeedItemDTO] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var showFilters = false
    @State private var followingIDs: Set<UUID> = []
    @State private var openedRoute: FitCheckRoute?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.isTabActive) private var isTabActive

    private static let pagePadding: CGFloat = 20
    private static let pageSize = 30
    private static let searchDebounce: Duration = .milliseconds(300)
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var requestKey: String { "\(trimmedQuery)|\(filter.occasion ?? "")" }
    private var displayed: [FeedItemDTO] { filter.apply(to: results) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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
                    let ratios = Dictionary(uniqueKeysWithValues: displayed.enumerated().map {
                        ($1.id, ExploreTileRatio.ratio(forIndex: $0))
                    })
                    MasonryGrid(items: displayed, aspectRatio: { ratios[$0.id] ?? ExploreTileRatio.ratio(forIndex: 0) },
                                onTap: { openedRoute = FitCheckRoute(id: $0.id, photoIndex: nil) }) { item in
                        tile(item)
                    }
                }
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
        .refreshable { await load() }
        .sheet(isPresented: $showFilters) {
            ExploreFiltersSheet(initial: filter, availableTags: ExploreFilter.availableTags(in: results)) { filter = $0 }
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
            TextField("Search fit-checks, tags, people", text: $query)
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
            Image(systemName: filter.isDefault
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.title2)
                .foregroundStyle(filter.isDefault ? Theme.ink : Theme.accentDeep)
                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel("Filters")
        .accessibilityValue(filter.isDefault ? "None applied" : "\(filter.activeCount) applied")
        .accessibilityIdentifier("explore.filters")
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

    @MainActor
    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let page = try await API.fetchFeedPage(
                offset: 0,
                limit: Self.pageSize,
                search: trimmedQuery,
                occasion: filter.occasion,
                followingIDs: nil,
                friendIDs: await Log.attempt("Load friend IDs") { try await API.fetchFriendIDs(userId: appState.userId) } ?? []
            )
            results = page.items
            followingIDs = await Log.attempt("Load following IDs") { try await API.fetchFollowingIDs(userId: appState.userId) } ?? followingIDs
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load search results. Please try again."
        }
    }
}
