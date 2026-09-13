import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState
    let onRead: () -> Void

    @State private var notifications: [NotificationDTO] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?

    private var hasUnread: Bool { notifications.contains { !$0.isRead } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncStateView(isLoading: isLoading, error: error, isEmpty: notifications.isEmpty,
                               emptyText: "Nothing yet — you'll see it here when someone votes or comments on your Fit-Checks.",
                               topPadding: 60, hasLoaded: hasLoaded, retry: { await load() }) {
                    VStack(spacing: 8) {
                        ForEach(notifications) { n in
                            if let fitCheckId = n.fitCheckId {
                                NavigationLink(value: FitCheckRoute(id: fitCheckId)) {
                                    row(for: n)
                                }
                                .buttonStyle(.plain)
                            } else {
                                row(for: n)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasUnread {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all read") { Task { await markAllRead() } }
                        .font(.system(size: 13, weight: .bold))
                }
            }
        }
        // No .navigationDestination(for: FitCheckRoute.self) here — this
        // view is always pushed inside FeedView's NavigationStack, which
        // already declares one mapping FitCheckRoute -> FitCheckDetailView;
        // adding a second one for the same type in the same stack is
        // redundant (and SwiftUI logs a warning for it).
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func row(for n: NotificationDTO) -> some View {
        HStack(spacing: 12) {
            AvatarView(url: n.actor?.avatarUrl, nickname: n.actor?.nickname, size: 36)

            Text("\(n.actor?.nickname ?? "Someone") \(notificationText(for: n.type))")
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !n.isRead {
                Circle().fill(Theme.accent).frame(width: 8, height: 8)
            }
        }
        .padding(14)
        .background(n.isRead ? Theme.card : Theme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Theme.cardShadow, radius: 8, y: 3)
    }

    private func notificationText(for type: String) -> String {
        switch type {
        case "vote": return "voted on your Fit-Check"
        case "comment": return "commented on your Fit-Check"
        case "friend_request": return "sent you a friend request"
        case "friend_accepted": return "accepted your friend request"
        default: return "interacted with you"
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            notifications = try await API.fetchNotifications(recipientId: appState.userId)
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load this content. Please try again."
        }
    }

    private func markAllRead() async {
        do {
            try await API.markAllNotificationsRead(recipientId: appState.userId)
            onRead()
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
