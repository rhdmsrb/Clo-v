import SwiftUI

/// Step 2 body: title, description, occasion, tags, duration, audience.
struct CreateDetailsStep: View {
    @Binding var model: CreateWizardModel
    @Binding var votingDuration: VotingDuration
    let myGroups: [FashionGroup]

    private var titleBinding: Binding<String> {
        Binding(get: { model.title }, set: { model.title = String($0.prefix(CreateWizardModel.maxTitleLength)) })
    }
    private var audienceBinding: Binding<FitCheckAudience> {
        Binding(get: { model.audience }, set: { newValue in
            model.selectAudience(newValue)
            if newValue == .group && model.groupId == nil { model.groupId = myGroups.first?.id }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            AudienceSection(
                selectedAudience: audienceBinding,
                selectedGroupId: $model.groupId,
                myGroups: myGroups,
                hasChosenAudience: model.hasChosenAudience
            )
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Title")
                LabeledField(padding: 12) {
                    TextField("Which shoes finish this look?", text: titleBinding, axis: .vertical)
                        .lineLimit(1...2)
                        .accessibilityIdentifier("createTitleField")
                }
                Text("\(model.title.count)/\(CreateWizardModel.maxTitleLength)")
                    .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
                    .accessibilityLabel("\(model.title.count) of \(CreateWizardModel.maxTitleLength) characters")
            }
            NoteSection(caption: $model.caption)
            OccasionSection(occasion: $model.occasion, options: CreateWizardModel.occasionOptions)
            TagChipGrid(title: "Tags", selected: model.tags, limit: CreateWizardModel.maxTags, identifierPrefix: "createTag") {
                model = model.togglingTag($0)
            }
            VotingWindowSection(votingDuration: $votingDuration)
        }
    }
}

/// Chip grid over the shared style vocabulary with a selection cap.
struct TagChipGrid: View {
    let title: String
    let selected: [String]
    let limit: Int
    let identifierPrefix: String
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            FlowLayout(spacing: 8) {
                ForEach(CreateWizardModel.tagVocabulary, id: \.self) { tag in
                    ChipToggle(label: tag, selected: selected.contains(tag)) { onToggle(tag) }
                        .accessibilityIdentifier("\(identifierPrefix)-\(tag)")
                }
            }
            Text("\(selected.count) of \(limit) selected")
                .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
        }
    }
}

/// Step 3 body: one photo, its unique description and tags.
struct CreatePhotoDetailStep: View {
    @Binding var model: CreateWizardModel
    let image: UIImage?
    let index: Int

    private var detail: PhotoDetail { model.photoDetails.indices.contains(index) ? model.photoDetails[index] : PhotoDetail() }

    private var descriptionBinding: Binding<String> {
        Binding(get: { detail.description }, set: { model = model.settingPhotoDescription($0, at: index) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let image {
                AspectFitTile(cornerRadius: Theme.tileRadius, shadow: false) {
                    Image(uiImage: image).resizable().scaledToFit().background(Theme.muted)
                }
                .accessibilityLabel("Photo \(index + 1) of \(model.photoCount)")
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Unique description")
                LabeledField(padding: 12) {
                    TextField("What’s special about this one?", text: descriptionBinding, axis: .vertical)
                        .lineLimit(1...4)
                        .accessibilityIdentifier("createPhotoDescriptionField")
                }
                Text("\(detail.description.count)/\(CreateWizardModel.maxPhotoDescriptionLength)")
                    .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
            }
            TagChipGrid(
                title: "Unique tags",
                selected: detail.tags,
                limit: CreateWizardModel.maxTags,
                identifierPrefix: "createPhotoTag"
            ) { model = model.togglingPhotoTag($0, at: index) }
        }
    }
}

/// Step 4 body: the feed card and the first vote-screen state, as they will appear.
struct CreatePreviewStep: View {
    let model: CreateWizardModel
    let images: [UIImage]
    let groupName: String?
    let votingDuration: VotingDuration

    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Feed card")
            feedCard
            SectionHeader(title: "Vote screen")
            voteState
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("createPreview")
    }

    private var heading: String { model.trimmedTitle ?? "Untitled Fit-Check" }

    private var feedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabView(selection: $page) {
                ForEach(Array(images.enumerated()), id: \.offset) { offset, image in
                    Color.clear
                        .overlay { Image(uiImage: image).resizable().scaledToFit() }
                        .background(Theme.muted)
                        .clipped()
                        .tag(offset)
                        .accessibilityLabel("Photo \(offset + 1) of \(images.count)")
                }
            }
            .tabViewStyle(.page)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            Text(heading).font(Theme.headline).foregroundStyle(Theme.ink)
            if let caption = model.trimmedCaption {
                Text(caption).font(Theme.body).foregroundStyle(Theme.mutedForeground)
            }
            metadata
        }
        .padding(12)
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var metadata: some View {
        let shown = (model.occasion.isEmpty ? [] : [model.occasion]) + model.tags
        return VStack(alignment: .leading, spacing: 6) {
            if !shown.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(shown, id: \.self) { Text($0).font(Theme.caption).foregroundStyle(Theme.accentDeep) }
                }
            }
            Label(model.audience == .group ? (groupName ?? "A group") : model.audience.title, systemImage: model.audience.symbol)
                .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
                .accessibilityIdentifier("createPreviewAudience")
            Label("Voting: \(votingDuration.label)", systemImage: "clock")
                .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
                .accessibilityIdentifier("createPreviewDuration")
        }
    }

    private var voteState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading).font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.offset) { offset, image in
                    VStack(alignment: .leading, spacing: 4) {
                        AspectFitTile(cornerRadius: Theme.tileRadius, shadow: false) {
                            Image(uiImage: image).resizable().scaledToFit().background(Theme.muted)
                        }
                        .accessibilityLabel("Photo \(offset + 1)")
                        let text = model.photoDetails.indices.contains(offset) ? model.photoDetails[offset].description : ""
                        if !text.isEmpty { Text(text).font(Theme.caption).foregroundStyle(Theme.ink) }
                        if model.photoDetails.indices.contains(offset), !model.photoDetails[offset].tags.isEmpty {
                            Text(model.photoDetails[offset].tags.map { "#\($0)" }.joined(separator: ", "))
                                .font(Theme.caption).foregroundStyle(Theme.accentDeep)
                                .accessibilityIdentifier("createPreviewPhotoTags-\(offset)")
                        }
                    }
                }
            }
            Text("Voters hold a photo to vote. Results stay hidden until they do.")
                .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
        }
    }
}
