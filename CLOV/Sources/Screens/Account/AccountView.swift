import SwiftUI
import PhotosUI

struct AccountView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var avatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var terminateTarget: UUID?
    @State private var deleteTarget: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        ZStack {
                            AvatarView(url: appState.profile?.avatarUrl, nickname: appState.profile?.nickname, size: 68)
                            if isUploadingAvatar {
                                ProgressView().tint(.white)
                            }
                        }
                    }
                    .onChange(of: avatarItem) { _, newItem in
                        Task { await uploadAvatar(newItem) }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.profile?.nickname ?? "Unnamed")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                        if let email = appState.email {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        if let styles = appState.profile?.stylePreferences, !styles.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(styles, id: \.self) { style in
                                    Text(style)
                                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 3)
                                        .background(Theme.muted)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .softCard()

                NavigationLink {
                    FriendsView()
                } label: {
                    HStack {
                        Text("Friends and circle")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    }
                    .softCard(radius: 18, padding: 14)
                }
                .buttonStyle(.plain)

                AsyncStateView(isLoading: isLoading, error: error, topPadding: 20, hasLoaded: hasLoaded, retry: { await load() }) {
                    votesSection(title: "LIVE", items: liveVotes, emptyText: "No live votes yet — post a Fit-Check to get started.")
                    votesSection(title: "ARCHIVED", items: archivedVotes, emptyText: "Terminated votes will land here.")
                }

                Button("Log out") { Task { await appState.signOut() } }
                    .buttonStyle(OutlineButtonStyle())
            }
            .padding(20)
        }
        .background(Theme.background)
        .task(id: appState.contentRevision) { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            "End voting on this Fit-Check?",
            isPresented: Binding(get: { terminateTarget != nil }, set: { if !$0 { terminateTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Terminate", role: .destructive) {
                if let id = terminateTarget { Task { await terminate(id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Voting closes immediately and can't be reopened.")
        }
        .confirmationDialog(
            "Delete this Fit-Check?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = deleteTarget { Task { await delete(id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes it along with its photos, votes, and comments. This can't be undone.")
        }
    }

    // MARK: - My votes (kept separate from FeedItemDTO since status matters here)

    @State private var liveVotes: [MyFitCheck] = []
    @State private var archivedVotes: [MyFitCheck] = []

    @ViewBuilder
    private func votesSection(title: String, items: [MyFitCheck], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.caption2, design: .default).weight(.bold)).foregroundStyle(.secondary)
            if items.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Theme.card.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            RemoteImage(url: item.thumbnailURL ?? "")
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Text(item.caption ?? "Untitled")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            if item.status == "live" {
                                Button("Terminate") { terminateTarget = item.id }
                                    .font(.system(.caption2, design: .rounded).weight(.bold))
                                    .foregroundStyle(Theme.accent)
                            }
                            Button("Delete") { deleteTarget = item.id }
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(.red)
                        }
                        .softCard(radius: 18, padding: 12)
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let all = try await API.fetchMyFitChecksWithStatus(creatorId: appState.userId)
            liveVotes = all.filter { $0.status == "live" }
            archivedVotes = all.filter { $0.status == "archived" }
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load this content. Please try again."
        }
    }

    private func terminate(_ id: UUID) async {
        do {
            try await API.terminateFitCheck(id: id, creatorId: appState.userId)
            Haptics.impact(.medium)
            await load()
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
        }
    }

    private func delete(_ id: UUID) async {
        do {
            try await API.deleteFitCheck(id: id, creatorId: appState.userId)
            Haptics.impact(.medium)
            await load()
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            _ = try await API.updateAvatar(id: appState.userId, image: image)
            Haptics.success()
            await appState.refreshProfile()
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
        }
    }
}

/// My-votes row shape — needs `status` and a position-1 thumbnail,
/// which the shared FeedItemDTO doesn't carry.
struct MyFitCheck: Identifiable {
    let id: UUID
    let caption: String?
    let status: String
    let thumbnailURL: String?
}
