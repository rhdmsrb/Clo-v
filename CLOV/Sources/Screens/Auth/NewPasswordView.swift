import SwiftUI
import Supabase

/// Shown after the user follows a password-reset email link.
struct NewPasswordView: View {
    @EnvironmentObject private var appState: AppState
    @State private var password = ""
    @State private var error: String?
    @State private var isSaving = false
    @FocusState private var passwordFocused: Bool

    private var canSave: Bool { password.count >= 6 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AuthHeroBlock(title: "New password", subtitle: "Choose a new password for your account.")
                VStack(alignment: .leading, spacing: 20) {
                    LabeledField(
                        label: "New password",
                        isFocused: passwordFocused,
                        errorMessage: !password.isEmpty && !canSave ? "Use at least 6 characters." : nil
                    ) {
                        SecureField("", text: $password)
                            .textContentType(.newPassword)
                            .focused($passwordFocused)
                            .submitLabel(.go)
                            .onSubmit {
                                guard canSave else { return }
                                Task { await save() }
                            }
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
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
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.accentDeep)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
                }
                .padding(24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollDismissesKeyboard(.interactively)
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
