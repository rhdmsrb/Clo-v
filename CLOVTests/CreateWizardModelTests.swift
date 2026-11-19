import Testing
import Foundation
@testable import CLOV

struct CreateWizardModelTests {
    @Test("Next on photos is disabled until every slot is filled")
    func photosGate() {
        var model = CreateWizardModel()
        #expect(!model.canAdvance(from: .photos))
        model = model.settingFilledSlots([true, false])
        #expect(!model.canAdvance(from: .photos))
        model = model.settingFilledSlots([true, true])
        #expect(model.canAdvance(from: .photos))
    }

    @Test("Switching to 4 photos requires the new slots")
    func photoCountResizes() {
        var model = CreateWizardModel()
        model = model.settingFilledSlots([true, true])
        let four = model.settingPhotoCount(4)
        #expect(four.filledSlots.count == 4)
        #expect(four.photoDetails.count == 4)
        #expect(!four.canAdvance(from: .photos))
        #expect(four.settingPhotoCount(2).filledSlots == [true, true])
        #expect(model.settingPhotoCount(3).photoCount == 2)
    }

    @Test("Group audience needs a group; everyone ignores it")
    func audienceValidation() {
        var model = CreateWizardModel()
        #expect(!model.hasChosenAudience)
        model.selectAudience(.group)
        #expect(model.hasChosenAudience)
        #expect(!model.canAdvance(from: .details))
        model.groupId = UUID()
        #expect(model.canAdvance(from: .details))
        model.selectAudience(.everyone)
        #expect(model.groupId == nil)
        #expect(model.effectiveGroupId == nil)
    }

    @Test("No audience is chosen for the user; Next waits for a tap")
    func audienceNeedsAChoice() {
        var model = CreateWizardModel()
        #expect(!model.hasChosenAudience)
        #expect(!model.audienceIsValid)
        #expect(!model.canAdvance(from: .details))
        model.selectAudience(.everyone)
        #expect(model.hasChosenAudience)
        #expect(model.canAdvance(from: .details))
    }

    @Test("Arriving from a group counts as chosen")
    func preselectedGroupIsChosen() {
        let model = CreateWizardModel(preselectedGroupId: UUID())
        #expect(model.hasChosenAudience)
        #expect(model.canAdvance(from: .details))
    }

    @Test("Friends and Only me are valid and never carry a group")
    func friendsAndOnlyMeAreValid() {
        var model = CreateWizardModel()
        model.groupId = UUID()
        for audience in [FitCheckAudience.friends, .onlyMe] {
            model.selectAudience(audience)
            #expect(model.audienceIsValid)
            #expect(model.canAdvance(from: .details))
            #expect(model.effectiveGroupId == nil)
        }
        #expect(CreateWizardModel.audiences.count == 4)
    }

