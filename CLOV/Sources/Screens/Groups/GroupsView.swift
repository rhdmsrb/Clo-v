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
                Text("Groups").font(.system(.largeTitle, design: .rounded).weight(.heavy))

                Button("+ Create a group") { showCreateSheet = true }
                    .buttonStyle(PrimaryButtonStyle())

                VStack(alignment: .leading, spacing: 10) {
                    Text("HAVE AN INVITE CODE?")
                        .font(.system(.caption2, design: .default).weight(.bold))
                        .foregroundStyle(.secondary)
                    TextField("ABC123", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if let joinError {
                        Text(joinError).font(.caption).foregroundStyle(.red)
                    }
                    Button(isJoining ? "Joining…" : "Join group") { Task { await join() } }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: isJoining))
                        .disabled(isJoining)
                }
                .softCard()

                Text("MY GROUPS")
                    .font(.system(.caption2, design: .default).weight(.bold))
                    .foregroundStyle(.secondary)

                AsyncStateView(isLoading: isLoading, error: error, isEmpty: groups.isEmpty,
                               emptyText: "You're not in any groups yet.", topPadding: 20, hasLoaded: hasLoaded, retry: { await load() }) {
                    VStack(spacing: 10) {
                        ForEach(groups) { group in
                            NavigationLink(value: group.id) {
                                Text(group.name)
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .softCard(radius: 18, padding: 16)
                            }
                            .foregroundStyle(Color.primary)
                            .buttonStyle(TileButtonStyle())
                        }
                    }
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
        .task(id: appState.contentRevision) { await load() }
        .refreshable { await load() }
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
            Text("New group").font(Theme.displayFont)
            Text("Give it a name — you'll get an invite link to share right after.")
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)
            TextField("BESTIEZ", text: $name)
                .padding(14)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button(isSaving ? "Please wait…" : "Create group") { Task { await create() } }
                .buttonStyle(PrimaryButtonStyle(isDisabled: isSaving))
                .disabled(isSaving)
            Spacer()
        }
        .padding(24)
        .presentationBackground(.regularMaterial)
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
