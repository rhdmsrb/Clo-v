import SwiftUI

struct GroupsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var groups: [FashionGroup] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?

    @State private var showCreateSheet = false
    @State private var joinCode = ""
    @State private var joinError: String?
    @State private var isJoining = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Button("Create a private circle") { showCreateSheet = true }
                    .buttonStyle(PrimaryButtonStyle())
                joinCard
                AsyncStateView(isLoading: isLoading, error: error, topPadding: 20, hasLoaded: hasLoaded, retry: { await load() }) {
                    circlesSection
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationDestination(for: UUID.self) { id in
            GroupDetailView(groupId: id)
        }
        .sheet(isPresented: $showCreateSheet) {
            NewGroupSheet { await load() }
        }
        .revisionTask(appState.contentRevision) { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Style Circles")
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

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Join a private circle")
                .font(Theme.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            TextField("ABC123", text: $joinCode)
                .font(Theme.body)
                .accessibilityLabel("Invite code")
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .frame(minHeight: Theme.minTapSize)
                .background(Theme.muted, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
            if let joinError {
                Text(joinError).font(Theme.caption).foregroundStyle(Theme.danger)
            }
            Button(isJoining ? "Joining…" : "Join with invite code") { Task { await join() } }
                .buttonStyle(PrimaryButtonStyle(isDisabled: isJoining))
                .disabled(isJoining)
        }
        .elevatedCard()
    }

    @ViewBuilder private var circlesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Private circles")
            if groups.isEmpty {
                EmptyStateView(
                    icon: "person.2",
                    title: "No circles yet",
                    message: "Create one or join with an invite code above.",
                    actionTitle: "Create a circle"
                ) { showCreateSheet = true }
                .padding(.vertical, 12)
            } else {
                ForEach(groups) { group in
                    NavigationLink(value: group.id) { GroupCard(group: group) }
                        .buttonStyle(.plain)
                }
            }
            SectionHeader(title: "Public circles")
            publicPlaceholder
        }
    }

    private var publicPlaceholder: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "globe.americas")
                .font(.title3)
                .foregroundStyle(Theme.accentDeep)
                .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                .background(Theme.accentTint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Discover public style circles")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                Text("Public circles will appear here when discovery is available.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
        .accessibilityElement(children: .combine)
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

    private func join() async {
        joinError = nil
        isJoining = true
        defer { isJoining = false }
        do {
            _ = try await API.joinGroup(code: joinCode)
            Haptics.success()
            joinCode = ""
            await load()
        } catch {
            Haptics.error()
            joinError = error.localizedDescription
        }
    }
}

private struct NewGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    let onCreated: () async -> Void

    @State private var name = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New private circle")
                .font(Theme.displayFont)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityAddTraits(.isHeader)
            Text("Name your circle, then invite friends with a private code.")
                .font(Theme.body)
                .foregroundStyle(Theme.mutedForeground)
            TextField("Name your circle", text: $name)
                .font(Theme.body)
                .padding(.horizontal, 16)
                .frame(minHeight: Theme.minTapSize)
                .background(Theme.muted, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
            if let error {
                Text(error).font(Theme.caption).foregroundStyle(Theme.danger)
            }
            Button(isSaving ? "Please wait…" : "Create private circle") { Task { await create() } }
                .buttonStyle(PrimaryButtonStyle(isDisabled: isSaving))
                .disabled(isSaving)
            Spacer()
        }
        .padding(24)
        .presentationCornerRadius(32)
        .presentationBackground(Theme.cardElevated)
    }

    private func create() async {
        guard name.trimmingCharacters(in: .whitespaces).count >= 2 else {
            error = "Group name must be 2-40 characters."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await API.createGroup(name: name, creatorId: appState.userId)
            Haptics.success()
            await onCreated()
            dismiss()
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
        }
    }
}

/// Elevated list card for one circle: icon, name, and a copyable invite-code capsule.
private struct GroupCard: View {
    let group: FashionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            .accessibilityElement(children: .combine)
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
