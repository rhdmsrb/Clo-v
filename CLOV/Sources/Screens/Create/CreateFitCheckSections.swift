import SwiftUI

/// Small uppercase heading used above each form section.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.microMedium)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct PhotoCountSection: View {
    let photoCount: Int
    let onSelect: (Int) -> Void

    private static let options = [2, 4]

    var body: some View {
        HStack(spacing: 8) {
            SectionLabel("PHOTOS")
            Spacer()
            ForEach(Self.options, id: \.self) { count in
                Button { onSelect(count) } label: { Text("\(count) photos") }
                    .buttonStyle(ChipButtonStyle(
                        isSelected: photoCount == count,
                        font: Theme.microMedium,
                        unselectedFill: Theme.card,
                        unselectedForeground: Theme.mutedForeground
                    ))
                    .accessibilityAddTraits(photoCount == count ? .isSelected : [])
            }
        }
    }
}

struct PhotoGridSection: View {
    @Binding var slots: [PhotoSlotState]
    let canUseWardrobe: Bool
    let onPickWardrobe: (UUID) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach($slots) { $slot in
                let number = (slots.firstIndex { $0.id == slot.id } ?? 0) + 1
                VStack(spacing: 7) {
                    PhotoSlotView(state: $slot, label: "Photo \(number)")
                    Button { onPickWardrobe(slot.id) } label: {
                        Label("My Wardrobe", systemImage: "hanger")
                            .font(Theme.microMedium)
                            .foregroundStyle(Theme.accent)
                            .frame(minHeight: 44)
                    }
                    .disabled(!canUseWardrobe)
                }
            }
        }
    }
}

struct NoteSection: View {
    @Binding var caption: String
    @ScaledMetric(relativeTo: .body) private var noteMinHeight: CGFloat = 80

    private static let placeholder = "Add context about where you're going or what matters to you."

    var body: some View {
        LabeledField(label: "ADD A NOTE (OPTIONAL)", padding: 8) {
            TextEditor(text: $caption)
                .frame(minHeight: noteMinHeight)
                .accessibilityLabel("Note, optional")
                .accessibilityHint(Self.placeholder)
                .overlay(alignment: .topLeading) {
                    if caption.isEmpty {
                        Text(Self.placeholder)
                            .font(.subheadline)
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
    }
}

struct PromptSection: View {
    @Binding var votePrompt: String
    let suggestions: [String]
    let maxLength: Int

    /// Clamps on write so the limit is enforced in a single update.
    private var clampedPrompt: Binding<String> {
        Binding(get: { votePrompt }, set: { votePrompt = String($0.prefix(maxLength)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("WHAT SHOULD PEOPLE HELP YOU DECIDE?")
            TextField("e.g. Which shoes finish this look?", text: clampedPrompt, axis: .vertical)
                .lineLimit(1...2)
                .font(.subheadline)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .stroke(Theme.controlBorder, lineWidth: 1))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button { votePrompt = suggestion } label: { Text(suggestion) }
                            .buttonStyle(ChipButtonStyle(
                                isSelected: false,
                                unselectedFill: Theme.iconPlum.opacity(0.11),
                                unselectedForeground: Theme.ink,
                                horizontalPadding: 10
                            ))
                    }
                }
            }
            Text("Optional. A specific question gets more useful feedback.")
                .font(.caption2).foregroundStyle(Theme.mutedForeground)
        }
    }
}

struct OccasionSection: View {
    @Binding var occasion: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("WHAT'S THE OCCASION?")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        ChipToggle(label: option, selected: occasion == option) { occasion = occasion == option ? "" : option }
                    }
                }
            }
        }
    }
}

struct VotingWindowSection: View {
    @Binding var votingDuration: VotingDuration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("VOTING WINDOW")
            HStack(spacing: 8) {
                ForEach(VotingDuration.allCases) { duration in
                    ChipToggle(label: duration.label, selected: votingDuration == duration) {
                        votingDuration = duration
                    }
                }
            }
            Text("Voting closes after this. Results remain available to you in Me; the post leaves everyone else's feed.")
                .font(.caption2)
                .foregroundStyle(Theme.mutedForeground)
        }
    }
}

struct AudienceSection: View {
    @Binding var selectedAudience: FitCheckAudience
    @Binding var selectedGroupId: UUID?
    let myGroups: [FashionGroup]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("WHO CAN SEE THIS?")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(FitCheckAudience.allCases) { option in audienceButton(option) }
            }
            if selectedAudience == .group { groupChooser }
            Text(selectedAudience.description)
                .font(.caption).foregroundStyle(Theme.mutedForeground)
        }
    }

    private func audienceButton(_ option: FitCheckAudience) -> some View {
        let isSelected = selectedAudience == option
        let shape = RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
        return Button {
            withAnimation(Theme.animation(Theme.press, reduceMotion: reduceMotion)) { selectedAudience = option }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: option.symbol).font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                Text(option.title).font(Theme.bodyEmphasis)
                Spacer(minLength: 0)
                if isSelected { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
            }
            .foregroundStyle(isSelected ? Theme.ink : Theme.mutedForeground)
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? Theme.accent.opacity(0.12) : Theme.card, in: shape)
            .overlay(shape.stroke(isSelected ? Theme.accent.opacity(0.55) : Theme.controlBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var groupChooser: some View {
        if myGroups.isEmpty {
            Text("Create or join a group first to share privately with its members.")
                .font(.caption).foregroundStyle(Theme.mutedForeground)
        } else {
            Picker("Choose group", selection: $selectedGroupId) {
                ForEach(myGroups) { group in Text(group.name).tag(Optional(group.id)) }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
