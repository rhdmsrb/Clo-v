import SwiftUI

struct PhotoCountSection: View {
    let photoCount: Int
    let onSelect: (Int) -> Void

    private static let options = [2, 4]

    var body: some View {
        HStack(spacing: 8) {
            SectionHeader(title: "Photos")
            Spacer()
            ForEach(Self.options, id: \.self) { count in
                Button { onSelect(count) } label: { Text("\(count) photos") }
                    .buttonStyle(ChipButtonStyle(
                        isSelected: photoCount == count,
                        font: Theme.caption
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
                            .font(Theme.caption)
                            .foregroundStyle(Theme.accentDeep)
                            .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
                            .contentShape(Rectangle())
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

    private static let placeholder = "Add context about where you’re going or what matters to you."
    private var limitedCaption: Binding<String> {
        Binding(get: { caption }, set: { caption = String($0.prefix(CreateWizardModel.maxCaptionLength)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledField(label: "Description (optional)", padding: 8) {
                TextEditor(text: limitedCaption)
                    // Hide TextEditor's opaque background so the field surface shows through.
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: noteMinHeight)
                    .accessibilityLabel("Description, optional")
                    .accessibilityIdentifier("createDescriptionField")
                    .accessibilityHint(Self.placeholder)
                    .overlay(alignment: .topLeading) {
                        if caption.isEmpty {
                            Text(Self.placeholder)
                                .font(Theme.body)
                                .foregroundStyle(Theme.mutedForeground)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
            }
            Text("\(caption.count)/\(CreateWizardModel.maxCaptionLength)")
                .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
                .accessibilityLabel("\(caption.count) of \(CreateWizardModel.maxCaptionLength) characters")
        }
    }
}

struct OccasionSection: View {
    @Binding var occasion: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "What’s the occasion?")
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
            SectionHeader(title: "Voting window")
            HStack(spacing: 8) {
                ForEach(VotingDuration.allCases) { duration in
                    ChipToggle(label: duration.label, selected: votingDuration == duration) {
                        votingDuration = duration
                    }
                }
            }
            Text("Voting closes after this. Results remain available to you in Me; the post leaves everyone else's feed.")
                .font(Theme.caption)
                .foregroundStyle(Theme.mutedForeground)
        }
    }
}

struct AudienceSection: View {
    @Binding var selectedAudience: FitCheckAudience
    @Binding var selectedGroupId: UUID?
    let myGroups: [FashionGroup]
    let hasChosenAudience: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(title: "Who can see this?")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
                ForEach(FitCheckAudience.allCases) { option in audienceButton(option) }
            }
            if selectedAudience == .group { groupChooser }
            Text(hasChosenAudience ? selectedAudience.description : "Choose who can see your Fit-Check.")
                .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
        }
    }

    private func audienceButton(_ option: FitCheckAudience) -> some View {
        let isSelected = hasChosenAudience && selectedAudience == option
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
            .foregroundStyle(isSelected ? Theme.accentDeep : Theme.ink)
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? Theme.accentTint : Theme.muted, in: shape)
            .overlay(shape.stroke(isSelected ? Theme.accentDeep : Theme.controlBorder, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("createAudience.\(option.rawValue)")
    }

    @ViewBuilder
    private var groupChooser: some View {
        if myGroups.isEmpty {
            Text("Create or join a group first to share privately with its members.")
                .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
        } else {
            Picker("Choose group", selection: $selectedGroupId) {
                ForEach(myGroups) { group in Text(group.name).tag(Optional(group.id)) }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 12)
            .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
    }
}
