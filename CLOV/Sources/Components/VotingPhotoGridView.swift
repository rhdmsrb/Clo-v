import SwiftUI

struct VotingPhotoGridView: View {
    @EnvironmentObject private var appState: AppState
    private let incomingCounts: [UUID: Int]
    private let incomingTotal: Int
    private let incomingVote: UUID?

    let fitCheckId: UUID
    let creatorId: UUID
    let status: String
    let photos: [FitCheckPhoto]
    let voterId: UUID
    let prompt: String?

    @State private var counts: [UUID: Int]
    @State private var total: Int
    @State private var myVote: UUID?
    @State private var error: String?
    @State private var isVoting = false

    @State private var commentPhotoId: UUID?
    @State private var commentBody = ""
    @State private var commentPosted = false
    @State private var isCommenting = false
    @State private var commentError: String?
    @State private var reasonTags: Set<String> = []
    @State private var expandedPhoto: FitCheckPhoto?
    @State private var reactionMessage: String?

    let expiresAt: Date?

    init(fitCheckId: UUID, creatorId: UUID, status: String, photos: [FitCheckPhoto],
         voteCounts: [UUID: Int], totalVotes: Int, myVote: UUID?, voterId: UUID, expiresAt: Date? = nil, prompt: String? = nil) {
        self.fitCheckId = fitCheckId
        self.creatorId = creatorId
        self.status = status
        self.photos = photos.sorted { $0.position < $1.position }
        self.voterId = voterId
        self.prompt = prompt
        self.expiresAt = expiresAt
        incomingCounts = voteCounts
        incomingTotal = totalVotes
        incomingVote = myVote
        _counts = State(initialValue: voteCounts)
        _total = State(initialValue: totalVotes)
        _myVote = State(initialValue: myVote)
    }

