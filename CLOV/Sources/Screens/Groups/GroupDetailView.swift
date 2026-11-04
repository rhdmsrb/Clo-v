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

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 36

    private var isOwner: Bool { group?.creatorId == appState.userId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncStateView(isLoading: isLoading, error: error, topPadding: 60, hasLoaded: hasLoaded, retry: { await load() }) {
                if !isMember {
                    EmptyStateView(
                        icon: "lock",
                        title: "Members only",
                        message: "You're not a member of \(group?.name ?? "this group"). Ask a member for the invite code."
                    )
                    .padding(.top, 40)
                } else if let group {
                    header(group)
                    membersList(group)
                    actionRow(group)
                    looksSection
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
        .revisionTask(appState.contentRevision) { await load() }
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

    private func header(_ group: FashionGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("STYLE BOARD")
                        .font(Theme.micro)
                        .tracking(1.3)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(group.name)
                        .font(Theme.editorialFont(size: 32, relativeTo: .title))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 8)
                optionsMenu(group)
            }
            HStack(spacing: 10) {
                stackedAvatars
                countCapsule("\(members.count) member\(members.count == 1 ? "" : "s")", icon: "person.2.fill")
            }
            if !items.isEmpty {
                Text("\(items.count) look\(items.count == 1 ? "" : "s") · \(contributorCount) contributor\(contributorCount == 1 ? "" : "s")")
                    .font(Theme.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .elevatedShadow()
    }

    private func optionsMenu(_ group: FashionGroup) -> some View {
        Menu {
            if isOwner {
                Button("Rename board") { newName = group.name; showRename = true }
                Button("Delete board", role: .destructive) { showDelete = true }
            } else {
                Button("Leave board", role: .destructive) { showLeave = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Board options")
    }

    private var stackedAvatars: some View {
        HStack(spacing: -10) {
            ForEach(Array(members.prefix(6).enumerated()), id: \.offset) { _, member in
                AvatarView(url: member.avatarUrl, nickname: member.nickname, size: avatarSize)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 2))
            }
        }
    }

    private func countCapsule(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(text)
        }
        .font(Theme.caption)
        .foregroundStyle(Theme.accentForeground)
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(Theme.accent, in: Capsule(style: .continuous))
    }

    private func membersList(_ group: FashionGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Members")
            ForEach(members) { member in
                HStack(spacing: 10) {
                    AvatarView(url: member.avatarUrl, nickname: member.nickname, size: avatarSize)
                    Text(member.nickname ?? "Someone").font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
                    if member.id == group.creatorId {
                        Text("Owner")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.accentDeep)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.accentTint, in: Capsule(style: .continuous))
                    }
                    Spacer()
                    if isOwner && member.id != appState.userId {
                        Button("Remove") { memberToRemove = member }
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                            .frame(minHeight: Theme.minTapSize)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Remove \(member.nickname ?? "member")")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    private func actionRow(_ group: FashionGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("+ Post to board") { showCreate = true }
                    .buttonStyle(PrimaryButtonStyle())
                ShareLink(item: "Join my style board on CLO·V — invite code: \(group.inviteCode)") {
                    Text("Invite friends")
                }
                .buttonStyle(OutlineButtonStyle())
            }
            InviteCodeCapsule(code: group.inviteCode)
        }
    }

    @ViewBuilder private var looksSection: some View {
        if items.isEmpty {
            EmptyStateView(
                icon: "photo.on.rectangle",
                title: "No looks yet",
                message: "No looks on this board yet. Add the first one.",
                actionTitle: "+ Post to board"
            ) { showCreate = true }
            .padding(.vertical, 20)
        } else {
            VStack(spacing: 20) {
                ForEach(items) { item in
                    FitCheckCardView(item: item, voterId: appState.userId)
                }
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
