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
    @FocusState private var isSearchFocused: Bool
    @Environment(\.isTabActive) private var isTabActive

    private static let pagePadding: CGFloat = 20
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
        .refreshable { await load() }
        .navigationDestination(for: FitCheckRoute.self) { route in
            FitCheckDetailView(fitCheckId: route.id)
        }
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
