import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState
    let onRead: () -> Void

    @State private var notifications: [NotificationDTO] = []
    @State private var incomingRequestCount = 0
    @State private var filter: ActivityFilter = .all
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?

    private var unreadCount: Int { notifications.filter { !$0.isRead }.count }
    private var hasUnread: Bool { unreadCount > 0 }

    private var filteredNotifications: [NotificationDTO] {
        notifications.filter { notification in
            switch filter {
            case .all: true
            case .unread: !notification.isRead
            case .fitChecks: notification.fitCheckId != nil
            case .friends: notification.type.hasPrefix("friend_")
            }
        }
    }

    private var groupedNotifications: [(String, [NotificationDTO])] {
        let groups = Dictionary(grouping: filteredNotifications) { sectionTitle(for: $0.createdAt) }
        return ["TODAY", "THIS WEEK", "EARLIER"].compactMap { title in
            groups[title].map { (title, $0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader
                friendRequestsShortcut
                filterBar

                if hasLoaded && filteredNotifications.isEmpty {
                    emptyFilteredState
                } else if isLoading && notifications.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if let error, notifications.isEmpty {
                    VStack(spacing: 12) {
                        Text(error).font(.subheadline).foregroundStyle(Theme.mutedForeground)
                        Button("Try again") { Task { await load() } }.buttonStyle(OutlineButtonStyle())
                    }.frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    ForEach(groupedNotifications, id: \.0) { title, items in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(title)
                                .font(.system(.caption2, design: .default).weight(.black))
                                .tracking(1.2)
                                .foregroundStyle(Theme.mutedForeground)
                                .padding(.top, 2)
                            ForEach(items) { notification in row(for: notification) }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasUnread {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all read") { Task { await markAllRead() } }
                        .font(.system(size: 13, weight: .bold))
                }
            }
        }
        // FitCheckRoute is registered by the parent tab's NavigationStack.
        .task { await load() }
        .refreshable { await load() }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Activity")
                .font(Theme.editorialFont(size: 34))
                .foregroundStyle(Theme.ink)
            Text("YOUR CIRCLE")
                .font(.system(.caption2, design: .default).weight(.black))
                .tracking(1.4)
                .foregroundStyle(Theme.accent)
            Text(hasUnread ? "\(unreadCount) new update\(unreadCount == 1 ? "" : "s")" : "Votes, comments, and friend updates in one place.")
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(Theme.mutedForeground)
        }
    }

    private var friendRequestsShortcut: some View {
        NavigationLink {
            FriendsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .background(Theme.accent.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Friend requests")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(incomingRequestCount == 0 ? "Find and manage your circle" : "\(incomingRequestCount) waiting for your reply")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedForeground)
                }
                Spacer()
                if incomingRequestCount > 0 {
                    Text("\(incomingRequestCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.inverseText)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(Theme.ink, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(13)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityFilter.allCases) { option in
                    ChipToggle(label: option.title, selected: filter == option) { filter = option }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyFilteredState: some View {
        VStack(spacing: 10) {
            Image(systemName: filter == .unread ? "checkmark.circle" : "bell")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.accent)
            Text(emptyText)
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }

    private var emptyText: String {
        if !notifications.isEmpty { return filter == .unread ? "You’re all caught up." : "No updates in this category yet." }
        return "Nothing yet — votes, comments, and friend updates will show up here."
    }

    @ViewBuilder
    private func row(for notification: NotificationDTO) -> some View {
        HStack(spacing: 10) {
            Group {
                if let fitCheckId = notification.fitCheckId {
                    NavigationLink(value: FitCheckRoute(id: fitCheckId)) { notificationContent(notification) }
                        .buttonStyle(.plain)
                } else if notification.type == "friend_request" {
                    NavigationLink { FriendsView() } label: { notificationContent(notification) }
                        .buttonStyle(.plain)
                } else {
                    notificationContent(notification)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !notification.isRead {
                Button { Task { await markRead(notification) } } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark update read")
            }
        }
        .padding(12)
        .background(notification.isRead ? Theme.card : Theme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line.opacity(0.08), lineWidth: 1))
    }

    private func notificationContent(_ notification: NotificationDTO) -> some View {
        HStack(alignment: .top, spacing: 11) {
            AvatarView(url: notification.actor?.avatarUrl, nickname: notification.actor?.nickname, size: 40)
            VStack(alignment: .leading, spacing: 5) {
                (Text(notification.actor?.nickname ?? "Someone").fontWeight(.semibold)
                    + Text(" \(notificationText(for: notification.type))"))
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                Text(notification.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
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

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "TODAY" }
        if let week = calendar.dateInterval(of: .weekOfYear, for: Date()), week.contains(date) { return "THIS WEEK" }
        return "EARLIER"
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        async let notificationTask = API.fetchNotifications(recipientId: appState.userId)
        async let requestTask = API.fetchFriendRequests(userId: appState.userId, incoming: true)
        do {
            notifications = try await notificationTask
            do { incomingRequestCount = try await requestTask.count } catch {
                Log.app.error("Load friend requests failed: \(error.localizedDescription)")
                incomingRequestCount = 0
            }
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load activity. Pull to refresh and try again."
            hasLoaded = true
        }
    }

    private func markRead(_ notification: NotificationDTO) async {
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }), !notifications[index].isRead else { return }
        notifications[index].isRead = true
        do {
            try await API.markNotificationRead(id: notification.id, recipientId: appState.userId)
            onRead()
        } catch {
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) { notifications[index].isRead = false }
            self.error = "Couldn’t update this activity. Please try again."
        }
    }

    private func markAllRead() async {
        do {
            try await API.markAllNotificationsRead(recipientId: appState.userId)
            notifications = notifications.map { notification in
                var result = notification
                result.isRead = true
                return result
            }
            onRead()
        } catch {
            self.error = "Couldn’t update activity. Please try again."
        }
    }
}

private enum ActivityFilter: String, CaseIterable, Identifiable {
    case all, unread, fitChecks, friends
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        case .fitChecks: "Fit-Checks"
        case .friends: "Friends"
        }
    }
}
