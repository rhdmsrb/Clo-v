@preconcurrency import SwiftUI

@MainActor
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var nickname: String
    @State private var styles: Set<String>
    @State private var isSaving = false
    @State private var error: String?

    private static let styleOptions = ["Streetwear", "Casual", "Formal", "Athletic", "Vintage", "Minimalist", "Bohemian", "Glam"]

    init(profile: Profile?) {
        _nickname = State(initialValue: profile?.nickname ?? "")
        _styles = State(initialValue: Set(profile?.stylePreferences ?? []))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LabeledField(label: "NICKNAME") {
                        TextField("Your nickname", text: $nickname)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Text("WHAT'S YOUR STYLE?")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.mutedForeground)
                    FlowLayout(spacing: 8) {
                        ForEach(Self.styleOptions, id: \.self) { style in
                            ChipToggle(label: style, selected: styles.contains(style)) {
                                if styles.contains(style) { styles.remove(style) }
                                else { styles.insert(style) }
                            }
                        }
                    }
                    if let error { Text(error).font(Theme.label).foregroundStyle(Theme.danger) }
                    Button(isSaving ? "Saving…" : "Save profile") { Task { await save() } }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: isSaving))
                        .disabled(isSaving)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() async {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "^[A-Za-z0-9_]{3,20}$", options: .regularExpression) != nil else {
            error = "Nickname must be 3–20 letters, numbers, or underscores."
            return
        }
        guard !styles.isEmpty else { error = "Pick at least one style."; return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await API.saveOnboarding(nickname: trimmed, styles: styles.sorted())
            await appState.refreshProfile()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
