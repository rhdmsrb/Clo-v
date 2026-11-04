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
    @State private var page = 0
    @FocusState private var nicknameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let introPages = [
        OnboardingIntro(
            symbol: "camera.viewfinder",
            title: "Post a fit, get real answers",
            body: "Upload 2 or 4 looks and let people pick the one that works."
        ),
        OnboardingIntro(
            symbol: "hand.thumbsup.fill",
            title: "Vote with your circle",
            body: "Friends and groups weigh in fast, so you walk out the door sure."
        ),
    ]
    private static var setupPageIndex: Int { introPages.count }
    private static var pageCount: Int { introPages.count + 1 }

    private var onIntro: Bool { page < Self.setupPageIndex }

    private var nicknameValid: Bool {
        let re = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_]{3,20}$")
        return re.firstMatch(in: nickname, range: NSRange(nickname.startIndex..., in: nickname)) != nil
    }

    private var canContinue: Bool {
        nicknameValid && !selectedStyles.isEmpty && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingPageIndicator(count: Self.pageCount, current: page, onGradient: onIntro)
                .padding(.top, 16)
                .padding(.bottom, 8)
            TabView(selection: $page) {
                ForEach(Self.introPages.indices, id: \.self) { index in
                    introPage(Self.introPages[index], index: index).tag(index)
                }
                setupPage.tag(Self.setupPageIndex)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background {
            Group {
                if onIntro { Rectangle().fill(Theme.heroGradient) } else { Theme.background }
            }
            .ignoresSafeArea()
        }
        .motionSafeAnimation(Theme.settle, value: onIntro)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: page) { _, _ in nicknameFocused = false }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { nicknameFocused = false }
            }
        }
    }

    // MARK: - Intro pages

    private func introPage(_ content: OnboardingIntro, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("CLO·V")
                    .font(Theme.editorialFont(size: 28, relativeTo: .title2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button("Skip") { goTo(Self.setupPageIndex) }
                    .font(Theme.label)
                    .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
            }
            Spacer(minLength: 0)
            Image(systemName: content.symbol)
                .font(.system(size: 64, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 140, height: 140)
                .background(Color.white.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            Text(content.title)
                .font(Theme.editorialFont(size: 36, relativeTo: .largeTitle))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Text(content.body)
                .font(Theme.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(index == Self.introPages.count - 1 ? "Get started" : "Next") {
                goTo(index + 1)
            }
            .buttonStyle(OutlineButtonStyle())
        }
        .foregroundStyle(Color.white)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(24)
    }

    private func goTo(_ target: Int) {
        withAnimation(Theme.animation(Theme.hero, reduceMotion: reduceMotion)) { page = target }
    }

    // MARK: - Setup page

    private var setupPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pick your fit persona")
                        .font(Theme.editorialFont(size: 34, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .accessibilityAddTraits(.isHeader)
                    Text("This is how your circle will see you when they're voting.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.mutedForeground)
                }

                LabeledField(
                    label: "Nickname",
                    isFocused: nicknameFocused,
                    errorMessage: !nickname.isEmpty && !nicknameValid
                        ? "3-20 characters: letters, numbers, underscores." : nil
                ) {
                    TextField("fitqueen99", text: $nickname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($nicknameFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            guard canContinue else { return }
                            Task { await submit() }
                        }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "What's your style?")
                    FlowLayout(spacing: 8) {
                        ForEach(styleOptions, id: \.self) { style in
                            ChipToggle(label: style, selected: selectedStyles.contains(style)) {
                                toggle(style)
                            }
                        }
                    }
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                }

                Button {
                    nicknameFocused = false
                    Task { await submit() }
                } label: {
                    if isSaving {
                        HStack(spacing: 8) { ProgressView(); Text("Please wait…") }
                    } else {
                        Text("Let's go")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(isDisabled: !canContinue))
                .disabled(!canContinue)

                Button("Back to log in") {
                    Task { await appState.signOut() }
                }
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.accentDeep)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
                .disabled(isSaving)
            }
            .padding(24)
        }
    }

    private func toggle(_ style: String) {
        if selectedStyles.contains(style) {
            selectedStyles.remove(style)
        } else {
            selectedStyles.insert(style)
        }
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
            try await API.saveOnboarding(nickname: nickname, styles: Array(selectedStyles))
            await appState.refreshProfile()
        } catch {
            if error.isLikelyExpiredSession {
                await appState.signOut()
            } else {
                self.error = error.localizedDescription
            }
        }
    }
}

private extension Error {
    var isLikelyExpiredSession: Bool {
        let message = localizedDescription.lowercased()
        return message.contains("jwt expired")
            || message.contains("session expired")
            || message.contains("not authenticated")
            || message.contains("invalid refresh token")
            || message.contains("refresh token") && message.contains("expired")
    }
}

private struct OnboardingIntro {
    let symbol: String
    let title: String
    let body: String
}

/// Capsule page indicator: the current page is a wide capsule, others are dots.
private struct OnboardingPageIndicator: View {
    let count: Int
    let current: Int
    let onGradient: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(color(isCurrent: index == current))
                    .frame(width: index == current ? 28 : 8, height: 8)
            }
        }
        .motionSafeAnimation(Theme.snap, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }

    private func color(isCurrent: Bool) -> Color {
        if onGradient { return Color.white.opacity(isCurrent ? 1 : 0.5) }
        return isCurrent ? Theme.accentDeep : Theme.controlBorder
    }
}