    // Callers are expected to check `isExpired(expiresAt)` and render
    // VotingEndedView instead of this view entirely once expired — this
    // flag is a second guard against `vote(on:)` firing on a stale
    // still-mounted grid.
    private var canVote: Bool { status == "live" && creatorId != voterId && !isExpired(expiresAt) }
    private var revealed: Bool { myVote != nil || !canVote }
    private var leadingCount: Int { counts.values.max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(revealed ? "THE RESULT" : "MAKE YOUR PICK")
                .font(.system(.caption2, design: .default).weight(.black))
                .tracking(1.4)
                .foregroundStyle(Theme.accent)

            if let prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                ForEach(photos) { photo in
                    photoTile(photo)
                }
            }
            if let error {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
            if myVote != nil {
                quickReactionBar
            }
            HStack(spacing: 8) {
                if !canVote {
                    Text("YOUR FIT-CHECK")
                        .font(.system(size: 10, weight: .black, design: .default))
                }
                Text("\(total) \(total == 1 ? "vote" : "votes")")
                    .font(.system(.caption2, design: .default).weight(.bold))
            }
            .foregroundStyle(Theme.inverseText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.ink)
        }
        .onChange(of: incomingCounts) { _, _ in syncVotes() }
        .onChange(of: incomingTotal) { _, _ in syncVotes() }
        .onChange(of: incomingVote) { _, _ in syncVotes() }
        .sheet(isPresented: Binding(get: { commentPhotoId != nil }, set: { if !$0 { closeComment() } })) {
            commentSheet
        }
        .fullScreenCover(item: $expandedPhoto) { photo in
            PhotoZoomView(photo: photo)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: myVote) { old, new in old == nil && new != nil }
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: commentPosted) { _, new in new }
    }

    private var quickReactionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("QUICK REACTION")
                .font(.system(.caption2, design: .default).weight(.black))
                .tracking(1.1)
                .foregroundStyle(Theme.mutedForeground)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Self.reasonOptions, id: \.self) { reason in
                        Button(reason) { sendQuickReaction(reason) }
                            .font(.system(.caption2, design: .default).weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Theme.card)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.line.opacity(0.25), lineWidth: 1))
                    }
                }
            }
            if let reactionMessage {
                Text(reactionMessage)
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func sendQuickReaction(_ reason: String) {
        reactionMessage = nil
        guard let photoId = myVote else {
            reactionMessage = "Vote first, then react"
            return
        }
        Task {
            do {
                try await API.saveVoteReason(fitCheckId: fitCheckId, photoId: photoId, tags: [reason], comment: "")
                reactionMessage = "Reaction sent"
            } catch {
                reactionMessage = "Couldn't send reaction"
            }
        }
    }

    @ViewBuilder
    private func photoTile(_ photo: FitCheckPhoto) -> some View {
        let count = counts[photo.id] ?? 0
        let pct = total > 0 ? Int((Double(count) / Double(total) * 100).rounded()) : 0
        let isMine = myVote == photo.id
        let isLeading = revealed && total > 0 && count == leadingCount

        Button {
            vote(on: photo.id)
        } label: {
            AspectFitTile(cornerRadius: 8, shadow: false) {
                RemoteImage(url: photo.imageUrl)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        Text(String(format: "%02d", photo.position + 1))
                            .font(.system(size: 11, weight: .black, design: .default))
                            .foregroundStyle(Theme.inverseText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(Theme.ink)
                    }
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 4) {
                            if revealed {
                                Text("\(pct)%")
                                    .font(.system(size: 17, weight: .black, design: .default))
                                if isLeading {
                                    Text("LEADS")
                                        .font(.system(size: 8, weight: .black, design: .default))
                                        .foregroundStyle(Theme.accent)
                                }
                                if isMine {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .black))
                                }
                            } else {
                                Text("VOTE")
                                    .font(.system(size: 10, weight: .black, design: .default))
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Theme.inverseText)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Theme.ink)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isMine ? Theme.accent : Theme.ink, lineWidth: isMine ? 3 : 1)
            }
        }
        .buttonStyle(TileButtonStyle())
        .disabled(revealed || isVoting)
        .overlay(alignment: .topTrailing) {
            // Zoom is its own control: a double-tap gesture on the tile also
            // fires the tile's vote button on the first tap.
            Button {
                expandedPhoto = photo
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.inverseText)
                    .frame(width: 28, height: 28)
                    .background(Theme.ink.opacity(0.75))
                    .clipShape(Circle())
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom photo \(photo.position + 1)")
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: revealed)
        .accessibilityLabel("Photo \(photo.position + 1)")
        .accessibilityValue(revealed ? "\(pct) percent of votes\(isMine ? ", your vote" : "")" : "Not revealed yet")
        .accessibilityHint(canVote && !revealed ? "Double tap to vote" : "")
    }

    private func vote(on photoId: UUID) {
        guard !revealed, !isVoting else { return }
        error = nil
        isVoting = true
        myVote = photoId // optimistic
        counts[photoId, default: 0] += 1
        total += 1

        Task {
            do {
                try await API.castVote(fitCheckId: fitCheckId, photoId: photoId, voterId: voterId, creatorId: creatorId, status: status, expiresAt: expiresAt)
                isVoting = false
                appState.contentDidChange()
                commentPhotoId = photoId
            } catch {
                self.error = error.localizedDescription
                myVote = nil
                counts[photoId, default: 1] -= 1
                total -= 1
            }
            isVoting = false
        }
    }

    private func syncVotes() {
        guard !isVoting else { return }
        counts = incomingCounts
        total = incomingTotal
        myVote = incomingVote
    }

    private func closeComment() {
        commentPhotoId = nil
        commentBody = ""
        reasonTags = []
        commentPosted = false
        commentError = nil
    }

    private var commentSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            if commentPosted {
                Text("Comment posted 🎉")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                Text("WHY DID YOU VOTE THIS WAY?")
                    .font(Theme.displayFont)
                Text("Tell the poster what stood out to you (optional).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedForeground)
                Text("People see overall results. If you leave a note, it will show your name.")
                    .font(.caption)
                    .foregroundStyle(Theme.mutedForeground)
                TextEditor(text: $commentBody)
                    .frame(height: 90)
                    .padding(8)
                    .background(Theme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onChange(of: commentBody) { _, newValue in
                        if newValue.count > 280 {
                            commentBody = String(newValue.prefix(280))
                        }
                    }
                Text("\(commentBody.count)/280")
                    .font(.caption2)
                    .foregroundStyle(commentBody.count == 280 ? Theme.accent : Theme.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("WHAT STOOD OUT?")
                    .font(.system(.caption2, design: .default).weight(.black))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Self.reasonOptions, id: \.self) { option in
                        Button(option) {
                            if reasonTags.contains(option) { reasonTags.remove(option) } else { reasonTags.insert(option) }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reasonTags.contains(option) ? .white : Color.primary)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(reasonTags.contains(option) ? Theme.accent : Theme.muted)
                        .clipShape(Capsule())
                    }
                }
                if let commentError {
                    Text(commentError).font(.caption).foregroundStyle(.red)
                }
                HStack(spacing: 10) {
                    Button("Skip") { closeComment() }
                        .buttonStyle(OutlineButtonStyle())
                    Button(isCommenting ? "Posting…" : "Save feedback") { postComment() }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: isCommenting))
                        .disabled(isCommenting)
                }
            }
        }
        .padding(24)
        .presentationDetents([.height(510)])
        .presentationCornerRadius(12)
        .presentationBackground(Theme.card)
    }

    private func postComment() {
        guard let commentPhotoId else { return }
        isCommenting = true
        Task {
            do {
                try await API.saveVoteReason(fitCheckId: fitCheckId, photoId: commentPhotoId, tags: Array(reasonTags), comment: commentBody)
                if commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    commentPosted = true
                    try? await Task.sleep(for: .milliseconds(700))
                    closeComment()
                    isCommenting = false
                    return
                }
                try await API.addComment(fitCheckId: fitCheckId, photoId: commentPhotoId, commenterId: voterId, body: commentBody)
                appState.contentDidChange()
                commentPosted = true
                try? await Task.sleep(for: .milliseconds(700))
                closeComment()
            } catch {
                commentError = error.localizedDescription
            }
            isCommenting = false
        }
    }

    private static let reasonOptions = ["Love the colors", "Comfy", "Fits the occasion", "Great layers", "Shoes work", "Feels like you"]
}

