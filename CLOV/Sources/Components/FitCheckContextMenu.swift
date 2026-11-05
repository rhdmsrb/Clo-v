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

/// Long-press menu for a Fit-Check card: share, copy the link, follow, report
/// and block. Everything here is also reachable elsewhere in the app; this is
/// the quick path. Report and block are hidden on the viewer's own posts.
private struct FitCheckContextMenu: ViewModifier {
    let fitCheckId: UUID
    let creatorId: UUID
    let posterName: String
    let viewerId: UUID
    let isFollowing: Bool
    let onToggleFollow: ((Bool) -> Void)?

    @EnvironmentObject private var appState: AppState
    @State private var showingBlockConfirmation = false
    @State private var safetyMessage: String?

    private var isOwnPost: Bool { creatorId == viewerId }

    func body(content: Content) -> some View {
        content
            .contextMenu { menuItems }
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

    @ViewBuilder
    private var menuItems: some View {
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
                    Button(reason.title) { Task { await report(reason) } }
                }
            }
            Button("Block \(posterName)", systemImage: "person.slash", role: .destructive) {
                showingBlockConfirmation = true
            }
        }
    }

    private func report(_ reason: ReportReason) async {
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
