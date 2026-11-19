import SwiftUI

/// Comments for a Fit-Check: a fan of its photos above the thread and a
/// sticky input row. General comments post without a photo id.
struct CommentThreadSheet: View {
    let fitCheckId: UUID
    let photoURLs: [String]
    let voterId: UUID
    let canComment: Bool
    var onPosted: (([CommentDTO]?) -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [CommentDTO] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var draft = ""
    @State private var isPosting = false
    @State private var postError: String?
    @FocusState private var isInputFocused: Bool
    @State private var detent: PresentationDetent = .fraction(0.58)

    static let maxLength = 280
    private static let fanPhotoWidth: CGFloat = 72
    private static let fanPhotoHeight: CGFloat = 96
    private static let fanOverlap: CGFloat = -28
    private static let fanTilt: Double = 6
    private static let maxFanPhotos = 4

    /// Whether `text` is non-blank and within the length limit.
    static func canSend(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && text.count <= maxLength
    }

    var body: some View {
        VStack(spacing: 0) {
            photoFan
            Divider()
            thread
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { inputRow }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                    .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Close comments")
            .accessibilityIdentifier("comments.close")
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
        // Opens half height so the feed stays visible while skimming; typing
        // needs the room, so focusing the input expands it.
        .presentationDetents([.fraction(0.58), .large], selection: $detent)
        .onChange(of: isInputFocused) { _, focused in
            if focused { detent = .large }
        }
        .presentationCornerRadius(32)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.cardElevated)
        .task { await load() }
    }

    // MARK: Photo fan

    @ViewBuilder
    private var photoFan: some View {
        let shown = Array(photoURLs.prefix(Self.maxFanPhotos))
        if !shown.isEmpty {
            HStack(spacing: Self.fanOverlap) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, url in
                    RemoteImage(url: url)
                        .scaledToFill()
                        .frame(width: Self.fanPhotoWidth, height: Self.fanPhotoHeight)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                            .stroke(Theme.cardElevated, lineWidth: 2))
                        .rotationEffect(.degrees((Double(index) - Double(shown.count - 1) / 2) * Self.fanTilt))
                        .zIndex(Double(index))
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(photoURLs.count) \(photoURLs.count == 1 ? "photo" : "photos") in this Fit-Check")
            .accessibilityIdentifier("voteFanComments")
        }
    }

    // MARK: Thread

    @ViewBuilder
    private var thread: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            VStack(spacing: 10) {
                Text(loadError).font(Theme.body).foregroundStyle(Theme.mutedForeground)
                Button("Try again") { Task { await load() } }.buttonStyle(OutlineButtonStyle())
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if comments.isEmpty {
            Text("No comments yet. Start the conversation.")
                .font(Theme.body).foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(comments) { commentRow($0) }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func commentRow(_ comment: CommentDTO) -> some View {
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

    // MARK: Input

    private var inputRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let postError {
                Text(postError).font(Theme.caption).foregroundStyle(Theme.danger)
            }
            if canComment {
                HStack(spacing: 10) {
                    AvatarView(url: appState.profile?.avatarUrl, nickname: appState.profile?.nickname, size: 30)
                        .accessibilityHidden(true)
                    TextField("Add a comment", text: $draft, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($isInputFocused)
                        .font(Theme.body)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                        .onChange(of: draft) { _, new in
                            if new.count > Self.maxLength { draft = String(new.prefix(Self.maxLength)) }
                        }
                        .accessibilityLabel("Comment")
                        .accessibilityIdentifier("voteFanCommentInput")
                    Button { Task { await post() } } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title)
                            .foregroundStyle(Self.canSend(draft) ? Theme.accent : Theme.mutedForeground)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(!Self.canSend(draft) || isPosting)
                    .accessibilityLabel("Post comment")
                    .accessibilityIdentifier("voteFanCommentSend")
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

    // MARK: Actions

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            comments = try await API.fetchComments(fitCheckId: fitCheckId)
        } catch {
            loadError = friendlyMessage(for: error, fallback: "Couldn’t load comments.")
        }
    }

    private func post() async {
        guard Self.canSend(draft), !isPosting else { return }
        isPosting = true
        postError = nil
        defer { isPosting = false }
        do {
            try await API.addComment(fitCheckId: fitCheckId, commenterId: voterId, body: draft)
            draft = ""
            isInputFocused = false
            let updated = try? await API.fetchComments(fitCheckId: fitCheckId)
            if let updated { comments = updated }
            appState.contentDidChange()
            onPosted?(updated)
        } catch {
            postError = friendlyMessage(for: error, fallback: "Couldn’t post your comment. Please try again.")
        }
    }
}
