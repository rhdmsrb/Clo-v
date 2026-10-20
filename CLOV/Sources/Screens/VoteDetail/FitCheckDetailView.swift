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

    @State private var detail: FitCheckDetailDTO?
    @State private var votes: [VoteRef] = []
    @State private var comments: [CommentDTO] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var showingReportReasons = false
    @State private var showingBlockConfirmation = false
    @State private var safetyMessage: String?

    private struct ReportReason: Identifiable {
        let title: String
        let value: String
        var id: String { value }
    }

    private let reportReasons = [
        ReportReason(title: "Inappropriate content", value: "inappropriate"),
        ReportReason(title: "Harassment or bullying", value: "harassment"),
        ReportReason(title: "Spam", value: "spam"),
        ReportReason(title: "Other", value: "other")
    ]

    private var voteCounts: [UUID: Int] {
        Dictionary(grouping: votes, by: \.photoId).mapValues(\.count)
    }
    private var myVote: UUID? {
        votes.first(where: { $0.voterId == appState.userId })?.photoId
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncStateView(isLoading: isLoading, error: error, topPadding: 60,
                               hasLoaded: hasLoaded, retry: { await load() }) {
                    if let detail {
                        let expired = isExpired(detail.expiresAt)

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("FIT CHECK / \((expired ? "ENDED" : detail.status).uppercased())")
                                    .font(.system(.caption2, design: .default).weight(.black))
                                    .tracking(1.4)
                                    .foregroundStyle(Theme.accent)
                                Text("The edit")
                                    .font(.system(size: 40, weight: .black, design: .default))
                            }
                            Spacer()
                            if !expired {
                                ShareLinkButton(
                                    fitCheckId: detail.id,
                                    title: "Share Fit-Check",
                                    summary: shareSummary
                                )
                            }
                        }

                        HStack(spacing: 10) {
                            AvatarView(url: detail.profiles?.avatarUrl, nickname: detail.profiles?.nickname, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(detail.profiles?.nickname ?? "Someone")
                                    .textCase(.uppercase)
                                    .font(.system(.subheadline, design: .default).weight(.black))
                                Text("FROM THE CIRCLE")
                                    .font(.system(.caption2, design: .default).weight(.bold))
                                    .tracking(0.8)
                                    .foregroundStyle(Theme.mutedForeground)
                            }
                        }
                        .accessibilityElement(children: .combine)

                        statusStrip(for: detail, expired: expired)

                        if expired {
                            if detail.creatorId == appState.userId {
                                Text("Voting has ended. Your results are saved here for you.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.mutedForeground)
                                VotingPhotoGridView(
                                    fitCheckId: detail.id,
                                    creatorId: detail.creatorId,
                                    status: detail.status,
                                    photos: detail.fitCheckPhotos,
                                    voteCounts: voteCounts,
                                    totalVotes: votes.count,
                                    myVote: nil,
                                    voterId: appState.userId,
                                    expiresAt: detail.expiresAt,
                                    prompt: detail.votePrompt
                                )
                            } else {
                                VotingEndedView()
                            }
                        } else {
                            if let caption = detail.caption, !caption.isEmpty {
                                Text(caption).font(.subheadline).foregroundStyle(Theme.mutedForeground)
                            }

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
                                prompt: detail.votePrompt
                            )

                            if detail.status == "archived" {
                                Text("This Fit-Check has ended — voting is closed.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.mutedForeground)
                                    .frame(maxWidth: .infinity)
                            }

                        Text("NOTES FROM THE CIRCLE")
                            .font(.system(.caption2, design: .default).weight(.black))
                            .tracking(1.2)
                            .foregroundStyle(Theme.accent)

                            if comments.isEmpty {
                                Text("No comments yet — vote to leave the first one.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.mutedForeground)
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(comments) { comment in
                                        HStack(alignment: .top, spacing: 8) {
                                            AvatarView(url: comment.profiles?.avatarUrl, nickname: comment.profiles?.nickname, size: 28)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(comment.profiles?.nickname ?? "Someone")
                                                    .font(.system(.caption2, design: .default).weight(.black))
                                                Text(comment.body).font(.subheadline)
                                            }
                                        .padding(.horizontal, 12).padding(.vertical, 10)
                                        .background(Theme.card)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Theme.line.opacity(0.2), lineWidth: 1))
                                        }
                                        .accessibilityElement(children: .combine)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
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
            ForEach(reportReasons) { reason in
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

    private func statusStrip(for detail: FitCheckDetailDTO, expired: Bool) -> some View {
        HStack {
            Text(expired ? "CLOSED" : "OPEN FOR VOTES")
                .font(.system(.caption2, design: .default).weight(.black))
                .tracking(0.9)
            Spacer()
            if let expiresAt = detail.expiresAt, !expired {
                Text(RelativeDateTimeFormatter().localizedString(for: expiresAt, relativeTo: Date()).uppercased())
                    .font(.system(.caption2, design: .default).weight(.bold))
            } else {
                Text("\(votes.count) VOTES")
                    .font(.system(.caption2, design: .default).weight(.bold))
            }
        }
        .foregroundStyle(Theme.inverseText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.ink)
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
