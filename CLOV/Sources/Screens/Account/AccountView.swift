@preconcurrency import SwiftUI
import PhotosUI

@MainActor
struct AccountView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var avatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var terminateTarget: UUID?
    @State private var deleteTarget: UUID?
    @State private var isDeletingAccount = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var showingEditProfile = false
    @State private var followerIDs: Set<UUID> = []
    @State private var followingIDs: Set<UUID> = []
    @State private var selectedFollowList: ProfileFollowList?

    private let profileAccent = Theme.accent

    var body: some View {
        let avatarURL = appState.profile?.avatarUrl
        let nickname = appState.profile?.nickname
        let uploadingAvatar = isUploadingAvatar
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your profile")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .tracking(0.2)
                            .foregroundStyle(profileAccent)
                        Text("Your style")
                            .font(Theme.editorialFont(size: 34))
                            .tracking(-0.5)
                    }
                    Spacer()
                    Button { showingEditProfile = true } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Edit profile")
                }

                profileHero(avatarURL: avatarURL, nickname: nickname, uploadingAvatar: uploadingAvatar)

                sectionHeading("Wardrobe & circle", detail: nil)

                VStack(spacing: 0) {
                    profileShortcut(title: "Wardrobe", subtitle: "Your pieces", icon: "hanger", tint: Theme.iconPlum) {
                        WardrobeView()
                    }
                    profileShortcut(title: "Groups", subtitle: "Private & public circles", icon: "person.3.fill", tint: Theme.iconSage) {
                        GroupsView()
                    }
                    profileShortcut(title: "Friends", subtitle: "Your circle", icon: "person.2.fill", tint: Theme.iconCoral) {
                        FriendsView()
                    }
                    profileShortcut(title: "Your week", subtitle: "Style activity", icon: "chart.bar.fill", tint: Theme.iconApricot) {
                        StyleInsightsView()
                    }
                    profileShortcut(title: "Privacy", subtitle: "Data & controls", icon: "lock.shield.fill", tint: Theme.mutedForeground) {
                        PrivacyView()
                    }
                }

                sectionHeading("Your Fit-Checks", detail: "\(liveVotes.count + archivedVotes.count) posts")

                AsyncStateView(isLoading: isLoading, error: error, topPadding: 20, hasLoaded: hasLoaded, retry: { await load() }) {
                    votesSection(title: "LIVE", items: liveVotes, emptyText: "No live votes yet — post a Fit-Check to get started.")
                    votesSection(title: "ENDED", items: archivedVotes, emptyText: "Completed Fit-Checks will land here.")
                }

                Button("Log out") { Task { await appState.signOut() } }
                    .buttonStyle(OutlineButtonStyle())

                Button("Delete account", role: .destructive) {
                    showingDeleteAccountConfirmation = true
                }
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .disabled(isDeletingAccount)
            }
            .padding(20)
            // Leave room for the floating tab bar so the final section can
            // scroll fully above it on compact simulator screens.
            .padding(.bottom, 88)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 82)
        }
        .background(Theme.background)
        .task(id: appState.contentRevision) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(profile: appState.profile)
        }
        .sheet(item: $selectedFollowList) { list in
            ProfileFollowListView(userId: appState.userId, initialList: list)
                .environmentObject(appState)
        }
        .alert("Delete your account?", isPresented: $showingDeleteAccountConfirmation) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your profile, Fit-Checks, photos, votes, comments, friends, and wardrobe items. This can't be undone.")
        }
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

    private func sectionHeading(_ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.editorialFont(size: 25, relativeTo: .title2))
                .foregroundStyle(Theme.ink)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .padding(.top, 2)
    }

    private func profileHero(avatarURL: String?, nickname: String?, uploadingAvatar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    ZStack {
                        AvatarView(url: avatarURL, nickname: nickname, size: 78)
                            .overlay(Circle().stroke(profileAccent.opacity(0.65), lineWidth: 1.5))
                        if uploadingAvatar {
                            ProgressView().tint(profileAccent)
                        }
                    }
                }
                .onChange(of: avatarItem) { _, newItem in
                    Task { await uploadAvatar(newItem) }
                }
                .accessibilityLabel("Change profile photo")

                VStack(alignment: .leading, spacing: 4) {
                    Text(nickname ?? "Your style profile")
                        .font(Theme.editorialFont(size: 30, relativeTo: .title2))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let email = appState.email {
                        Text(email)
                            .font(.system(.caption, design: .default).weight(.medium))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)
                    }
                    if let createdAt = appState.profile?.createdAt {
                        Label("Here since \(createdAt.formatted(.dateTime.month(.abbreviated).year()))", systemImage: "calendar")
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(profileAccent)
                    }
                }
                Spacer(minLength: 0)
            }

            if let styles = appState.profile?.stylePreferences, !styles.isEmpty {
                Text(styles.joined(separator: "  ·  "))
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundStyle(profileAccent)
            } else {
                Text("Add your style preferences to personalize your feed.")
                            .font(.system(.subheadline, design: .default))
                    .foregroundStyle(Theme.mutedForeground)
            }

            Rectangle()
                .fill(Theme.line.opacity(0.12))
                .frame(height: 1)

            HStack(spacing: 0) {
                profileStat("\(liveVotes.count + archivedVotes.count)", label: "Fit-Checks")
                Button { selectedFollowList = .followers } label: {
                    profileStat("\(followerIDs.count)", label: "Followers")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                Button { selectedFollowList = .following } label: {
                    profileStat("\(followingIDs.count)", label: "Following")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line.opacity(0.1), lineWidth: 1))
    }

    private func profileStat(_ value: String, label: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(value)
                .font(Theme.editorialFont(size: 27, relativeTo: .title2))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func profileShortcut<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(Theme.mutedForeground)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground.opacity(0.7))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title == "Your week" ? "yourWeekButton" : "profileShortcut_\(title)")
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.line.opacity(0.1))
                .frame(height: 0.7)
                .padding(.leading, 45)
        }
    }

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
                            NavigationLink {
                                FitCheckDetailView(fitCheckId: item.id)
                            } label: {
                                Text(item.caption ?? "Untitled")
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            if item.status == "live" && !isExpired(item.expiresAt) {
                                Button("Terminate") { terminateTarget = item.id }
                                    .font(.system(.caption2, design: .default).weight(.bold))
                                    .foregroundStyle(Theme.accent)
                            }
                            Button("Delete") { deleteTarget = item.id }
                                .font(.system(.caption2, design: .default).weight(.bold))
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
        async let followersTask = API.fetchFollowerIDs(userId: appState.userId)
        async let followingTask = API.fetchFollowingIDs(userId: appState.userId)
        do {
            let all = try await API.fetchMyFitChecksWithStatus(creatorId: appState.userId)
            liveVotes = all.filter { $0.status == "live" && !isExpired($0.expiresAt) }
            archivedVotes = all.filter { $0.status == "archived" || isExpired($0.expiresAt) }
            followerIDs = try await followersTask
            followingIDs = try await followingTask
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

    private func deleteAccount() async {
        isDeletingAccount = true
        error = nil
        do {
            try await API.deleteAccount()
            appState.accountDeleted()
        } catch {
            self.error = error.localizedDescription
        }
        isDeletingAccount = false
    }

    private func uploadAvatar(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            let image = try await item.loadImage()
            _ = try await API.updateAvatar(id: appState.userId, image: image)
            Haptics.success()
            await appState.refreshProfile()
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
        }
    }
}

