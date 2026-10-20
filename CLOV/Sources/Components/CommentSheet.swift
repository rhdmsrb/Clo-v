import SwiftUI

/// Quick "what stood out" tags shared by the comment sheet and the quick-reaction bar.
enum VoteReason {
    static let options = ["Love the colors", "Comfy", "Fits the occasion", "Great layers", "Shoes work", "Feels like you"]
}

/// Post-vote sheet asking why the voter picked a look.
struct CommentSheet: View {
    @EnvironmentObject private var appState: AppState

    let fitCheckId: UUID
    let photoId: UUID
    let voterId: UUID
    let onClose: () -> Void

    @State private var commentBody = ""
    @State private var reasonTags: Set<String> = []
    @State private var savedReasonKey: String?
    @State private var isCommenting = false
    @State private var commentPosted = false
    @State private var commentError: String?

    private static let maxCommentLength = 280
    private static let closeDelay: Duration = .milliseconds(700)
    private static let tagMinimumWidth: CGFloat = 140
    private static let postedMessage = "Feedback saved"

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var editorMinHeight: CGFloat = 90

    var body: some View {
        Group {
            if commentPosted {
                postedConfirmation
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) { form }
                        .padding(24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(12)
        .presentationBackground(Theme.card)
        .interactiveDismissDisabled(isCommenting)
        .sensoryFeedback(.success, trigger: commentPosted) { _, new in new }
    }

    private var postedConfirmation: some View {
        Text(Self.postedMessage)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(24)
            .padding(.vertical, 20)
    }

    @ViewBuilder
    private var form: some View {
        Text("WHY DID YOU VOTE THIS WAY?")
            .font(Theme.displayFont)
            .accessibilityAddTraits(.isHeader)
        Text("Tell the poster what stood out to you (optional).")
            .font(.subheadline)
            .foregroundStyle(Theme.mutedForeground)
        Text("People see overall results. If you leave a note, it will show your name.")
            .font(.caption)
            .foregroundStyle(Theme.mutedForeground)
        TextEditor(text: $commentBody)
            .frame(minHeight: editorMinHeight)
            .padding(8)
            .background(Theme.muted)
            .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                .stroke(Theme.controlBorder, lineWidth: 1))
            .accessibilityLabel("Comment")
            .accessibilityHint("Optional note for the poster, up to \(Self.maxCommentLength) characters")
            .onChange(of: commentBody) { _, newValue in
                if newValue.count > Self.maxCommentLength {
                    commentBody = String(newValue.prefix(Self.maxCommentLength))
                }
            }
        Text("\(commentBody.count)/\(Self.maxCommentLength)")
            .font(.caption2)
            .foregroundStyle(commentBody.count == Self.maxCommentLength ? Theme.accent : Theme.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .trailing)
        Text("WHAT STOOD OUT?")
            .font(Theme.micro)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
        tagGrid
        if let commentError {
            Text(commentError).font(.caption).foregroundStyle(Theme.danger)
        }
        actions
    }

    private var tagGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tagMinimumWidth), spacing: 8)], spacing: 8) {
            ForEach(VoteReason.options, id: \.self) { option in
                let isSelected = reasonTags.contains(option)
                Button {
                    reasonTags = isSelected ? reasonTags.subtracting([option]) : reasonTags.union([option])
                } label: {
                    Text(option)
                }
                .buttonStyle(ChipButtonStyle(isSelected: isSelected, expands: true))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var actions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button("Skip", action: onClose)
                .buttonStyle(OutlineButtonStyle())
                .disabled(isCommenting)
            Button(isCommenting ? "Posting…" : "Save feedback") { Task { await post() } }
                .buttonStyle(PrimaryButtonStyle(isDisabled: isCommenting))
                .disabled(isCommenting)
        }
    }

    private func post() async {
        guard !isCommenting else { return }
        isCommenting = true
        commentError = nil
        defer { isCommenting = false }
        do {
            // Skip the reason write on retry; only the comment failed before.
            let reasonKey = (reasonTags.sorted() + [commentBody]).joined(separator: "\u{1F}")
            if savedReasonKey != reasonKey {
                try await API.saveVoteReason(fitCheckId: fitCheckId, photoId: photoId, tags: Array(reasonTags), comment: commentBody)
                savedReasonKey = reasonKey
            }
            if !commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await API.addComment(fitCheckId: fitCheckId, photoId: photoId, commenterId: voterId, body: commentBody)
                appState.contentDidChange()
            }
            commentPosted = true
            AccessibilityNotification.Announcement(Self.postedMessage).post()
            try? await Task.sleep(for: Self.closeDelay)
            onClose()
        } catch {
            let message = friendlyMessage(for: error, fallback: "Couldn’t save your feedback. Please try again.")
            commentError = message
            AccessibilityNotification.Announcement(message).post()
        }
    }
}
