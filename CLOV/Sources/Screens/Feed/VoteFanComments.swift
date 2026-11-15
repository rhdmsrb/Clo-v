import SwiftUI

/// Loads a Fit-Check's comments once and posts new ones. Filtering to the
/// selected photo happens in memory via `PhotoComments.visible`.
@MainActor
final class VoteFanCommentsModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let fitCheckId: UUID
    @Published private(set) var comments: [CommentDTO] = []
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var isPosting = false
    @Published private(set) var postError: String?

    init(fitCheckId: UUID) {
        self.fitCheckId = fitCheckId
    }

    func load() async {
        phase = .loading
        do {
            comments = try await API.fetchComments(fitCheckId: fitCheckId)
            phase = .loaded
        } catch {
            phase = .failed(friendlyMessage(for: error, fallback: "Couldn’t load comments."))
        }
    }

    /// Posts on `photoId`, then refetches. Returns whether the post succeeded.
    func post(body: String, photoId: UUID?, commenterId: UUID) async -> Bool {
        guard CommentThreadSheet.canSend(body), !isPosting else { return false }
        isPosting = true
        postError = nil
        defer { isPosting = false }
        do {
            try await API.addComment(fitCheckId: fitCheckId, photoId: photoId, commenterId: commenterId, body: body)
            comments = (try? await API.fetchComments(fitCheckId: fitCheckId)) ?? comments
            phase = .loaded
            return true
        } catch {
            postError = friendlyMessage(for: error, fallback: "Couldn’t post your comment. Please try again.")
            return false
        }
    }
}

/// Rounded "Comments" panel for the selected photo.
struct VoteFanCommentsPanel: View {
    @ObservedObject var model: VoteFanCommentsModel
    let photoId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comments").font(Theme.font(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardElevated, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityIdentifier("voteFanComments")
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message).font(Theme.body).foregroundStyle(Theme.mutedForeground)
                Button("Try again") { Task { await model.load() } }.buttonStyle(OutlineButtonStyle())
            }
            .frame(maxWidth: .infinity)
        case .loaded:
            loadedList
        }
    }

    @ViewBuilder
    private var loadedList: some View {
        let visible = PhotoComments.visible(model.comments, photoId: photoId)
        if visible.isEmpty {
            Text("No comments on this look yet.")
                .font(Theme.body).foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(visible) { VoteFanCommentRow(comment: $0) }
            }
        }
    }
}

struct VoteFanCommentRow: View {
    let comment: CommentDTO

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(url: comment.profiles?.avatarUrl, nickname: comment.profiles?.nickname, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(comment.profiles?.nickname ?? "Someone").font(Theme.micro).foregroundStyle(Theme.ink)
                Text(comment.body).font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Sticky input row: avatar, field, send. Shows a closed notice when comments are closed.
struct VoteFanCommentInput: View {
    @Binding var draft: String
    let avatarUrl: String?
    let nickname: String?
    let canComment: Bool
    let isPosting: Bool
    let postError: String?
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let postError {
                Text(postError).font(Theme.caption).foregroundStyle(Theme.danger)
            }
            if canComment {
                HStack(spacing: 10) {
                    AvatarView(url: avatarUrl, nickname: nickname, size: 32)
                    TextField("Add a comment on this look", text: $draft, axis: .vertical)
                        .lineLimit(1...3)
                        .focused(isFocused)
                        .font(Theme.body)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                        .onChange(of: draft) { _, new in
                            if new.count > CommentThreadSheet.maxLength {
                                draft = String(new.prefix(CommentThreadSheet.maxLength))
                            }
                        }
                        .accessibilityLabel("Comment")
                        .accessibilityIdentifier("voteFanCommentInput")
                    sendButton
                }
            } else {
                Text("Comments are closed for this Fit-Check.")
                    .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardElevated)
        .overlay(alignment: .top) { Divider() }
    }

    private var sendButton: some View {
        let enabled = CommentThreadSheet.canSend(draft) && !isPosting
        return Button(action: onSend) {
            Image(systemName: "arrow.up.circle.fill").font(.title)
                .foregroundStyle(enabled ? Theme.accent : Theme.mutedForeground)
                .frame(minWidth: 44, minHeight: 44)
        }
        .disabled(!enabled)
        .accessibilityLabel("Post comment")
        .accessibilityIdentifier("voteFanCommentSend")
    }
}
