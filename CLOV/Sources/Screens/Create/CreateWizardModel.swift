import Foundation

/// The wizard steps in order: photos, details, one step per photo, preview.
enum CreateWizardStep: Equatable {
    case photos
    case details
    case photoDetail(Int)
    case preview
}

/// Pure value-type state and validation for the Create wizard, kept free of
/// SwiftUI so it can be unit tested.
struct CreateWizardModel: Equatable {
    // Limits come from FitCheckSubmission so the wizard and the API agree.
    static let maxTitleLength = FitCheckSubmission.maxVotePromptLength
    static let maxCaptionLength = 280
    static let maxPhotoDescriptionLength = FitCheckSubmission.maxDescriptionLength
    static let maxTags = FitCheckSubmission.maxTags
    /// Style vocabulary shared with the wardrobe editor.
    static let tagVocabulary = ["Casual", "Minimal", "Streetwear", "Vintage", "Workwear", "Sporty", "Smart casual", "Monochrome", "Statement"]
    static let occasionOptions = ["Everyday", "Work", "Date", "Interview", "Party", "Travel", "Wedding"]

    /// Mutated only through `settingPhotoCount` / `settingFilledSlots` so the
    /// two arrays can never desync from the count.
    private(set) var photoCount = 2
    private(set) var filledSlots: [Bool] = [false, false]
    var title = ""
    var caption = ""
    var occasion = ""
    var tags: [String] = []
    var audience: FitCheckAudience = .everyone
    var groupId: UUID?
    var photoDetails: [PhotoDetail] = [.init(), .init()]
    var step: CreateWizardStep = .photos

    /// Wizard only offers public and group audiences.
    static let audiences: [FitCheckAudience] = [.everyone, .group]

    init(preselectedGroupId: UUID? = nil, occasion: String? = nil) {
        self.occasion = occasion ?? ""
        if let preselectedGroupId {
            audience = .group
            groupId = preselectedGroupId
        }
    }

    // MARK: - Validation

    var allPhotosFilled: Bool { filledSlots.count == photoCount && !filledSlots.contains(false) }
    var titleIsValid: Bool { title.count <= Self.maxTitleLength }
    var captionIsValid: Bool { caption.count <= Self.maxCaptionLength }
    var audienceIsValid: Bool {
        switch audience {
        case .everyone: true
        case .group: groupId != nil
        case .friends, .onlyMe: false
        }
    }
    var detailsAreValid: Bool { titleIsValid && captionIsValid && audienceIsValid }

    func canAdvance(from step: CreateWizardStep) -> Bool {
        switch step {
        case .photos: allPhotosFilled
        case .details: detailsAreValid
        case .photoDetail(let index): photoDetailIsValid(index)
        case .preview: allPhotosFilled && detailsAreValid
        }
    }

    func photoDetailIsValid(_ index: Int) -> Bool {
        guard photoDetails.indices.contains(index) else { return false }
        let detail = photoDetails[index]
        return detail.description.count <= Self.maxPhotoDescriptionLength && detail.tags.count <= Self.maxTags
    }

    /// True when leaving would throw away something the user entered.
    /// Audience, group and duration are choices with defaults, not typed
    /// content, so they deliberately do not count.
    func hasEnteredContent(initialOccasion: String? = nil) -> Bool {
        filledSlots.contains(true)
            || !title.isEmpty || !caption.isEmpty || !tags.isEmpty
            || occasion != (initialOccasion ?? "")
            || photoDetails.contains { !$0.description.isEmpty || !$0.tags.isEmpty }
    }

    // MARK: - Mutations (value-returning)

    func settingPhotoCount(_ count: Int) -> CreateWizardModel {
        guard count == 2 || count == 4 else { return self }
        var copy = self
        copy.photoCount = count
        copy.filledSlots = Self.resized(filledSlots, to: count, fill: false)
        copy.photoDetails = Self.resized(photoDetails, to: count, fill: PhotoDetail())
        return copy
    }

    /// Records which slots hold a photo; always normalised to `photoCount`.
    func settingFilledSlots(_ filled: [Bool]) -> CreateWizardModel {
        var copy = self
        copy.filledSlots = Self.resized(filled, to: photoCount, fill: false)
        return copy
    }

    func togglingTag(_ tag: String) -> CreateWizardModel {
        var copy = self
        copy.tags = Self.toggled(tag, in: tags, limit: Self.maxTags)
        return copy
    }

    func togglingPhotoTag(_ tag: String, at index: Int) -> CreateWizardModel {
        guard photoDetails.indices.contains(index) else { return self }
        var copy = self
        copy.photoDetails[index].tags = Self.toggled(tag, in: photoDetails[index].tags, limit: Self.maxTags)
        return copy
    }

    func settingPhotoDescription(_ text: String, at index: Int) -> CreateWizardModel {
        guard photoDetails.indices.contains(index) else { return self }
        var copy = self
        copy.photoDetails[index].description = String(text.prefix(Self.maxPhotoDescriptionLength))
        return copy
    }

    // MARK: - Navigation

    var lastStepIndex: Int { photoCount - 1 }

    func nextStep(after step: CreateWizardStep) -> CreateWizardStep {
        switch step {
        case .photos: .details
        case .details: .photoDetail(0)
        case .photoDetail(let index): index >= lastStepIndex ? .preview : .photoDetail(index + 1)
        case .preview: .preview
        }
    }

    func previousStep(before step: CreateWizardStep) -> CreateWizardStep? {
        switch step {
        case .photos: nil
        case .details: .photos
        case .photoDetail(let index): index == 0 ? .details : .photoDetail(index - 1)
        case .preview: .photoDetail(lastStepIndex)
        }
    }

    // MARK: - Submission payload (nil/empty when blank so old backends keep working)

    var effectiveGroupId: UUID? { audience == .group ? groupId : nil }
    var trimmedTitle: String? { Self.nonEmpty(title) }
    var trimmedCaption: String? { Self.nonEmpty(caption) }
    var postTags: [String] { tags }

    /// Per-photo payload, or an empty array when no photo has any detail.
    var photoDetailPayload: [PhotoDetail] {
        let cleaned = photoDetails.map {
            PhotoDetail(description: $0.description.trimmingCharacters(in: .whitespacesAndNewlines), tags: $0.tags)
        }
        return cleaned.contains { !$0.description.isEmpty || !$0.tags.isEmpty } ? cleaned : []
    }

    // MARK: - Helpers

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func toggled(_ tag: String, in list: [String], limit: Int) -> [String] {
        if list.contains(tag) { return list.filter { $0 != tag } }
        return list.count < limit ? list + [tag] : list
    }

    private static func resized<T>(_ array: [T], to count: Int, fill: T) -> [T] {
        array.count >= count ? Array(array.prefix(count)) : array + Array(repeating: fill, count: count - array.count)
    }
}
