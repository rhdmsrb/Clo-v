import SwiftUI
import Supabase

/// Shown after the user follows a password-reset email link.
struct NewPasswordView: View {
    @EnvironmentObject private var appState: AppState
    @State private var password = ""
    @State private var error: String?
    @State private var isSaving = false

    private var canSave: Bool { password.count >= 6 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("CLO·V")
                    .font(.system(.title3, weight: .heavy))

                VStack(alignment: .leading, spacing: 6) {
                    Text("New password")
                        .font(Theme.editorialFont(size: 38))
                    Text("Choose a new password for your account.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                }

                LabeledField(label: "NEW PASSWORD") {
                    SecureField("", text: $password)
                        .textContentType(.newPassword)
                        .submitLabel(.go)
                        .onSubmit {
                            guard canSave else { return }
                            Task { await save() }
                        }
                }

                if !password.isEmpty && !canSave {
                    Text("Use at least 6 characters.")
                        .font(.footnote)
                        .foregroundStyle(Theme.mutedForeground)
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                }

                Button {
                    Task { await save() }
                } label: {
                    Text(isSaving ? "Please wait…" : "Save password")
                }
                .buttonStyle(PrimaryButtonStyle(isDisabled: isSaving || !canSave))
                .disabled(isSaving || !canSave)

                Button("Cancel") {
                    Task { await appState.signOut() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
            }
            .padding(24)
        }
        .background(Theme.background)
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            _ = try await SupabaseManager.client.auth.update(user: UserAttributes(password: password))
            appState.isRecoveringPassword = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
