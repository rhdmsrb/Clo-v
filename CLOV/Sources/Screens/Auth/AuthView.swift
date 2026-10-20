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

    private enum Field: Hashable {
        case email
        case password
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isSubmitting = false
    @State private var checkEmailNotice = false
    @State private var showingPasswordReset = false
    @State private var resetEmail = ""
    @State private var resetNotice: String?
    @FocusState private var focusedField: Field?

    private var canSubmit: Bool {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.contains("@") && password.count >= 6
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("CLO·V")
                    .font(.system(.title3, weight: .heavy))

                VStack(alignment: .leading, spacing: 6) {
                    Text(mode.title)
                        .font(Theme.editorialFont(size: 38))
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
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                    }
                    LabeledField(label: "PASSWORD") {
                        SecureField("", text: $password)
                            .textContentType(mode == .signIn ? .password : .newPassword)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit {
                                guard canSubmit else { return }
                                Task { await submit() }
                            }
                    }
                    if !password.isEmpty && password.count < 6 {
                        Text("Use at least 6 characters.")
                            .font(.footnote)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                }

                Button {
                    focusedField = nil
                    Task { await submit() }
                } label: {
                    Text(isSubmitting ? "Please wait…" : mode.title)
                }
                .buttonStyle(PrimaryButtonStyle(isDisabled: isSubmitting || !canSubmit))
                .disabled(isSubmitting || !canSubmit)

                Button {
                    mode = mode == .signIn ? .signUp : .signIn
                    error = nil
                    checkEmailNotice = false
                } label: {
                    Text(mode.switchPrompt)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)

                if mode == .signIn {
                    Button("Forgot password?") {
                        resetEmail = email.trimmingCharacters(in: .whitespaces)
                        resetNotice = nil
                        showingPasswordReset = true
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
                }
            }
            .padding(24)
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .sheet(isPresented: $showingPasswordReset) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Reset your password")
                        .font(Theme.editorialFont(size: 29, relativeTo: .title2))
                    Text("We'll send a secure password reset link to your email.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                    TextField("Email", text: $resetEmail)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if let resetNotice {
                        Text(resetNotice)
                            .font(.footnote)
                            .foregroundStyle(resetNotice.hasPrefix("We couldn't") ? Theme.danger : Theme.mutedForeground)
                    }
                    Button("Send reset link") { Task { await sendPasswordReset() } }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: resetEmail.trimmingCharacters(in: .whitespaces).isEmpty))
                        .disabled(resetEmail.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                }
                .padding(24)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }

    private func submit() async {
        error = nil
        checkEmailNotice = false

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        #if DEBUG
        // Keep the old synthetic credentials testable in Debug builds without
        // shipping a special-case login path in the production binary.
        if trimmedEmail == "1", password == "1" {
            error = "Use your real account to log in. The old 1 / 1 shortcut cannot save your profile."
            return
        }
        #endif


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

    private func sendPasswordReset() async {
        let address = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        do {
            try await SupabaseManager.client.auth.resetPasswordForEmail(address, redirectTo: AppConfig.authCallbackURL)
            resetNotice = "Check your email for a password reset link."
        } catch {
            resetNotice = "We couldn't send the reset link. Please check the email and try again."
        }
    }
}
