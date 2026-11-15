import SwiftUI

/// Overflow menu with Report and Block, plus their confirmation dialogs.
/// Same actions and copy as the swipe page's action rail.
struct VoteFanSafetyMenu: View {
    let fitCheckId: UUID
    let creatorId: UUID

    @State private var showingReportReasons = false
    @State private var showingBlockConfirmation = false
    @State private var safetyMessage: String?

    private static let reportReasons = [
        ("Inappropriate content", "inappropriate"), ("Harassment or bullying", "harassment"),
        ("Spam", "spam"), ("Other", "other")
    ]

    var body: some View {
        Menu {
            Button("Report Fit-Check", systemImage: "flag") { showingReportReasons = true }
            Button("Block creator", systemImage: "person.slash", role: .destructive) { showingBlockConfirmation = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.55), in: Circle())
                .frame(minWidth: FeedLayout.minHitSize, minHeight: FeedLayout.minHitSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Report or block")
        .accessibilityIdentifier("voteFanMenu")
        .confirmationDialog("Why are you reporting this?", isPresented: $showingReportReasons, titleVisibility: .visible) {
            ForEach(Self.reportReasons, id: \.1) { reason in
                Button(reason.0) { Task { await report(reason: reason.1) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Block this creator?", isPresented: $showingBlockConfirmation, titleVisibility: .visible) {
            Button("Block creator", role: .destructive) { Task { await blockCreator() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won’t see their Fit-Checks anymore.")
        }
        .alert("Thanks", isPresented: Binding(get: { safetyMessage != nil }, set: { if !$0 { safetyMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(safetyMessage ?? "") }
    }

    private func report(reason: String) async {
        do {
            try await API.reportFitCheck(id: fitCheckId, reason: reason)
            safetyMessage = "Your report was submitted for review."
        } catch {
            safetyMessage = "We couldn’t submit the report. Please try again."
        }
    }

    private func blockCreator() async {
        do {
            try await API.blockUser(id: creatorId)
            safetyMessage = "Creator blocked. Their content will be removed from your feed after refresh."
        } catch {
            safetyMessage = "We couldn’t block this creator. Please try again."
        }
    }
}
