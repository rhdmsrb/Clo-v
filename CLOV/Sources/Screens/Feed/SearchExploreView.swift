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

    private let occasions = ["Everyday", "Work", "Date", "Party", "Travel", "Wedding"]
    private var requestKey: String { "\(query.trimmingCharacters(in: .whitespacesAndNewlines))|\(occasion ?? "")" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("STYLE, IN YOUR WORDS")
                        .font(.system(.caption2, design: .default).weight(.bold)).tracking(1.4)
                        .foregroundStyle(Theme.accent)
                    Text("Find your next look")
                        .font(Theme.editorialFont(size: 34)).foregroundStyle(Theme.ink)
                }
                HStack(spacing: 11) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedForeground)
                    TextField("Try ‘wedding guest’ or a creator", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityIdentifier("search.query")
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.mutedForeground)
                        }.accessibilityLabel("Clear search")
                    }
                }
                .font(.system(size: 15))
                .padding(.horizontal, 15).frame(height: 52)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Theme.line.opacity(0.12), lineWidth: 1))

                VStack(alignment: .leading, spacing: 11) {
                    Text("BROWSE BY OCCASION")
                        .font(.system(.caption2, design: .default).weight(.bold)).tracking(1.1)
                        .foregroundStyle(Theme.mutedForeground)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            occasionChip("All", value: nil)
                            ForEach(occasions, id: \.self) { value in occasionChip(value, value: value) }
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(query.isEmpty ? "Looks to explore" : "Search results")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    if hasLoaded && !results.isEmpty {
                        Text("\(results.count) looks").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                    }
                }

                AsyncStateView(isLoading: isLoading, error: error,
                               isEmpty: results.isEmpty,
                               emptyText: hasLoaded && error == nil
                                ? "No looks found. Try another search or occasion."
                                : "No looks to explore yet. Check back when your circle starts posting.",
                               topPadding: 28, hasLoaded: hasLoaded, retry: { await load() }) {
                    LazyVStack(spacing: 14) {
                        ForEach(results) { item in
                            FitCheckCardView(item: item, voterId: appState.userId)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 90)
        }
        .background(Theme.background)
        .navigationBarHidden(true)
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
        let selected = occasion == value
        return Button { occasion = value } label: {
            Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.inverseText : Theme.ink)
                .padding(.horizontal, 15).padding(.vertical, 9)
                .background(selected ? Theme.ink : Theme.card, in: Capsule())
                .overlay(Capsule().stroke(selected ? .clear : Theme.line.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
                friendIDs: (try? await API.fetchFriendIDs(userId: appState.userId)) ?? []
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
