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
    @State private var showingEditProfile = false
    @State private var followerIDs: Set<UUID> = []
    @State private var followingIDs: Set<UUID> = []
    @State private var selectedFollowList: ProfileFollowList?

    private let profileAccent = Theme.accentDeep
    private let shortcutColumns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        let avatarURL = appState.profile?.avatarUrl
        let nickname = appState.profile?.nickname
        let uploadingAvatar = isUploadingAvatar
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                profileHero(avatarURL: avatarURL, nickname: nickname, uploadingAvatar: uploadingAvatar)

                SectionHeader(title: "Wardrobe & circle")
                shortcutGrid

                SectionHeader(title: "Your Fit-Checks")
                    .overlay(alignment: .trailing) {
                        Text("\(liveVotes.count + archivedVotes.count) posts")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.mutedForeground)
                    }

                AsyncStateView(isLoading: isLoading, error: error, topPadding: 20, hasLoaded: hasLoaded, retry: { await load() }) {
                    votesSection(title: "LIVE", items: liveVotes, emptyText: "No live votes yet — post a Fit-Check to get started.")
                    votesSection(title: "ENDED", items: archivedVotes, emptyText: "Completed Fit-Checks will land here.")
                }
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
        .revisionTask(appState.contentRevision) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(profile: appState.profile)
        }
        .sheet(item: $selectedFollowList) { list in
            ProfileFollowListView(userId: appState.userId, initialList: list)
                .environmentObject(appState)
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your profile")
                    .font(Theme.label)
                    .foregroundStyle(profileAccent)
                Text("Your style")
                    .font(Theme.editorialFont(size: 34))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button { showingEditProfile = true } label: {
                Image(systemName: "pencil")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                    .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                    .background(Theme.muted, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Edit profile")
            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                    .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                    .background(Theme.muted, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(InstantPressStyle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsButton")
        }
    }

    private var shortcutGrid: some View {
        LazyVGrid(columns: shortcutColumns, spacing: 16) {
            profileShortcut(title: "Wardrobe", subtitle: "Your pieces", icon: "hanger", tint: Theme.iconCoral) {
                WardrobeView()
            }
            profileShortcut(title: "Groups", subtitle: "Private & public circles", icon: "person.3", tint: Theme.iconPlum) {
                GroupsView()
            }
            profileShortcut(title: "Friends", subtitle: "Your circle", icon: "person.2", tint: Theme.iconApricot) {
                FriendsView()
            }
            profileShortcut(title: "Your week", subtitle: "Style activity", icon: "chart.bar", tint: Theme.iconSage) {
                StyleInsightsView()
            }
        }
    }

    private func profileHero(avatarURL: String?, nickname: String?, uploadingAvatar: Bool) -> some View {
        VStack(spacing: 14) {
            PhotosPicker(selection: $avatarItem, matching: .images) {
                ZStack {
                    AvatarView(url: avatarURL, nickname: nickname, size: 96, ringed: true)
                    if uploadingAvatar {
                        ProgressView().tint(.white)
                    }
                }
                .padding(8)
                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                .contentShape(Circle())
            }
            .onChange(of: avatarItem) { _, newItem in
                Task { await uploadAvatar(newItem) }
            }
            .accessibilityLabel("Change profile photo")

            VStack(spacing: 4) {
                Text(nickname ?? "Your style profile")
                    .font(Theme.editorialFont(size: 30, relativeTo: .title2))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                if let email = appState.email {
                    Text(email)
                        .font(Theme.caption)
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                }
                if let createdAt = appState.profile?.createdAt {
                    Label("Here since \(createdAt.formatted(.dateTime.month(.abbreviated).year()))", systemImage: "calendar")
                        .font(Theme.micro)
                        .foregroundStyle(Color.white.opacity(0.9))
                }
            }

            if let styles = appState.profile?.stylePreferences, !styles.isEmpty {
                Text(styles.joined(separator: "  ·  "))
                    .font(Theme.label)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
            } else {
                Text("Add your style preferences to personalize your feed.")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Color.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }

            ViewThatFits(in: .horizontal) {
                countCapsules(spacing: 8, horizontal: true)
                countCapsules(spacing: 8, horizontal: false)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: Self.heroRadius, style: .continuous))
        .elevatedShadow()
    }

    @ViewBuilder
    private func countCapsules(spacing: CGFloat, horizontal: Bool) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: spacing)) : AnyLayout(VStackLayout(spacing: spacing))
        layout {
            countCapsule("\(liveVotes.count + archivedVotes.count)", label: "Fit-Checks")
            Button { selectedFollowList = .followers } label: {
                countCapsule("\(followerIDs.count)", label: "Followers")
            }
            .buttonStyle(.plain)
            Button { selectedFollowList = .following } label: {
                countCapsule("\(followingIDs.count)", label: "Following")
            }
            .buttonStyle(.plain)
        }
    }

    private static let heroRadius: CGFloat = 28

    /// Opaque-feeling dark capsule over the gradient so white text stays >= 4.5:1.
    private func countCapsule(_ value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(Theme.headline)
            Text(label).font(Theme.micro).fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
        .background(Color.black.opacity(0.35), in: Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func profileShortcut<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(Theme.headline)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .elevatedCard(radius: Theme.tileRadius, padding: 14)
            .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title == "Your week" ? "yourWeekButton" : "profileShortcut_\(title)")
    }

    @ViewBuilder
    private func votesSection(title: String, items: [MyFitCheck], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Theme.micro).foregroundStyle(Theme.mutedForeground)
            if items.isEmpty {
                Text(emptyText)
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            } else {
                VStack(spacing: 16) {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            RemoteImage(url: item.thumbnailURL ?? "")
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                            NavigationLink {
                                FitCheckDetailView(fitCheckId: item.id)
                            } label: {
                                Text(item.caption ?? "Untitled")
                                    .font(Theme.bodyEmphasis)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            if item.status == "live" && !isExpired(item.expiresAt) {
                                Button("Terminate") { terminateTarget = item.id }
                                    .font(Theme.micro)
                                    .foregroundStyle(Theme.accentDeep)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                                    .accessibilityLabel("Terminate \(item.caption ?? "Fit-Check")")
                            }
                            Button("Delete") { deleteTarget = item.id }
                                .font(Theme.micro)
                                .foregroundStyle(Theme.danger)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                                .accessibilityLabel("Delete \(item.caption ?? "Fit-Check")")
                        }
                        .softCard(radius: Theme.tileRadius, padding: 12)
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
    @ScaledMetric(relativeTo: .title2) private var streakIconSize: CGFloat = 28
    @State private var report: WeeklyStyleReport?
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("YOUR WEEK")
                    .font(Theme.micro)
                    .tracking(1.5)
                    .foregroundStyle(Theme.accentDeep)
                Text("Style momentum")
                    .font(Theme.editorialFont(size: 34))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                Text("A quick look at how you showed up this week.")
                    .font(Theme.font(.subheadline))
                    .foregroundStyle(Theme.mutedForeground)

                AsyncStateView(isLoading: isLoading, error: error, topPadding: 16, hasLoaded: hasLoaded, retry: { await load() }) {
                    if let report {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 14) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: streakIconSize, weight: .bold))
                                    .foregroundStyle(Theme.iconCoral)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(report.currentStreak)-day streak")
                                        .font(Theme.title)
                                        .foregroundStyle(Theme.ink)
                                    Text(report.currentStreak == 0 ? "Start with one small style action today." : "Keep the momentum going.")
                                        .font(Theme.font(.caption))
                                        .foregroundStyle(Theme.mutedForeground)
                                }
                                Spacer()
                            }
                            .accessibilityElement(children: .combine)
                            .softCard()

                            LazyVGrid(columns: columns, spacing: 12) {
                                metric("Votes", value: report.votesCast, icon: "hand.thumbsup.fill")
                                metric("Fit-Checks", value: report.fitChecksPosted, icon: "camera.fill")
                                metric("Comments", value: report.commentsWritten, icon: "bubble.left.fill")
                                metric("New pieces", value: report.wardrobePiecesAdded, icon: "hanger")
                            }

                            if let occasion = report.topOccasion {
                                HStack {
                                    Text("Your top vibe: \(occasion)")
                                        .font(Theme.bodyEmphasis)
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                }
                                .softCard(radius: Theme.tileRadius, padding: 14)
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
        .revisionTask(appState.contentRevision) { await load() }
        .refreshable { await load() }
    }

    private func metric(_ title: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accentDeep)
                .accessibilityHidden(true)
            Text("\(value)")
                .font(Theme.editorialFont(size: 28, relativeTo: .title2))
                .foregroundStyle(Theme.ink)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            Text(title)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .softCard(radius: Theme.tileRadius, padding: 14)
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
struct EditProfileView: View {
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
                        .font(Theme.micro)
                        .foregroundStyle(Theme.mutedForeground)
                    FlowLayout(spacing: 8) {
                        ForEach(Self.styleOptions, id: \.self) { style in
                            ChipToggle(label: style, selected: styles.contains(style)) {
                                if styles.contains(style) { styles.remove(style) }
                                else { styles.insert(style) }
                            }
                        }
                    }
                    if let error { Text(error).font(Theme.label).foregroundStyle(Theme.danger) }
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
