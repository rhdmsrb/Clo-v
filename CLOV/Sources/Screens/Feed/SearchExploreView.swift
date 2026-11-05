import SwiftUI

/// Search is a first-class destination so people can move from inspiration to
/// a specific creator, occasion or fit-check without leaving the main loop.
struct SearchExploreView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var occasion: String?
    @State private var results: [FeedItemDTO] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var recents = RecentSearches()
    @FocusState private var isSearchFocused: Bool
    @Environment(\.isTabActive) private var isTabActive

    private static let pagePadding: CGFloat = 20
    private static let recentStore = RecentSearchStore()
    /// Shown until the user has searches of their own.
    private static let suggestions = ["Wedding guest", "Interview", "Date night", "Brunch", "Travel fit", "Streetwear"]
    private let occasions = ["Everyday", "Work", "Date", "Party", "Travel", "Wedding"]
    private var requestKey: String { "\(query.trimmingCharacters(in: .whitespacesAndNewlines))|\(occasion ?? "")" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("STYLE, IN YOUR WORDS")
                        .font(Theme.micro).tracking(1.4)
                        .foregroundStyle(Theme.accentDeep)
                    Text("Find your next look")
                        .font(Theme.displayFont).foregroundStyle(Theme.ink)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .accessibilityAddTraits(.isHeader)
                }
                HStack(spacing: 11) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedForeground)
                        .accessibilityHidden(true)
                    TextField("Try ‘wedding guest’ or a creator", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($isSearchFocused)
                        .onSubmit { record(query) }
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

                VStack(alignment: .leading, spacing: 11) {
                    Text("BROWSE BY OCCASION")
                        .font(Theme.micro).tracking(1.1)
                        .foregroundStyle(Theme.mutedForeground)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            occasionChip("All", value: nil)
                            ForEach(occasions, id: \.self) { value in occasionChip(value, value: value) }
                        }
                    }
                    // Run the row edge to edge so chips scroll off the screen
                    // edge instead of being sliced at the page padding.
                    .contentMargins(.horizontal, Self.pagePadding, for: .scrollContent)
                    .padding(.horizontal, -Self.pagePadding)
                }

                searchSuggestions

                HStack(alignment: .firstTextBaseline) {
                    Text(query.isEmpty ? "Looks to explore" : "Search results")
                        .font(Theme.title).foregroundStyle(Theme.ink)
                    Spacer()
                    if hasLoaded && !results.isEmpty {
                        Text("\(results.count) looks").font(Theme.caption).foregroundStyle(Theme.mutedForeground)
                    }
                }

                AsyncStateView(isLoading: isLoading, error: error,
                               isEmpty: results.isEmpty,
                               emptyText: hasLoaded && error == nil
                                ? "No looks found. Try another search or occasion."
                                : "No looks to explore yet. Check back when your circle starts posting.",
                               topPadding: 28, hasLoaded: hasLoaded, retry: { await load() }) {
                    LazyVStack(spacing: 16) {
                        ForEach(results) { item in
                            FitCheckCardView(item: item, voterId: appState.userId)
                        }
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
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            await load()
        }
        .task { recents = Self.recentStore.load(for: appState.userId) }
        .refreshable { await load() }
        .navigationDestination(for: FitCheckRoute.self) { route in
            FitCheckDetailView(fitCheckId: route.id)
        }
    }

    // MARK: - Recent searches and suggestions

    /// Recent searches when there are any, otherwise a few ideas to try. Hidden
    /// once the user starts typing, so it never competes with live results.
    @ViewBuilder
    private var searchSuggestions: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                    Button("Clear") { clearRecents() }
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
                            Button("Remove", systemImage: "xmark", role: .destructive) { removeRecent(term) }
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

    private func removeRecent(_ term: String) {
        update(recents.removing(term))
    }

    private func clearRecents() {
        update(recents.cleared())
    }

    private func update(_ updated: RecentSearches) {
        recents = updated
        Self.recentStore.save(updated, for: appState.userId)
    }

    private func occasionChip(_ title: String, value: String?) -> some View {
        ChipToggle(label: title, selected: occasion == value) { occasion = value }
    }

    @MainActor
    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let page = try await API.fetchFeedPage(
                offset: 0,
                limit: 30,
                search: query.trimmingCharacters(in: .whitespacesAndNewlines),
                occasion: occasion,
                followingIDs: nil,
                friendIDs: await Log.attempt("Load friend IDs") { try await API.fetchFriendIDs(userId: appState.userId) } ?? []
            )
            results = page.items
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load search results. Please try again."
        }
    }
}
