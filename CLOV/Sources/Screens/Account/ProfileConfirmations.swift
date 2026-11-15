import SwiftUI

/// Delete-account alert plus the end-voting and delete-post confirmations.
struct ProfileConfirmations: ViewModifier {
    @Binding var showDeleteAccount: Bool
    @Binding var terminateTarget: UUID?
    @Binding var deleteTarget: UUID?
    let onDeleteAccount: () -> Void
    let onTerminate: (UUID) -> Void
    let onDelete: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .alert("Delete your account?", isPresented: $showDeleteAccount) {
                Button("Delete account", role: .destructive, action: onDeleteAccount)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your profile, Fit-Checks, photos, votes, comments, friends, and wardrobe items. This can't be undone.")
            }
            .confirmationDialog(
                "End voting on this Fit-Check?",
                isPresented: Binding(get: { terminateTarget != nil }, set: { if !$0 { terminateTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("End voting", role: .destructive) {
                    if let id = terminateTarget { onTerminate(id) }
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
                    if let id = deleteTarget { onDelete(id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes it along with its photos, votes, and comments. This can't be undone.")
            }
    }
}