@MainActor
struct StyleInsightsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var report: WeeklyStyleReport?
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("YOUR WEEK")
                    .font(.system(.caption2, design: .default).weight(.black))
                    .tracking(1.5)
                    .foregroundStyle(Theme.accent)
                Text("Style momentum")
                    .font(.system(size: 34, weight: .black, design: .default))
                Text("A quick look at how you showed up this week.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedForeground)

                AsyncStateView(isLoading: isLoading, error: error, topPadding: 16, hasLoaded: hasLoaded, retry: { await load() }) {
                    if let report {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 14) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(report.currentStreak)-day streak")
                                        .font(.system(.title3, design: .default).weight(.heavy))
                                    Text(report.currentStreak == 0 ? "Start with one small style action today." : "Keep the momentum going.")
                                        .font(.caption)
                                        .foregroundStyle(Theme.mutedForeground)
                                }
                                Spacer()
                            }
                            .softCard()

                            LazyVGrid(columns: columns, spacing: 12) {
                                metric("Votes", value: report.votesCast, icon: "hand.thumbsup.fill")
                                metric("Fit-Checks", value: report.fitChecksPosted, icon: "camera.fill")
                                metric("Comments", value: report.commentsWritten, icon: "bubble.left.fill")
                                metric("New pieces", value: report.wardrobePiecesAdded, icon: "hanger")
                            }

                            if let occasion = report.topOccasion {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(Theme.accent)
                                    Text("Your top vibe: \(occasion)")
                                        .font(.system(.subheadline, design: .default).weight(.bold))
                                    Spacer()
                                }
                                .softCard(radius: 16, padding: 14)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Your week")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appState.contentRevision) { await load() }
        .refreshable { await load() }
    }

    private func metric(_ title: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
            Text("\(value)")
                .font(.system(size: 27, weight: .black, design: .default))
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(radius: 16, padding: 14)
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            report = try await API.fetchWeeklyStyleReport(userId: appState.userId)
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load your weekly report. Please try again."
        }
    }
}

/// My-votes row shape — needs `status` and a position-1 thumbnail,
/// which the shared FeedItemDTO doesn't carry.
struct MyFitCheck: Identifiable {
    let id: UUID
    let caption: String?
    let status: String
    var expiresAt: Date? = nil
    let thumbnailURL: String?
}

@MainActor
private struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var nickname: String
    @State private var styles: Set<String>
    @State private var isSaving = false
    @State private var error: String?

    private static let styleOptions = ["Streetwear", "Casual", "Formal", "Athletic", "Vintage", "Minimalist", "Bohemian", "Glam"]

    init(profile: Profile?) {
        _nickname = State(initialValue: profile?.nickname ?? "")
        _styles = State(initialValue: Set(profile?.stylePreferences ?? []))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LabeledField(label: "NICKNAME") {
                        TextField("Your nickname", text: $nickname)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Text("WHAT'S YOUR STYLE?")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.mutedForeground)
                    FlowLayout(spacing: 8) {
                        ForEach(Self.styleOptions, id: \.self) { style in
                            ChipToggle(label: style, selected: styles.contains(style)) {
                                if styles.contains(style) { styles.remove(style) }
                                else { styles.insert(style) }
                            }
                        }
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button(isSaving ? "Saving…" : "Save profile") { Task { await save() } }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: isSaving))
                        .disabled(isSaving)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() async {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "^[A-Za-z0-9_]{3,20}$", options: .regularExpression) != nil else {
            error = "Nickname must be 3–20 letters, numbers, or underscores."
            return
        }
        guard !styles.isEmpty else { error = "Pick at least one style."; return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await API.saveOnboarding(nickname: trimmed, styles: styles.sorted())
            await appState.refreshProfile()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
