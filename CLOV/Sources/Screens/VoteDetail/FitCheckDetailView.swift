import SwiftUI

/// Value pushed via `NavigationLink(value:)` to open `FitCheckDetailView`.
/// A dedicated type rather than a bare `UUID` — `GroupsView` already
/// registers `.navigationDestination(for: UUID.self)` for *group* ids on
/// the Groups tab's NavigationStack, and `GroupDetailView` (pushed from
/// there) also shows fit-check cards. A raw `UUID.self` destination for
/// fit-checks would collide with that registration and open the wrong
/// screen — see `GroupDetailView`'s own `FitCheckRoute` registration.
struct FitCheckRoute: Hashable {
    let id: UUID
}

struct FitCheckDetailView: View {
    let fitCheckId: UUID
    @EnvironmentObject private var appState: AppState
    @Environment(\.tabBarClearance) private var tabBarClearance

    @State private var detail: FitCheckDetailDTO?
    @State private var votes: [VoteRef] = []
    @State private var comments: [CommentDTO] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var showingReportReasons = false
    @State private var showingBlockConfirmation = false
    @State private var safetyMessage: String?

    private var voteCounts: [UUID: Int] {
        Dictionary(grouping: votes, by: \.photoId).mapValues(\.count)
    }
    private var myVote: UUID? {
        votes.first(where: { $0.voterId == appState.userId })?.photoId
    }

