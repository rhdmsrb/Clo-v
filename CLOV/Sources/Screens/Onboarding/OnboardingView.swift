import SwiftUI

private let styleOptions = [
    "Streetwear", "Casual", "Formal", "Athletic",
    "Vintage", "Minimalist", "Bohemian", "Glam",
]

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState

    @State private var nickname = ""
    @State private var selectedStyles: Set<String> = []
    @State private var error: String?
    @State private var isSaving = false

    private var nicknameValid: Bool {
        let re = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_]{3,20}$")
        return re.firstMatch(in: nickname, range: NSRange(nickname.startIndex..., in: nickname)) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("CLO·V")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick your fit persona")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    Text("This is how your circle will see you when they're voting.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                }

                LabeledField(label: "NICKNAME") {
                    TextField("fitqueen99", text: $nickname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("WHAT'S YOUR STYLE?")
                        .font(.system(.caption2, design: .default).weight(.bold))
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(styleOptions, id: \.self) { style in
                            ChipToggle(label: style, selected: selectedStyles.contains(style)) {
                                if selectedStyles.contains(style) {
                                    selectedStyles.remove(style)
                                } else {
                                    selectedStyles.insert(style)
                                }
                            }
                        }
                    }
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Text(isSaving ? "Please wait…" : "Let's go")
                }
                .buttonStyle(PrimaryButtonStyle(isDisabled: isSaving))
                .disabled(isSaving)

                Button("Back to log in") {
                    Task { await appState.signOut() }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .disabled(isSaving)
            }
            .padding(24)
        }
        .background(Theme.background)
    }

    private func submit() async {
        error = nil
        guard nicknameValid else {
            error = "Nickname must be 3-20 characters: letters, numbers, underscores only."
            return
        }
        guard !selectedStyles.isEmpty else {
            error = "Pick at least one style you're into."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await API.saveOnboarding(id: appState.userId, nickname: nickname, styles: Array(selectedStyles))
            await appState.refreshProfile()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