private struct PhotoZoomView: View {
    let photo: FitCheckPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Theme.ink.ignoresSafeArea()

                if let imageURL = URL(string: photo.imageUrl), !photo.imageUrl.isEmpty {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .empty:
                            photoPlaceholder(message: "Loading photo…")
                        case .failure:
                            photoPlaceholder(message: "This photo couldn’t be loaded.")
                        @unknown default:
                            photoPlaceholder(message: "This photo couldn’t be loaded.")
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in scale = min(max(value.magnification, 1), 4) }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    scale = min(max(scale, 1), 4)
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            scale = scale > 1 ? 1 : 2
                        }
                    }
                } else {
                    photoPlaceholder(message: "This photo is unavailable.")
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }

                Button("Close", systemImage: "xmark") { dismiss() }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.inverseText)
                    .padding(12)
                    .background(.black.opacity(0.65), in: Circle())
                    .padding()
                    .accessibilityLabel("Close enlarged photo")
            }
        }
        .background(Theme.ink.ignoresSafeArea())
        .statusBarHidden()
    }

    private func photoPlaceholder(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 30, weight: .regular))
            Text(message).font(.subheadline.weight(.medium))
        }
        .foregroundStyle(Theme.inverseText.opacity(0.72))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Scale-down-on-press without the default button dimming — keeps
/// photo tiles reading as photos, not chrome.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// Thin AsyncImage wrapper with a placeholder background.
struct RemoteImage: View {
    let url: String

    var body: some View {
        if let imageURL = URL(string: url) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty:
                    ZStack {
                        Theme.muted
                        ProgressView().tint(Theme.mutedForeground)
                    }
                case .failure:
                    ZStack {
                        Theme.muted
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                @unknown default:
                    Theme.muted
                }
            }
        } else {
            Theme.muted
        }
    }
}
