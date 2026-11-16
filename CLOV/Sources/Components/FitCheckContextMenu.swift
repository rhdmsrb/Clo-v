import SwiftUI

/// Why someone is reporting a Fit-Check. Shared by every place that offers
/// reporting so the choices (and the values the backend receives) stay identical.
struct ReportReason: Identifiable {
    let title: String
    let value: String
    var id: String { value }

    static let all = [
        ReportReason(title: "Inappropriate content", value: "inappropriate"),
        ReportReason(title: "Harassment or bullying", value: "harassment"),
        ReportReason(title: "Spam", value: "spam"),
        ReportReason(title: "Other", value: "other")
    ]
}

/// What the menu offers for one Fit-Check. Shared by the long-press menu and
/// the visible "…" button so the two never drift apart.
private struct FitCheckMenuItems: View {
    let fitCheckId: UUID
    let creatorId: UUID
    let posterName: String
    let viewerId: UUID
    let isFollowing: Bool
    let onToggleFollow: ((Bool) -> Void)?
    let onReport: (ReportReason) -> Void
    let onBlock: () -> Void

    private var isOwnPost: Bool { creatorId == viewerId }

    var body: some View {
        if let url = ShareURL.make(fitCheckId: fitCheckId) {
            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
            Button("Copy link", systemImage: "link") { UIPasteboard.general.url = url }
        }
        if !isOwnPost {
            if let onToggleFollow {
                Button(isFollowing ? "Unfollow \(posterName)" : "Follow \(posterName)",
                       systemImage: isFollowing ? "person.badge.minus" : "person.badge.plus") {
                    onToggleFollow(!isFollowing)
                }
            }
            Menu("Report", systemImage: "flag") {
                ForEach(ReportReason.all) { reason in
                    Button(reason.title) { onReport(reason) }
                }
            }
            Button("Block \(posterName)", systemImage: "person.slash", role: .destructive, action: onBlock)
        }
    }
}

/// Block confirmation, result alert, and the report/block calls behind them.
private struct FitCheckSafetyDialogs: ViewModifier {
    let fitCheckId: UUID
    let creatorId: UUID
    let posterName: String
    @Binding var showingBlockConfirmation: Bool
    @Binding var safetyMessage: String?

    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Block \(posterName)?", isPresented: $showingBlockConfirmation, titleVisibility: .visible) {
                Button("Block \(posterName)", role: .destructive) { Task { await block() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You won't see their content or receive new friend requests from them.")
            }
            .alert("Safety action", isPresented: Binding(get: { safetyMessage != nil }, set: { if !$0 { safetyMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(safetyMessage ?? "")
            }
    }

    func report(_ reason: ReportReason) async {
        do {
            try await API.reportFitCheck(id: fitCheckId, reason: reason.value)
            Haptics.success()
            safetyMessage = "Thanks. Your report was submitted for review."
        } catch {
            Haptics.error()
            safetyMessage = "We couldn't submit the report. Please try again."
        }
    }

    private func block() async {
        do {
            try await API.blockUser(id: creatorId)
            Haptics.success()
            // Reload feeds so their Fit-Checks drop out right away.
            appState.contentDidChange()
            safetyMessage = "\(posterName) is blocked. You can unblock them any time in Settings."
        } catch {
            Haptics.error()
            safetyMessage = "We couldn't block \(posterName). Please try again."
        }
    }
}

/// Long-press menu for a Fit-Check card: share, copy the link, follow, report
/// and block. Report and block are hidden on the viewer's own posts.
private struct FitCheckContextMenu: ViewModifier {
    let fitCheckId: UUID
    let creatorId: UUID
    let posterName: String
    let viewerId: UUID
    let isFollowing: Bool
    let onToggleFollow: ((Bool) -> Void)?

    @State private var showingBlockConfirmation = false
    @State private var safetyMessage: String?

    private var dialogs: FitCheckSafetyDialogs {
        FitCheckSafetyDialogs(fitCheckId: fitCheckId, creatorId: creatorId, posterName: posterName,
                              showingBlockConfirmation: $showingBlockConfirmation, safetyMessage: $safetyMessage)
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                FitCheckMenuItems(
                    fitCheckId: fitCheckId, creatorId: creatorId, posterName: posterName, viewerId: viewerId,
                    isFollowing: isFollowing, onToggleFollow: onToggleFollow,
                    onReport: { reason in Task { await dialogs.report(reason) } },
                    onBlock: { showingBlockConfirmation = true }
                )
            }
            .modifier(dialogs)
    }
}

/// The visible way to reach the long-press menu: an ellipsis button with the
/// same entries, so Report and Block don't depend on discovering a long press.
struct FitCheckMoreMenu: View {
    let fitCheckId: UUID
    let creatorId: UUID
    let posterName: String
    let viewerId: UUID
    let isFollowing: Bool
    let onToggleFollow: ((Bool) -> Void)?

    @State private var showingBlockConfirmation = false
    @State private var safetyMessage: String?

    private var dialogs: FitCheckSafetyDialogs {
        FitCheckSafetyDialogs(fitCheckId: fitCheckId, creatorId: creatorId, posterName: posterName,
                              showingBlockConfirmation: $showingBlockConfirmation, safetyMessage: $safetyMessage)
    }

    var body: some View {
        Menu {
            FitCheckMenuItems(
                fitCheckId: fitCheckId, creatorId: creatorId, posterName: posterName, viewerId: viewerId,
                isFollowing: isFollowing, onToggleFollow: onToggleFollow,
                onReport: { reason in Task { await dialogs.report(reason) } },
                onBlock: { showingBlockConfirmation = true }
            )
        } label: {
            Image(systemName: "ellipsis")
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.ink)
                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options for \(posterName)’s Fit-Check")
        .accessibilityIdentifier("feed-more-button")
        .modifier(dialogs)
    }
}

extension View {
    func fitCheckContextMenu(
        fitCheckId: UUID, creatorId: UUID, posterName: String, viewerId: UUID,
        isFollowing: Bool = false, onToggleFollow: ((Bool) -> Void)? = nil
    ) -> some View {
        modifier(FitCheckContextMenu(
            fitCheckId: fitCheckId, creatorId: creatorId, posterName: posterName, viewerId: viewerId,
            isFollowing: isFollowing, onToggleFollow: onToggleFollow
        ))
    }
}
