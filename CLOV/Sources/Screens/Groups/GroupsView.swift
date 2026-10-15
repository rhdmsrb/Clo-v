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
                Text("Style Circles").font(Theme.editorialFont(size: 38))
                Text("A place to plan looks, share ideas, and get ready together.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedForeground)

                Button("Create a private circle") { showCreateSheet = true }
                    .buttonStyle(PrimaryButtonStyle())

                VStack(alignment: .leading, spacing: 10) {
                    Text("JOIN A PRIVATE CIRCLE")
                        .font(.system(.caption2, design: .default).weight(.bold))
                        .foregroundStyle(.secondary)
                    TextField("ABC123", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Theme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if let joinError {
                        Text(joinError).font(.caption).foregroundStyle(.red)
                    }
                    Button(isJoining ? "Joining…" : "Join with invite code") { Task { await join() } }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: isJoining))
                        .disabled(isJoining)
                }
                .softCard()

                AsyncStateView(isLoading: isLoading, error: error, topPadding: 20, hasLoaded: hasLoaded, retry: { await load() }) {
                    VStack(alignment: .leading, spacing: 22) {
                        groupSectionHeading("Private circles", detail: "INVITE ONLY")
                        if groups.isEmpty {
                            Text("Your invite-only circles will appear here. Create one or join with a code above.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.mutedForeground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(groups) { group in
                                    NavigationLink(value: group.id) {
                                        HStack(spacing: 13) {
                                            Image(systemName: "person.2")
                                                .font(.system(size: 16, weight: .regular))
                                                .foregroundStyle(Theme.accent)
                                                .frame(width: 34)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(group.name)
                                                    .font(.system(size: 16, weight: .medium))
                                                    .foregroundStyle(Theme.ink)
                                                Text("Private · invite code")
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.mutedForeground)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(Theme.mutedForeground)
                                        }
                                        .padding(.vertical, 13)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .overlay(alignment: .bottom) {
                                        Rectangle().fill(Theme.line.opacity(0.1)).frame(height: 0.7).padding(.leading, 46)
                                    }
                                }
                            }
                        }

                        groupSectionHeading("Public circles", detail: "OPEN TO EVERYONE")
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "globe.americas")
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.accentSecondary)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Discover public style circles")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Text("Public circles will appear here when discovery is available.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.mutedForeground)
                            }
                        }
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private func groupSectionHeading(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.editorialFont(size: 26, relativeTo: .title2))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(detail)
                .font(.system(size: 8, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.mutedForeground)
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
            Text("New private circle").font(Theme.displayFont)
            Text("Name your circle, then invite friends with a private code.")
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)
            TextField("Name your circle", text: $name)
                .padding(14)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button(isSaving ? "Please wait…" : "Create private circle") { Task { await create() } }
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
