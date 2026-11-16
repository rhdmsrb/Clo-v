import SwiftUI

/// People the user has blocked, with a way to lift each block.
@MainActor
struct BlockedUsersView: View {
    @EnvironmentObject private var appState: AppState

    @State private var people: [BlockedUser] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var actionError: String?
    @State private var unblockTarget: BlockedUser?
    @State private var unblockingIDs: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Blocked people can't see your Fit-Checks or comment on them, and you won't see theirs.")
                    .font(Theme.font(.footnote))
                    .foregroundStyle(Theme.mutedForeground)
                AsyncStateView(
                    isLoading: isLoading, error: error, isEmpty: people.isEmpty,
                    emptyText: "People you block will show up here, so you can unblock them later.",
                    topPadding: 24, hasLoaded: hasLoaded, retry: { await load() },
                    emptyIcon: "person.slash", emptyTitle: "No blocked people"
                ) {
                    LazyVStack(spacing: 12) {
                        ForEach(people) { person in row(person) }
                    }
                }
                if let actionError {
                    Label(actionError, systemImage: "exclamationmark.circle.fill")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                }
            }
            .padding(20)
            .padding(.bottom, 88)
        }
        .background(Theme.background)
        .navigationTitle("Blocked people")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            unblockTarget.map { "Unblock \($0.displayName)?" } ?? "Unblock?",
            isPresented: Binding(get: { unblockTarget != nil }, set: { if !$0 { unblockTarget = nil } }),
            titleVisibility: .visible,
            presenting: unblockTarget
        ) { person in
            Button("Unblock \(person.displayName)") { Task { await unblock(person) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("They'll be able to see your Fit-Checks and comment on them again.")
        }
    }

    private func row(_ person: BlockedUser) -> some View {
        let isWorking = unblockingIDs.contains(person.id)
        return HStack(spacing: 12) {
            AvatarView(url: person.avatarUrl, nickname: person.nickname, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName)
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let blockedAt = person.blockedAt {
                    Text("Blocked \(blockedAt.formatted(.relative(presentation: .named)))")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            Spacer(minLength: 8)
            Button { unblockTarget = person } label: {
                Text(isWorking ? "Unblocking…" : "Unblock")
                    .font(Theme.label)
                    .foregroundStyle(Theme.accentDeep)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minTapSize)
                    .overlay(Capsule(style: .continuous).stroke(Theme.accentDeep, lineWidth: 1.5))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(InstantPressStyle())
            .disabled(isWorking)
            .accessibilityLabel("Unblock \(person.displayName)")
            .accessibilityIdentifier("unblock_\(person.displayName)")
        }
        .softCard(radius: Theme.tileRadius, padding: 12)
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            people = try await API.fetchBlockedUsers()
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            self.error = "Couldn’t load your blocked people. Please try again."
        }
    }

    private func unblock(_ person: BlockedUser) async {
        unblockingIDs.insert(person.id)
        actionError = nil
        defer { unblockingIDs.remove(person.id) }
        do {
            try await API.unblockUser(id: person.id)
            people.removeAll { $0.id == person.id }
            Haptics.success()
            AccessibilityNotification.Announcement("Unblocked \(person.displayName)").post()
            // Their Fit-Checks can show up in the feed again.
            appState.contentDidChange()
        } catch {
            Haptics.error()
            actionError = "Couldn’t unblock \(person.displayName). Please try again."
        }
    }
}
