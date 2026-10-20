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

    @ScaledMetric(relativeTo: .body) private var iconButtonSize: CGFloat = 42
    private static let minTapSize: CGFloat = 44

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

    private var groupedNotifications: [ActivitySection] {
        let groups = Dictionary(grouping: filteredNotifications) { ActivityPeriod(date: $0.createdAt) }
        return ActivityPeriod.allCases.compactMap { period in
            groups[period].map { ActivitySection(period: period, items: $0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader
                friendRequestsShortcut
                filterBar

                AsyncStateView(
                    isLoading: isLoading,
                    error: error,
                    isEmpty: filteredNotifications.isEmpty,
                    emptyText: emptyText,
                    topPadding: 42,
                    hasLoaded: hasLoaded,
                    retry: { await load() },
                    emptyIcon: filter == .unread ? "checkmark.circle" : "bell",
                    errorIcon: "exclamationmark.triangle",
                    skeleton: .rows
                ) {
                    ForEach(groupedNotifications) { section in sectionView(section) }
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
                        .font(.footnote.weight(.bold))
                }
            }
        }
        // FitCheckRoute is registered by the parent tab's NavigationStack.
        .revisionTask(appState.contentRevision) { await load() }
        .refreshable { await load() }
    }

    private func sectionView(_ section: ActivitySection) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(section.period.title)
                .font(Theme.micro)
                .tracking(1.2)
                .foregroundStyle(Theme.mutedForeground)
                .padding(.top, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(section.items) { notification in row(for: notification) }
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Activity")
                .font(Theme.editorialFont(size: 34))
                .foregroundStyle(Theme.ink)
            Text("YOUR CIRCLE")
                .font(Theme.micro)
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
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: iconButtonSize, height: iconButtonSize)
                    .background(Theme.accent.opacity(0.10), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Friend requests")
                        .font(Theme.bodyEmphasis)
                        .foregroundStyle(Theme.ink)
                    Text(incomingRequestCount == 0 ? "Find and manage your circle" : "\(incomingRequestCount) waiting for your reply")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }
                Spacer()
                if incomingRequestCount > 0 {
                    Text("\(incomingRequestCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.inverseText)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(Theme.ink, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .padding(13)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.line.opacity(0.10), lineWidth: 1))
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
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: Self.minTapSize, minHeight: Self.minTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark update read")
            }
        }
        .padding(12)
        .background(notification.isRead ? Theme.card : Theme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.line.opacity(0.08), lineWidth: 1))
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
        .accessibilityElement(children: .combine)
        .accessibilityValue(notification.isRead ? "" : "Unread")
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
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            self.error = "Couldn’t load activity. Check your connection and try again."
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
            notifications = notifications.map(\.markedRead)
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

private enum ActivityPeriod: CaseIterable, Hashable {
    case today, thisWeek, earlier

    init(date: Date, calendar: Calendar = .current, now: Date = Date()) {
        if calendar.isDateInToday(date) {
            self = .today
        } else if let week = calendar.dateInterval(of: .weekOfYear, for: now), week.contains(date) {
            self = .thisWeek
        } else {
            self = .earlier
        }
    }

    var title: String {
        switch self {
        case .today: "TODAY"
        case .thisWeek: "THIS WEEK"
        case .earlier: "EARLIER"
        }
    }
}

private struct ActivitySection: Identifiable {
    let period: ActivityPeriod
    let items: [NotificationDTO]
    var id: String { period.title }
}

private extension NotificationDTO {
    var markedRead: NotificationDTO {
        NotificationDTO(id: id, type: type, isRead: true, createdAt: createdAt, fitCheckId: fitCheckId, actor: actor)
    }
}
