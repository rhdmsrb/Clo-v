import SwiftUI
import Supabase

struct AuthView: View {
    @EnvironmentObject private var appState: AppState

    private enum Mode {
        case signIn, signUp

        var title: String { self == .signIn ? "Log in" : "Sign up" }
        var subtitle: String {
            self == .signIn
                ? "Welcome back."
                : "Create an account to start posting Fit-Checks."
        }
        var switchPrompt: String {
            self == .signIn ? "No account? Sign up" : "Already have an account? Log in"
        }
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isSubmitting = false
    @State private var checkEmailNotice = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("CLO·V")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))

                VStack(alignment: .leading, spacing: 6) {
                    Text(mode.title)
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    Text(mode.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                }

                if checkEmailNotice {
                    Text("Check your email to confirm your account, then log in.")
                        .font(.subheadline)
                        .padding(14)
                        .background(Theme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 16) {
                    LabeledField(label: "EMAIL") {
                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    LabeledField(label: "PASSWORD") {
                        SecureField("", text: $password)
                            .textContentType(mode == .signIn ? .password : .newPassword)
                    }
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Text(isSubmitting ? "Please wait…" : mode.title)
                }
                .buttonStyle(PrimaryButtonStyle(isDisabled: isSubmitting))
                .disabled(isSubmitting)

                Button {
                    mode = mode == .signIn ? .signUp : .signIn
                    error = nil
                    checkEmailNotice = false
                } label: {
                    Text(mode.switchPrompt)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity)


            }
            .padding(24)
        }
        .background(Theme.background)
    }

    private func submit() async {
        error = nil
        checkEmailNotice = false

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        if trimmedEmail == "1", password == "1" {
            error = "Use your real account to log in. The old 1 / 1 shortcut cannot save your profile."
            return
        }


        guard !trimmedEmail.isEmpty, password.count >= 6 else {
            error = "Enter a valid email and a password of at least 6 characters."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            switch mode {
            case .signIn:
                // A successful call updates the session internally;
                // AppState's auth-state listener picks it up and routes
                // on automatically — nothing to do here but wait.
                try await SupabaseManager.client.auth.signIn(email: trimmedEmail, password: password)
            case .signUp:
                let response = try await SupabaseManager.client.auth.signUp(email: trimmedEmail, password: password)
                if case .user = response {
                    // No session yet — email confirmation is required.
                    checkEmailNotice = true
                    mode = .signIn
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
