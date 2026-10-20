import SwiftUI

enum ProfileFollowList: String, Identifiable {
    case followers = "Followers"
    case following = "Following"

    var id: String { rawValue }
}

@MainActor
struct ProfileFollowListView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let userId: UUID
    @State private var selectedList: ProfileFollowList
    @State private var followers: [AuthorInfoWithId] = []
    @State private var following: [AuthorInfoWithId] = []
    @State private var followingIDs: Set<UUID> = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var updatingIDs: Set<UUID> = []

    init(userId: UUID, initialList: ProfileFollowList) {
        self.userId = userId
        _selectedList = State(initialValue: initialList)
    }

    private var people: [AuthorInfoWithId] {
        selectedList == .followers ? followers : following
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("People", selection: $selectedList) {
                    ForEach([ProfileFollowList.followers, .following]) { list in
                        Text(list.rawValue).tag(list)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 12) {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Theme.mutedForeground)
                            .multilineTextAlignment(.center)
                        Button("Try again") { Task { await load() } }
                            .buttonStyle(OutlineButtonStyle())
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if people.isEmpty {
                    Text(selectedList == .followers ? "No followers yet." : "You’re not following anyone yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(people) { person in
                        HStack(spacing: 12) {
                            AvatarView(url: person.avatarUrl, nickname: person.nickname, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(person.nickname ?? "Style lover")
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                Text(person.accountCode)
                                    .font(.caption)
                                    .foregroundStyle(Theme.mutedForeground)
                            }
                            .accessibilityElement(children: .combine)
                            Spacer(minLength: 8)
                            followButton(for: person)
                        }
                        .listRowBackground(Theme.background)
                        .listRowSeparatorTint(Theme.line.opacity(0.1))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background)
            .navigationTitle(selectedList.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private func followButton(for person: AuthorInfoWithId) -> some View {
        let isFollowing = followingIDs.contains(person.id)
        Button {
            Task { await setFollowing(!isFollowing, person: person) }
        } label: {
            HStack(spacing: 5) {
                if updatingIDs.contains(person.id) { ProgressView().controlSize(.mini) }
                Text(isFollowing ? "Following" : "Follow")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isFollowing ? Theme.ink : Theme.inverseText)
            .padding(.horizontal, 13)
            .frame(minHeight: 32)
            .background(isFollowing ? Theme.muted : Theme.ink, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(updatingIDs.contains(person.id))
        .accessibilityLabel(isFollowing ? "Following \(person.nickname ?? "user")" : "Follow \(person.nickname ?? "user")")
        .accessibilityHint(isFollowing ? "Double tap to unfollow" : "Double tap to follow")
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        async let followerTask = API.fetchFollowerIDs(userId: userId)
        async let followingTask = API.fetchFollowingIDs(userId: userId)
        do {
            let fetchedFollowers = try await followerTask
            let fetchedFollowing = try await followingTask
            async let followerProfilesTask = API.fetchProfiles(ids: Array(fetchedFollowers))
            async let followingProfilesTask = API.fetchProfiles(ids: Array(fetchedFollowing))
            let fetchedFollowerProfiles = try await followerProfilesTask
            let fetchedFollowingProfiles = try await followingProfilesTask
            followers = fetchedFollowerProfiles.sorted { ($0.nickname ?? "").localizedCaseInsensitiveCompare($1.nickname ?? "") == .orderedAscending }
            following = fetchedFollowingProfiles.sorted { ($0.nickname ?? "").localizedCaseInsensitiveCompare($1.nickname ?? "") == .orderedAscending }
            followingIDs = fetchedFollowing
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load your people. Pull to refresh and try again."
        }
    }

    private func setFollowing(_ shouldFollow: Bool, person: AuthorInfoWithId) async {
        guard !updatingIDs.contains(person.id) else { return }
        updatingIDs.insert(person.id)
        defer { updatingIDs.remove(person.id) }
        do {
            try await API.setFollowing(shouldFollow, followerId: userId, followingId: person.id)
            if shouldFollow {
                followingIDs.insert(person.id)
                if !following.contains(where: { $0.id == person.id }) { following.append(person) }
            } else {
                followingIDs.remove(person.id)
                following.removeAll { $0.id == person.id }
            }
            appState.contentDidChange()
            Haptics.success()
        } catch {
            self.error = "Couldn’t update your following list. Please try again."
        }
    }
}
