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
            model.audience = newValue
            if newValue == .group { model.groupId = model.groupId ?? myGroups.first?.id } else { model.groupId = nil }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
            TagChipGrid(title: "Tags", selected: model.tags, limit: CreateWizardModel.maxTags, identifierPrefix: "createTag",
                         onToggle: { model = model.togglingTag($0) },
                         onAdd: { model = model.addingTag($0) })
            VotingWindowSection(votingDuration: $votingDuration)
            AudienceSection(
                selectedAudience: audienceBinding,
                selectedGroupId: $model.groupId,
                myGroups: myGroups,
                hasChosen: model.audienceChosen
            )
        }
    }
}

/// Suggested style chips plus a field for the viewer's own tags, with a selection cap.
/// Typed tags appear as selected chips; tapping one removes it.
struct TagChipGrid: View {
    let title: String
    let selected: [String]
    let limit: Int
    let identifierPrefix: String
    let onToggle: (String) -> Void
    let onAdd: (String) -> Void

    @State private var draft = ""

    private var customTags: [String] {
        selected.filter { tag in !CreateWizardModel.tagVocabulary.contains(tag) }
    }
    private var isFull: Bool { selected.count >= limit }
    private var canAdd: Bool { !isFull && CreateWizardModel.cleanedTag(draft) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            FlowLayout(spacing: 8) {
                ForEach(CreateWizardModel.tagVocabulary + customTags, id: \.self) { tag in
                    ChipToggle(label: tag, selected: selected.contains(tag)) { onToggle(tag) }
                        .accessibilityIdentifier("\(identifierPrefix)-\(tag)")
                }
            }
            addField
            Text("\(selected.count) of \(limit) selected")
                .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            LabeledField(padding: 12) {
                TextField("Add your own tag", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .disabled(isFull)
                    .onChange(of: draft) { _, value in
                        if value.count > FitCheckSubmission.maxTagLength {
                            draft = String(value.prefix(FitCheckSubmission.maxTagLength))
                        }
                    }
                    .onSubmit(commit)
                    .accessibilityIdentifier("\(identifierPrefix)-input")
            }
            Button("Add", action: commit)
                .font(Theme.label)
                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                .disabled(!canAdd)
                .accessibilityIdentifier("\(identifierPrefix)-add")
        }
    }

    private func commit() {
        guard canAdd else { return }
        onAdd(draft)
        draft = ""
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
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
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
                identifierPrefix: "createPhotoTag",
                onToggle: { model = model.togglingPhotoTag($0, at: index) },
                onAdd: { model = model.addingPhotoTag($0, at: index) }
            )
        }
    }
}

/// Step 4 body: the feed card and the first vote-screen state, as they will appear.
struct CreatePreviewStep: View {
    let model: CreateWizardModel
    let images: [UIImage]
    let groupName: String?

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
                    Image(uiImage: image).resizable().scaledToFill().clipped()
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
        let shown = model.selectedOccasions + model.tags
        return VStack(alignment: .leading, spacing: 6) {
            if !shown.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(shown, id: \.self) { Text($0).font(Theme.caption).foregroundStyle(Theme.accentDeep) }
                }
            }
            Label(model.audience == .group ? (groupName ?? "A group") : model.audience.title, systemImage: model.audience.symbol)
                .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
        }
    }

    private var voteState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading).font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.offset) { offset, image in
                    VStack(alignment: .leading, spacing: 4) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                            .accessibilityLabel("Photo \(offset + 1)")
                        let text = model.photoDetails.indices.contains(offset) ? model.photoDetails[offset].description : ""
                        if !text.isEmpty { Text(text).font(Theme.caption).foregroundStyle(Theme.ink) }
                    }
                }
            }
            Text("Voters hold a photo to vote. Results stay hidden until they do.")
                .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
        }
    }
}
