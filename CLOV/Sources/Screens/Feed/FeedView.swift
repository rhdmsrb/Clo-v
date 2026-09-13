import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var appState: AppState

    @State private var items: [FeedItemDTO] = []
    @State private var sort: SortOption = .newest
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var unreadCount = 0

    private enum SortOption { case newest, votes }

    private var sortedItems: [FeedItemDTO] {
        switch sort {
        case .newest: return items.sorted { $0.createdAt > $1.createdAt }
        case .votes: return items.sorted { $0.fitCheckVotes.count > $1.fitCheckVotes.count }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TODAY'S EDIT")
                            .font(.system(.caption2, design: .default).weight(.black))
                            .foregroundStyle(Theme.accent)
                            .tracking(1.5)
                        Text("Fit Checks")
                            .font(.system(size: 42, weight: .black, design: .default))
                    }
                    Spacer()
                    NavigationLink {
                        NotificationsView(onRead: { unreadCount = 0 })
                    } label: {
                        bellIcon
                    }
                }

                HStack(spacing: 8) {
                    sortChip("Newest", .newest)
                    sortChip("Most Voted", .votes)
                }

                AsyncStateView(isLoading: isLoading, error: error, isEmpty: sortedItems.isEmpty,
                               emptyText: "No Fit-Checks yet — be the first to post one.", topPadding: 40, hasLoaded: hasLoaded, retry: { await load() }) {
                    VStack(spacing: 20) {
                        ForEach(sortedItems) { item in
                            FitCheckCardView(item: item, voterId: appState.userId)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationBarHidden(true)
        .navigationDestination(for: FitCheckRoute.self) { route in
            FitCheckDetailView(fitCheckId: route.id)
        }
        .refreshable { await load() }
        .task(id: appState.contentRevision) { await load() }
    }

    private var bellIcon: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 40, height: 40)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.line.opacity(0.25), lineWidth: 1))
            if unreadCount > 0 {
                Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accentForeground)
                    .padding(4)
                    .background(Theme.accent)
                    .clipShape(Circle())
                    .offset(x: 4, y: -4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unreadCount > 0 ? "Notifications, \(unreadCount) unread" : "Notifications")
    }

    @ViewBuilder
    private func sortChip(_ label: String, _ option: SortOption) -> some View {
        Button {
            withAnimation(Theme.press) { sort = option }
        } label: {
            Text(label)
                .font(.system(.footnote, design: .default).weight(.bold))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(sort == option ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.card))
                .foregroundStyle(sort == option ? Theme.inverseText : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.line.opacity(sort == option ? 0 : 0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: sort == option)
    }

    private func loadUnreadCount() async {
        // A badge failure must not hide an otherwise usable feed.
        if let count = try? await API.fetchUnreadNotificationCount(recipientId: appState.userId) {
            unreadCount = count
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let feedTask = API.fetchFeed()
            async let countTask: Void = loadUnreadCount()
            items = try await feedTask
            hasLoaded = true
            await countTask
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load this content. Please try again."
        }
    }
}
