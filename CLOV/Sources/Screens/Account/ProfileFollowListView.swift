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
                    EmptyStateView(icon: "exclamationmark.triangle", title: "Couldn’t load people",
                                   message: error, actionTitle: "Try again", tint: Theme.danger) {
                        Task { await load() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if people.isEmpty {
                    EmptyStateView(icon: "person.2",
                                   title: selectedList == .followers ? "No followers yet" : "Not following anyone",
                                   message: selectedList == .followers ? "When people follow you, they’ll show up here."
                                       : "Follow people to see their fits in your feed.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(people) { person in
                        personRow(person)
                            .listRowBackground(Theme.background)
                            .listRowSeparator(.hidden)
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
                        .foregroundStyle(Theme.accentDeep)
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func personRow(_ person: AuthorInfoWithId) -> some View {
        HStack(spacing: 12) {
            AvatarView(url: person.avatarUrl, nickname: person.nickname, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(person.nickname ?? "Style lover")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                Text(person.accountCode)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.mutedForeground)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            followButton(for: person)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func followButton(for person: AuthorInfoWithId) -> some View {
        let isFollowing = followingIDs.contains(person.id)
        Button {
            Task { await setFollowing(!isFollowing, person: person) }
        } label: {
            HStack(spacing: 5) {
                if updatingIDs.contains(person.id) { ProgressView().controlSize(.mini) }
                if isFollowing {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).accessibilityHidden(true)
                }
                Text(isFollowing ? "Following" : "Follow")
                    .font(Theme.label)
            }
            .foregroundStyle(isFollowing ? Theme.ink : Color.white)
            .padding(.horizontal, 16)
            .frame(minHeight: Theme.minTapSize)
            .background {
                if isFollowing {
                    Capsule(style: .continuous).fill(Theme.muted)
                        .overlay(Capsule(style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
                } else {
                    Capsule(style: .continuous).fill(Theme.heroGradient)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(updatingIDs.contains(person.id))
        .motionSafeAnimation(Theme.snap, value: isFollowing)
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