    @Test("Only friends and private are sent as an explicit server audience")
    func draftParamsAudience() throws {
        func json(_ audience: String?) throws -> [String: Any] {
            let params = DraftParams(id: UUID(), caption: nil, groupId: nil, occasion: nil,
                                     tags: nil, votePrompt: nil, audience: audience)
            return try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any] ?? [:]
        }
        #expect(try json("friends")["p_audience"] as? String == "friends")
        #expect(try json("private")["p_audience"] as? String == "private")
        #expect(try json(nil)["p_audience"] == nil)
    }

    @Test("Preselected group starts on the group audience")
    func preselectedGroup() {
        let id = UUID()
        let model = CreateWizardModel(preselectedGroupId: id)
        #expect(model.audience == .group)
        #expect(model.hasChosenAudience)
        #expect(model.effectiveGroupId == id)
    }

    @Test("Tags toggle and cap at the limit")
    func tagLimits() {
        var model = CreateWizardModel()
        model = model.togglingTag("Casual").togglingTag("Vintage")
        #expect(model.tags == ["Casual", "Vintage"])
        model = model.togglingTag("Casual")
        #expect(model.tags == ["Vintage"])
        var photo = CreateWizardModel()
        for index in 0..<12 { photo = photo.togglingPhotoTag("t\(index)", at: 0) }
        #expect(photo.photoDetails[0].tags.count == CreateWizardModel.maxTags)
        #expect(photo.togglingPhotoTag("x", at: 9) == photo)
    }

    @Test("Several occasions can be picked and are stored in one text")
    func multipleOccasions() {
        var model = CreateWizardModel()
        model = model.togglingOccasion("Date").togglingOccasion("Work")
        #expect(model.occasion == "Work, Date")
        #expect(model.selectedOccasions == ["Work", "Date"])
        model = model.togglingOccasion("Work")
        #expect(model.occasion == "Date")
        #expect(model.togglingOccasion("Date").occasion.isEmpty)
        #expect(CreateWizardModel(occasion: "Everyday").togglingOccasion("Party").occasion == "Everyday, Party")
    }

    @Test("Typed tags are cleaned, de-duplicated and capped")
    func customTags() {
        var model = CreateWizardModel()
        model = model.addingTag("  #  Boho   chic ").addingTag("boho CHIC").addingTag("casual").addingTag("   ")
        #expect(model.tags == ["Boho chic", "Casual"])
        #expect(CreateWizardModel().addingTag(String(repeating: "a", count: 80)).tags[0].count == FitCheckSubmission.maxTagLength)
        var full = CreateWizardModel()
        for index in 0..<12 { full = full.addingTag("tag\(index)") }
        #expect(full.tags.count == CreateWizardModel.maxTags)
        #expect(CreateWizardModel().addingPhotoTag("denim", at: 0).photoDetails[0].tags == ["denim"])
        #expect(CreateWizardModel().addingPhotoTag("x", at: 9) == CreateWizardModel())
    }

    @Test("Photo description is clamped to 200 characters")
    func descriptionClamp() {
        let model = CreateWizardModel().settingPhotoDescription(String(repeating: "a", count: 500), at: 1)
        #expect(model.photoDetails[1].description.count == 200)
        #expect(model.photoDetailIsValid(1))
        #expect(!model.photoDetailIsValid(5))
    }

    @Test("Title over 120 characters is invalid")
    func titleLimit() {
        var model = CreateWizardModel()
        model.title = String(repeating: "a", count: 121)
        #expect(!model.canAdvance(from: .details))
    }

    @Test("Step navigation walks every photo then preview, and back")
    func navigation() {
        let model = CreateWizardModel().settingPhotoCount(4)
        var step = CreateWizardStep.photos
        var visited: [CreateWizardStep] = [step]
        while step != .preview { step = model.nextStep(after: step); visited.append(step) }
        #expect(visited == [.photos, .details, .photoDetail(0), .photoDetail(1), .photoDetail(2), .photoDetail(3), .preview])
        #expect(model.previousStep(before: .preview) == .photoDetail(3))
        #expect(model.previousStep(before: .photoDetail(0)) == .details)
        #expect(model.previousStep(before: .photos) == nil)
    }

    @Test("Discard prompt only when something was entered")
    func discardDetection() {
        var model = CreateWizardModel()
        #expect(!model.hasEnteredContent())
        model.title = "x"
        #expect(model.hasEnteredContent())
        #expect(!CreateWizardModel(occasion: "Work").hasEnteredContent(initialOccasion: "Work"))
        model = CreateWizardModel()
        model = model.settingFilledSlots([true, false])
        #expect(model.hasEnteredContent())
    }

    @Test("Blank optional fields are omitted from the payload")
    func payloadOmitsBlanks() {
        var model = CreateWizardModel()
        model.title = "   "
        model.caption = "\n"
        #expect(model.trimmedTitle == nil)
        #expect(model.trimmedCaption == nil)
        #expect(model.photoDetailPayload.isEmpty)
        model = model.settingPhotoDescription("  hi ", at: 0)
        #expect(model.photoDetailPayload.first?.description == "hi")
        #expect(model.photoDetailPayload.count == 2)
    }
}
