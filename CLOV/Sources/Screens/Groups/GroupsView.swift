import SwiftUI

struct GroupsView: View {
    @EnvironmentObject private var appState: AppState

    /// True when pushed inside another NavigationStack (e.g. from Profile).
    /// As a tab root (default) the view owns its NavigationStack.
    var embedded = false

    @State private var groups: [FashionGroup] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var addMode: GroupAddSheet.Mode?

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                HStack(spacing: 8) {
                    Button("+ Create") { addMode = .create }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("groups.create")
                    Button("+ Join") { addMode = .join }
                        .buttonStyle(OutlineButtonStyle())
                        .accessibilityIdentifier("groups.join")
                }
                AsyncStateView(isLoading: isLoading, error: error, topPadding: 20, hasLoaded: hasLoaded, retry: { await load() }) {
                    circlesSection
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .accessibilityIdentifier("groups.root")
        .navigationDestination(for: UUID.self) { id in
            GroupDetailView(groupId: id, groupName: groups.first(where: { $0.id == id })?.name)
        }
        .sheet(item: $addMode) { mode in
            GroupAddSheet(initialMode: mode) { await load() }
        }
        .revisionTask(appState.contentRevision) { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Groups")
                .font(Theme.editorialFont(size: 34, relativeTo: .largeTitle))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityAddTraits(.isHeader)
            Text("A place to plan looks, share ideas, and get ready together.")
                .font(Theme.body)
                .foregroundStyle(Theme.mutedForeground)
        }
    }

    @ViewBuilder private var circlesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if groups.isEmpty {
                EmptyStateView(
                    icon: "person.2",
                    title: "No groups yet",
                    message: "Create one or join with an invite code.",
                    actionTitle: "Create a group"
                ) { addMode = .create }
                .padding(.vertical, 12)
            } else {
                ForEach(groups) { group in
                    GroupCard(group: group)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            groups = try await API.fetchMyGroups(profileId: appState.userId)
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load this content. Please try again."
        }
    }
}

/// Elevated list card for one circle: icon, name, and a copyable invite-code capsule.
private struct GroupCard: View {
    let group: FashionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: group.id) {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accentDeep)
                        .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                        .background(Theme.accentTint, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                            .font(Theme.headline)
                            .foregroundStyle(Theme.ink)
                        Text("Private circle")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            InviteCodeCapsule(code: group.inviteCode)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }
}

/// Invite code shown as a capsule; tapping copies it to the pasteboard.
struct InviteCodeCapsule: View {
    let code: String
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let resetDelay: Duration = .seconds(2)

    var body: some View {
        Button {
            UIPasteboard.general.string = code
            withAnimation(Theme.animation(Theme.snap, reduceMotion: reduceMotion)) { copied = true }
            AccessibilityNotification.Announcement("Invite code copied").post()
            Task {
                try? await Task.sleep(for: Self.resetDelay)
                withAnimation(Theme.animation(Theme.snap, reduceMotion: reduceMotion)) { copied = false }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .accessibilityHidden(true)
                Text(copied ? "Copied" : code)
                    .monospaced()
            }
            .font(Theme.label)
            .foregroundStyle(Theme.accentDeep)
            .padding(.horizontal, 14)
            .frame(minHeight: Theme.minTapSize)
            .background(Theme.accentTint, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Theme.accentDeep.opacity(0.4), lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Invite code \(code)")
        .accessibilityHint("Copies the code")
    }
}
