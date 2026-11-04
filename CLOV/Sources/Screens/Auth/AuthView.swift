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
            VStack(alignment: .leading, spacing: 0) {
                AuthHeroBlock(title: mode.title, subtitle: mode.subtitle)
                VStack(alignment: .leading, spacing: 20) {
                    if checkEmailNotice { checkEmailBanner }
                    fields
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                    }
                    submitButton
                    secondaryActions
                }
                .padding(24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
        .motionSafeAnimation(Theme.settle, value: mode)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .sheet(isPresented: $showingPasswordReset) { resetSheet }
    }

    private var checkEmailBanner: some View {
        Label("Check your email to confirm your account, then log in.", systemImage: "envelope.badge")
            .font(Theme.bodyEmphasis)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledField(label: "Email", isFocused: focusedField == .email) {
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }
            LabeledField(
                label: "Password",
                isFocused: focusedField == .password,
                errorMessage: !password.isEmpty && password.count < 6 ? "Use at least 6 characters." : nil
            ) {
                SecureField("", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit {
                        guard canSubmit else { return }
                        Task { await submit() }
                    }
            }
        }
    }

    private var submitButton: some View {
        Button {
            focusedField = nil
            Task { await submit() }
        } label: {
            if isSubmitting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Please wait…")
                }
            } else {
                Text(mode.title)
            }
        }
        .buttonStyle(PrimaryButtonStyle(isDisabled: isSubmitting || !canSubmit))
        .disabled(isSubmitting || !canSubmit)
    }

    private var secondaryActions: some View {
        VStack(spacing: 0) {
            Button {
                mode = mode == .signIn ? .signUp : .signIn
                error = nil
                checkEmailNotice = false
            } label: {
                Text(mode.switchPrompt)
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.accentDeep)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
                    .contentShape(Rectangle())
            }
            if mode == .signIn {
                Button("Forgot password?") {
                    resetEmail = email.trimmingCharacters(in: .whitespaces)
                    resetNotice = nil
                    showingPasswordReset = true
                }
                .font(Theme.label)
                .foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
            }
        }
    }

    private var resetEmailIsEmpty: Bool {
        resetEmail.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var resetSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reset your password")
                    .font(Theme.editorialFont(size: 30, relativeTo: .title2))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityAddTraits(.isHeader)
                Text("We'll send a secure password reset link to your email.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.mutedForeground)
                LabeledField(label: "Email") {
                    TextField("you@example.com", text: $resetEmail)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let resetNotice {
                    let failed = resetNotice.hasPrefix("We couldn't")
                    Label(resetNotice, systemImage: failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(Theme.caption)
                        .foregroundStyle(failed ? Theme.danger : Theme.mutedForeground)
                }
                Button("Send reset link") { Task { await sendPasswordReset() } }
                    .buttonStyle(PrimaryButtonStyle(isDisabled: resetEmailIsEmpty))
                    .disabled(resetEmailIsEmpty)
                Spacer()
            }
            .padding(24)
            .background(Theme.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(Theme.cardRadius)
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
            AuthCallbackGate.shared.markResetRequested()
            resetNotice = "Check your email for a password reset link."
        } catch {
            resetNotice = "We couldn't send the reset link. Please check the email and try again."
        }
    }
}

/// Full-bleed hero used by Auth, Onboarding intro and New Password: gradient
/// surface, Bodoni title, short value copy. White on every gradient stop is >= 4.5:1.
struct AuthHeroBlock: View {
    let title: String
    let subtitle: String

    private static let bottomRadius: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").accessibilityHidden(true)
                Text("CLO·V")
                    .font(Theme.editorialFont(size: 28, relativeTo: .title2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color.white)
            Spacer(minLength: 12)
            Text(title)
                .font(Theme.editorialFont(size: 44, relativeTo: .largeTitle))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(Theme.body)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 72)
        .padding(.bottom, 32)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: Self.bottomRadius, bottomTrailingRadius: Self.bottomRadius, style: .continuous)
                .fill(Theme.heroGradient)
        }
    }
}