    private static let pagePadding: CGFloat = 20
    private static let sectionSpacing: CGFloat = 20
    private static let displayMinScale: CGFloat = 0.7

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                AsyncStateView(isLoading: isLoading, error: error, topPadding: 60,
                               hasLoaded: hasLoaded, retry: { await load() }) {
                    if let detail { loadedContent(detail) }
                }
            }
            .padding(Self.pagePadding)
        }
        .safeAreaPadding(.bottom, tabBarClearance)
        .background(Theme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Report Fit-Check", systemImage: "flag") {
                        showingReportReasons = true
                    }
                    if detail?.creatorId != appState.userId {
                        Button("Block creator", systemImage: "person.slash", role: .destructive) {
                            showingBlockConfirmation = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Report or block")
            }
        }
        .confirmationDialog("Why are you reporting this?", isPresented: $showingReportReasons, titleVisibility: .visible) {
            ForEach(ReportReason.all) { reason in
                Button(reason.title) { Task { await report(reason: reason.value) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Block this creator?", isPresented: $showingBlockConfirmation, titleVisibility: .visible) {
            Button("Block creator", role: .destructive) { Task { await blockCreator() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see their content or receive new friend requests from them.")
        }
        .alert("Safety action", isPresented: Binding(get: { safetyMessage != nil }, set: { if !$0 { safetyMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(safetyMessage ?? "")
        }
        .task(id: appState.contentRevision) { await load() }
        .refreshable { await load() }
    }

    // MARK: Sections

    @ViewBuilder
    private func loadedContent(_ detail: FitCheckDetailDTO) -> some View {
        let expired = isExpired(detail.expiresAt)
        header(detail, expired: expired)
        creatorRow(detail)
        statusStrip(for: detail, expired: expired)
        if let summary = heroSummary(detail, expired: expired) { summary }

        if expired {
            if detail.creatorId == appState.userId {
                Text("Voting has ended. Your results are saved here for you.")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.mutedForeground)
                votingSection(detail, myVote: nil)
            } else {
                VotingEndedView()
            }
        } else {
            if let caption = detail.caption, !caption.isEmpty {
                Text(caption).font(Theme.bodyEmphasis).foregroundStyle(Theme.mutedForeground)
            }
            votingSection(detail, myVote: myVote)
            if detail.status == "archived" {
                Text("This Fit-Check has ended — voting is closed.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity)
            }
            commentsSection
        }
    }

    private func votingSection(_ detail: FitCheckDetailDTO, myVote: UUID?) -> some View {
        VotingPhotoGridView(
            fitCheckId: detail.id,
            creatorId: detail.creatorId,
            status: detail.status,
            photos: detail.fitCheckPhotos,
            voteCounts: voteCounts,
            totalVotes: votes.count,
            myVote: myVote,
            voterId: appState.userId,
            expiresAt: detail.expiresAt,
            prompt: detail.votePrompt,
            isPublicPost: detail.isPublic == true
        )
        .elevatedCard()
    }

    private func header(_ detail: FitCheckDetailDTO, expired: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FIT CHECK / \((expired ? "ENDED" : detail.status).uppercased())")
                    .font(Theme.micro)
                    .tracking(1.4)
                    .foregroundStyle(Theme.accentDeep)
                Text("The edit")
                    .font(Theme.editorialFont(size: 40))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(Self.displayMinScale)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            if !expired {
                ShareLinkButton(fitCheckId: detail.id, title: "Share Fit-Check", summary: shareSummary)
            }
        }
    }

    private func creatorRow(_ detail: FitCheckDetailDTO) -> some View {
        HStack(spacing: 10) {
            AvatarView(url: detail.profiles?.avatarUrl, nickname: detail.profiles?.nickname, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.profiles?.nickname ?? "Someone")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                Text("From the circle")
                    .font(Theme.micro)
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Winner summary. Only shown when the result is visible to this viewer,
    /// so it never spoils an undecided vote.
    private func heroSummary(_ detail: FitCheckDetailDTO, expired: Bool) -> AnyView? {
        let isCreator = detail.creatorId == appState.userId
        guard !votes.isEmpty, isCreator || (!expired && myVote != nil) else { return nil }
        let leading = voteCounts.values.max() ?? 0
        let percent = Int((Double(leading) / Double(votes.count) * 100).rounded())
        let card = HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(percent)%")
                .font(Theme.editorialFont(size: 44))
                .lineLimit(1)
                .minimumScaleFactor(Self.displayMinScale)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            VStack(alignment: .leading, spacing: 2) {
                Label("Leading look", systemImage: "crown.fill").font(Theme.label)
                Text("\(votes.count) \(votes.count == 1 ? "vote" : "votes")").font(Theme.caption)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.white)
        .padding(Self.pagePadding)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .layeredShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Leading look has \(percent) percent of \(votes.count) \(votes.count == 1 ? "vote" : "votes")")
        return AnyView(card)
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Notes from the circle")
            if comments.isEmpty {
                Text("No comments yet — vote to leave the first one.")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.mutedForeground)
            } else {
                ForEach(comments) { comment in commentRow(comment) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }

    private func commentRow(_ comment: CommentDTO) -> some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(url: comment.profiles?.avatarUrl, nickname: comment.profiles?.nickname, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(comment.profiles?.nickname ?? "Someone")
                    .font(Theme.micro)
                    .foregroundStyle(Theme.ink)
                Text(comment.body).font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func statusStrip(for detail: FitCheckDetailDTO, expired: Bool) -> some View {
        HStack {
            Label(expired ? "Closed" : "Open for votes", systemImage: expired ? "lock.fill" : "circle.fill")
                .font(Theme.label)
            Spacer()
            if let expiresAt = detail.expiresAt, !expired {
                Text(RelativeDateTimeFormatter().localizedString(for: expiresAt, relativeTo: Date()))
                    .font(Theme.caption)
            } else {
                Text("\(votes.count) \(votes.count == 1 ? "vote" : "votes")")
                    .font(Theme.caption)
            }
        }
        .foregroundStyle(Theme.accentForeground)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.accent, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var shareSummary: String {
        let total = votes.count
        guard total > 0 else { return "Help me choose my outfit on CLO·V." }
        let leading = voteCounts.values.max() ?? 0
        let percentage = Int((Double(leading) / Double(total) * 100).rounded())
        return "My Fit-Check is at \(percentage)% for the leading look (\(total) vote\(total == 1 ? "" : "s"))."
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let detailTask = API.fetchFitCheckDetail(id: fitCheckId)
            async let votesTask = API.fetchVotes(fitCheckId: fitCheckId)
            async let commentsTask = API.fetchComments(fitCheckId: fitCheckId)
            let loaded = try await (detailTask, votesTask, commentsTask)
            try Task.checkCancellation()
            detail = loaded.0
            votes = loaded.1
            comments = loaded.2
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load this content. Please try again."
        }
    }

    private func report(reason: String) async {
        do {
            try await API.reportFitCheck(id: fitCheckId, reason: reason)
            safetyMessage = "Thanks. Your report was submitted for review."
        } catch {
            safetyMessage = "We couldn't submit the report. Please try again."
        }
    }

    private func blockCreator() async {
        guard let creatorId = detail?.creatorId else { return }
        do {
            try await API.blockUser(id: creatorId)
            safetyMessage = "Creator blocked. Their content will be removed from your feed after refresh."
        } catch {
            safetyMessage = "We couldn't block this creator. Please try again."
        }
    }
}
