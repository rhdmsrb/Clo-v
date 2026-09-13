import SwiftUI

struct GroupDetailView: View {
    let groupId: UUID
    @EnvironmentObject private var appState: AppState

    @State private var group: FashionGroup?
    @State private var members: [AuthorInfo] = []
    @State private var isMember = false
    @State private var items: [FeedItemDTO] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var showCreate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncStateView(isLoading: isLoading, error: error, topPadding: 60, hasLoaded: hasLoaded, retry: { await load() }) {
                if !isMember {
                    Text("You're not a member of \(group?.name ?? "this group"). Ask a member for the invite link.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let group {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.name).font(.system(.title, design: .rounded).weight(.heavy))
                        HStack(spacing: -8) {
                            ForEach(Array(members.prefix(6).enumerated()), id: \.offset) { _, member in
                                AvatarView(url: member.avatarUrl, nickname: member.nickname, size: 26)
                                    .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                            }
                        }
                        Text("\(members.count) member\(members.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Theme.mutedForeground)
                    }

                    HStack(spacing: 8) {
                        Button("+ Post here") { showCreate = true }
                            .buttonStyle(PrimaryButtonStyle())
                        ShareLink(item: "Join my group on CLO·V — invite code: \(group.inviteCode)") {
                            Text("Share")
                        }
                        .buttonStyle(OutlineButtonStyle())
                    }

                    if items.isEmpty {
                        Text("No Fit-Checks in this group yet.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    } else {
                        VStack(spacing: 20) {
                            ForEach(items) { item in
                                FitCheckCardView(item: item, voterId: appState.userId)
                            }
                        }
                    }
                }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationDestination(for: FitCheckRoute.self) { route in
            FitCheckDetailView(fitCheckId: route.id)
        }
        .fullScreenCover(isPresented: $showCreate) {
            CreateFitCheckView(preselectedGroup: group)
        }
        .task(id: appState.contentRevision) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            isMember = try await API.isMember(groupId: groupId, profileId: appState.userId)
            guard isMember else { return }
            async let groups = API.fetchMyGroups(profileId: appState.userId)
            async let membersTask = API.fetchGroupMembers(groupId: groupId)
            async let feedTask = API.fetchGroupFeed(groupId: groupId)
            group = try await groups.first(where: { $0.id == groupId })
            members = try await membersTask
            items = try await feedTask
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load this content. Please try again."
        }
    }
}
