import SwiftUI

/// A friend's (or any person's) public profile: ID, follower/following counts,
/// mutual friends, and the styles they like.
struct FriendProfileView: View {
    @EnvironmentObject private var appState: AppState
    let person: AuthorInfoWithId

    @State private var profile: Profile?
    @State private var followerCount = 0
    @State private var followingCount = 0
    @State private var isFollowing = false
    @State private var isUpdatingFollow = false
    @State private var isLoading = true
    @State private var error: String?

    private var displayName: String { person.nickname ?? "Style lover" }
    private var isSelf: Bool { person.id == appState.userId }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                identity
                stats
                if !isSelf { followButton }
                styles
                if let error { Text(error).font(Theme.label).foregroundStyle(Theme.danger) }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var identity: some View {
        VStack(spacing: 8) {
            AvatarView(url: person.avatarUrl, nickname: person.nickname, size: 96)
            Text(displayName)
                .font(Theme.editorialFont(size: 30, relativeTo: .title))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("CLO·V ID \(person.accountCode)")
                .font(Theme.label)
                .foregroundStyle(Theme.mutedForeground)
                .textSelection(.enabled)
            if let createdAt = profile?.createdAt {
                Label("Here since \(createdAt.formatted(.dateTime.month(.abbreviated).year()))", systemImage: "calendar")
                    .font(Theme.micro)
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var stats: some View {
        HStack(spacing: 0) {
            statCell(value: followerCount, label: "Followers")
            statCell(value: followingCount, label: "Following")
            if !isSelf { statCell(value: person.mutualCount, label: "Mutual") }
        }
        .softCard(radius: Theme.cardRadius, padding: 12)
        .redacted(reason: isLoading ? .placeholder : [])
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(Theme.title).foregroundStyle(Theme.ink)
            Text(label).font(Theme.micro).foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var followButton: some View {
        if isFollowing {
            Button { Task { await toggleFollow() } } label: { followLabel }
                .buttonStyle(OutlineButtonStyle())
                .disabled(isUpdatingFollow || isLoading)
        } else {
            Button { Task { await toggleFollow() } } label: { followLabel }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isUpdatingFollow || isLoading)
        }
    }

    private var followLabel: some View {
        HStack(spacing: 6) {
            if isUpdatingFollow { ProgressView().controlSize(.small) }
            Text(isFollowing ? "Following" : "Follow")
        }
    }

    @ViewBuilder private var styles: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Style")
            if let styles = profile?.stylePreferences, !styles.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(styles, id: \.self) { style in
                        Text(style)
                            .font(Theme.label)
                            .foregroundStyle(Theme.accentDeep)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.accentTint, in: Capsule(style: .continuous))
                    }
                }
            } else if !isLoading {
                Text("\(displayName) hasn’t picked any styles yet.")
                    .font(Theme.body).foregroundStyle(Theme.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        error = nil
        do {
            async let profileTask = API.fetchPublicProfile(id: person.id)
            async let followersTask = API.fetchFollowerIDs(userId: person.id)
            async let followingTask = API.fetchFollowingIDs(userId: person.id)
            profile = try await profileTask
            let followers = try await followersTask
            followerCount = followers.count
            followingCount = try await followingTask.count
            isFollowing = followers.contains(appState.userId)
        } catch {
            self.error = "Couldn’t load this profile. Pull down to try again."
        }
        isLoading = false
    }

    private func toggleFollow() async {
        let shouldFollow = !isFollowing
        isUpdatingFollow = true
        defer { isUpdatingFollow = false }
        do {
            try await API.setFollowing(shouldFollow, followerId: appState.userId, followingId: person.id)
            isFollowing = shouldFollow
            followerCount = max(0, followerCount + (shouldFollow ? 1 : -1))
            appState.contentDidChange()
            Haptics.success()
        } catch {
            self.error = "Couldn’t update follow. Please try again."
        }
    }
}
