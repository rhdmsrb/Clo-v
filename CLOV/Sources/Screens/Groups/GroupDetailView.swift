import SwiftUI

struct GroupDetailView: View {
    let groupId: UUID
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var group: FashionGroup?
    @State private var members: [GroupMemberDisplay] = []
    @State private var isMember = false
    @State private var items: [FeedItemDTO] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var showCreate = false
    @State private var showRename = false
    @State private var showLeave = false
    @State private var showDelete = false
    @State private var memberToRemove: GroupMemberDisplay?
    @State private var newName = ""

    private var isOwner: Bool { group?.creatorId == appState.userId }

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
                        Text("STYLE BOARD")
                            .font(.system(.caption2, design: .default).weight(.black))
                            .tracking(1.3)
                            .foregroundStyle(Theme.accent)
                        HStack {
                            Text(group.name).font(Theme.editorialFont(size: 32, relativeTo: .title))
                            Spacer()
                            Menu {
                                if isOwner {
                                    Button("Rename board") { newName = group.name; showRename = true }
                                    Button("Delete board", role: .destructive) { showDelete = true }
                                } else {
                                    Button("Leave board", role: .destructive) { showLeave = true }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.title3)
                            }
                            .accessibilityLabel("Board options")
                        }
                        HStack(spacing: -8) {
                            ForEach(Array(members.prefix(6).enumerated()), id: \.offset) { _, member in
                                AvatarView(url: member.avatarUrl, nickname: member.nickname, size: 26)
                                    .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                            }
                        }
                        Text("\(members.count) member\(members.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Theme.mutedForeground)
                        ForEach(members) { member in
                            HStack(spacing: 8) {
                                AvatarView(url: member.avatarUrl, nickname: member.nickname, size: 28)
                                Text(member.nickname ?? "Someone").font(.subheadline)
                                if member.id == group.creatorId { Text("Owner").font(.caption).foregroundStyle(Theme.mutedForeground) }
                                Spacer()
                                if isOwner && member.id != appState.userId {
                                    Button("Remove") { memberToRemove = member }
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                        if !items.isEmpty {
                            Text("\(items.count) look\(items.count == 1 ? "" : "s") · \(contributorCount) contributor\(contributorCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }

                    HStack(spacing: 8) {
                        Button("+ Post to board") { showCreate = true }
                            .buttonStyle(PrimaryButtonStyle())
                        ShareLink(item: "Join my style board on CLO·V — invite code: \(group.inviteCode)") {
                            Text("Invite friends")
                        }
                        .buttonStyle(OutlineButtonStyle())
                    }

                    if items.isEmpty {
                        Text("No looks on this board yet. Add the first one.")
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
        .alert("Rename board", isPresented: $showRename) {
            TextField("Board name", text: $newName)
            Button("Save") { Task { await rename() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Leave this board?", isPresented: $showLeave) {
            Button("Leave board", role: .destructive) { Task { await leave() } }
        }
        .confirmationDialog("Delete this board?", isPresented: $showDelete) {
            Button("Delete board", role: .destructive) { Task { await deleteBoard() } }
        } message: {
            Text("Members will lose access. Posts on this board will no longer appear in a board.")
        }
        .confirmationDialog("Remove this member?", isPresented: Binding(
            get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }
        )) {
            Button("Remove member", role: .destructive) {
                if let memberToRemove { Task { await remove(memberToRemove) } }
            }
        }
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

    private var contributorCount: Int {
        Set(items.map(\.creatorId)).count
    }

    private func rename() async {
        do {
            try await API.renameGroup(id: groupId, name: newName)
            appState.contentDidChange()
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func leave() async {
        do {
            try await API.leaveGroup(id: groupId, profileId: appState.userId)
            appState.contentDidChange()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func deleteBoard() async {
        do {
            try await API.deleteGroup(id: groupId)
            appState.contentDidChange()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func remove(_ member: GroupMemberDisplay) async {
        do {
            try await API.removeGroupMember(groupId: groupId, profileId: member.id)
            memberToRemove = nil
            await load()
        } catch { self.error = error.localizedDescription }
    }
}
