import XCTest
import Supabase
import UIKit
@testable import CLOV

final class FitCheckSubmissionTests: XCTestCase {
    func testCropGeometryMatchesVisibleRegionAndClampsPan() {
        let image = CGSize(width: 1200, height: 800)
        let frame = CGSize(width: 300, height: 400)
        let offset = CropGeometry.clamped(CGSize(width: 500, height: 500), image: image, frame: frame, zoom: 1)
        XCTAssertEqual(offset.width, 150, accuracy: 0.001)
        XCTAssertEqual(offset.height, 0, accuracy: 0.001)
        let rect = CropGeometry.cropRect(image: image, frame: frame, zoom: 1, offset: offset)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 600, accuracy: 0.001)
        XCTAssertEqual(rect.height, 800, accuracy: 0.001)
    }

    func testCropZoomKeepsPinchAnchorInPlace() {
        let anchor = CGPoint(x: 60, y: -40)
        let offset = CropGeometry.zoomedOffset(CGSize(width: 20, height: 10), anchor: anchor, factor: 2)
        XCTAssertEqual(offset.width, -20, accuracy: 0.001)
        XCTAssertEqual(offset.height, 60, accuracy: 0.001)
    }

    func testSavedCropRestoresAtDifferentCanvasSize() {
        let image = CGSize(width: 1600, height: 1200)
        let firstFrame = CGSize(width: 300, height: 400)
        let rect = CropGeometry.cropRect(image: image, frame: firstFrame, zoom: 2, offset: CGSize(width: 80, height: -50))
        let secondFrame = CGSize(width: 240, height: 320)
        let restored = CropGeometry.transform(for: rect, image: image, frame: secondFrame, maxZoom: 5)
        let actual = CropGeometry.cropRect(image: image, frame: secondFrame, zoom: restored.zoom, offset: restored.offset)
        XCTAssertEqual(actual.minX, rect.minX, accuracy: 0.001)
        XCTAssertEqual(actual.minY, rect.minY, accuracy: 0.001)
        XCTAssertEqual(actual.width, rect.width, accuracy: 0.001)
        XCTAssertEqual(actual.height, rect.height, accuracy: 0.001)
    }
    private func encodedKeys<T: Encodable>(_ value: T) throws -> Set<String> {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try JSONSerialization.jsonObject(with: encoder.encode(value))
        return Set((object as? [String: Any] ?? [:]).keys)
    }

    func testPostUploadKeepsWholeLandscapePhotoWhenDownsizing() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3200, height: 1800), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1800))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 1600, y: 0, width: 1600, height: 1800))
        }
        let uploaded = try XCTUnwrap(UIImage(data: API.preparedFitCheckJPEG(image)))
        XCTAssertEqual(uploaded.size.width, 1600, accuracy: 1)
        XCTAssertEqual(uploaded.size.height, 900, accuracy: 1)
    }

    func testPostUploadResizesRetinaImageUsingPixelDimensions() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 900), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
        }
        let uploaded = try XCTUnwrap(UIImage(data: API.preparedFitCheckJPEG(image)))
        XCTAssertEqual(uploaded.size.width, 1600, accuracy: 1)
        XCTAssertEqual(uploaded.size.height, 900, accuracy: 1)
    }

    // MARK: Tally decoding

    func testLivePhotoTallyDecodesSnakeCase() throws {
        let json = #"[{"photo_id":"11111111-1111-1111-1111-111111111111","vote_count":7,"is_mine":true}]"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try decoder.decode([LivePhotoTally].self, from: Data(json.utf8))
        XCTAssertEqual(rows.first?.voteCount, 7)
        XCTAssertEqual(rows.first?.isMine, true)
        XCTAssertEqual(rows.first?.photoId, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    }

    // MARK: Encoding keys

    func testDraftParamsFullPayloadUsesRpcParamNames() throws {
        let params = DraftParams(id: UUID(), caption: "c", groupId: UUID(), occasion: "Work", tags: ["a"], votePrompt: "Which?")
        XCTAssertEqual(try encodedKeys(params),
                       ["p_id", "p_caption", "p_group_id", "p_occasion", "p_tags", "p_vote_prompt"])
    }

    func testDraftParamsOldStyleOmitsTagsAndVotePrompt() throws {
        let params = DraftParams(id: UUID(), caption: "c", groupId: nil, occasion: nil, tags: nil, votePrompt: nil)
        let keys = try encodedKeys(params)
        XCTAssertEqual(keys, ["p_id", "p_caption"])
        XCTAssertFalse(keys.contains("p_tags"))
        XCTAssertFalse(keys.contains("p_vote_prompt"))
    }

    func testPhotoInsertEncodesColumnNamesAndOmitsEmptyDetails() throws {
        let plain = PhotoInsert(fitCheckId: UUID(), imageUrl: "u", position: 1, description: nil, tags: nil)
        XCTAssertEqual(try encodedKeys(plain), ["fit_check_id", "image_url", "position"])
        let detailed = PhotoInsert(fitCheckId: UUID(), imageUrl: "u", position: 2, description: "d", tags: ["t"])
        XCTAssertEqual(try encodedKeys(detailed), ["fit_check_id", "image_url", "position", "description", "tags"])
    }

    // MARK: Normaliser

    func testTagsAreTrimmedLowercasedAndDeduplicated() throws {
        let result = try FitCheckSubmission.normalizedTags(["  Work ", "work", "", "  ", "Date Night"])
        XCTAssertEqual(result, ["work", "date night"])
    }

    func testTagsAreCappedAtThirtyCharacters() throws {
        let result = try FitCheckSubmission.normalizedTags([String(repeating: "A", count: 45)])
        XCTAssertEqual(result, [String(repeating: "a", count: 30)])
    }

    func testMoreThanEightTagsThrowsFriendlyError() {
        let tags = (1...9).map { "tag\($0)" }
        XCTAssertThrowsError(try FitCheckSubmission.normalizedTags(tags)) { error in
            guard case APIError.message(let text) = error else { return XCTFail("Expected APIError.message") }
            XCTAssertTrue(text.contains("8"))
        }
        XCTAssertEqual(try FitCheckSubmission.normalizedTags((1...8).map { "tag\($0)" }).count, 8)
    }

    func testDuplicatesDoNotCountTowardTagLimit() throws {
        let tags = (1...8).map { "tag\($0)" } + ["TAG1", " tag2 "]
        XCTAssertEqual(try FitCheckSubmission.normalizedTags(tags).count, 8)
    }

    func testDescriptionIsTrimmedCappedAndNilWhenBlank() {
        XCTAssertNil(FitCheckSubmission.normalizedDescription("   \n"))
        XCTAssertNil(FitCheckSubmission.normalizedDescription(nil))
        XCTAssertEqual(FitCheckSubmission.normalizedDescription("  hi  "), "hi")
        XCTAssertEqual(FitCheckSubmission.normalizedDescription(String(repeating: "x", count: 300))?.count, 200)
    }

    func testVotePromptIsTrimmedAndCappedAtOneTwenty() {
        XCTAssertNil(FitCheckSubmission.normalizedVotePrompt("  "))
        XCTAssertEqual(FitCheckSubmission.normalizedVotePrompt(String(repeating: "y", count: 200))?.count, 120)
    }

    func testPhotoDetailsMustMatchPhotoCount() {
        let details = [PhotoDetail(description: "a", tags: [])]
        XCTAssertThrowsError(try FitCheckSubmission.normalizedDetails(details, photoCount: 2))
        XCTAssertEqual(try FitCheckSubmission.normalizedDetails([], photoCount: 2), [])
    }

    func testPhotoDetailsAreNormalizedPerPhoto() throws {
        let details = [PhotoDetail(description: " one ", tags: ["A", "a"]), PhotoDetail(description: " ", tags: [])]
        let result = try FitCheckSubmission.normalizedDetails(details, photoCount: 2)
        XCTAssertEqual(result, [PhotoDetail(description: "one", tags: ["a"]), PhotoDetail(description: "", tags: [])])
    }

    func testMissingSchemaErrorsAreRecognised() {
        XCTAssertTrue(API.isMissingColumnError(PostgrestError(code: "PGRST202", message: "Could not find the function")))
        XCTAssertTrue(API.isMissingColumnError(PostgrestError(code: "PGRST204", message: "Could not find the 'tags' column")))
        XCTAssertTrue(API.isMissingColumnError(PostgrestError(code: "42703", message: "x")))
        XCTAssertTrue(API.isMissingColumnError(PostgrestError(code: "42883", message: "x")))
        XCTAssertFalse(API.isMissingColumnError(PostgrestError(code: "PGRST200", message: "Could not find a relationship between 'a' and 'b' in the schema cache")))
        XCTAssertFalse(API.isMissingColumnError(PostgrestError(code: nil, message: "schema cache")))
        XCTAssertFalse(API.isMissingColumnError(URLError(.networkConnectionLost)))
        XCTAssertFalse(API.isMissingColumnError(PostgrestError(code: "23505", message: "duplicate key")))
        XCTAssertFalse(API.isMissingColumnError(APIError.message("nope")))
    }

    func testWizardLimitsMatchApiLimits() {
        XCTAssertEqual(CreateWizardModel.maxTags, FitCheckSubmission.maxTags)
        XCTAssertEqual(CreateWizardModel.maxTitleLength, FitCheckSubmission.maxVotePromptLength)
        XCTAssertEqual(CreateWizardModel.maxPhotoDescriptionLength, FitCheckSubmission.maxDescriptionLength)
    }

    // MARK: Feed column fallback and overlay copy

    func testPostCardOverlayContentRules() {
        // A person's name reads friendlier than a generated code, so the nickname wins.
        XCTAssertEqual(PostCardContent.handle(accountCode: "CLOV-AB12", nickname: "maya"), "@maya")
        XCTAssertEqual(PostCardContent.handle(accountCode: "CLOV-AB12", nickname: " "), "@CLOV-AB12")
        XCTAssertEqual(PostCardContent.handle(accountCode: " ", nickname: "maya"), "@maya")
        XCTAssertEqual(PostCardContent.handle(accountCode: nil, nickname: nil), "@someone")
        XCTAssertEqual(PostCardContent.overlayDescription(photoDescription: "photo", caption: "post"), "photo")
        XCTAssertEqual(PostCardContent.overlayDescription(photoDescription: " ", caption: "post"), "post")
        XCTAssertNil(PostCardContent.overlayDescription(photoDescription: nil, caption: nil))
        XCTAssertEqual(PostCardContent.displayTags(["a", " ", "b"], limit: 4), ["#a", "#b"])
    }

    func testStartingLookIsClamped() {
        XCTAssertEqual(ReelVoteModel.clampedLook(1, count: 2), 1)
        XCTAssertEqual(ReelVoteModel.clampedLook(5, count: 2), 0)
        XCTAssertEqual(ReelVoteModel.clampedLook(nil, count: 2), 0)
        XCTAssertEqual(ReelVoteModel.clampedLook(-1, count: 2), 0)
    }

    func testExploreTagFilterMatchesCaseInsensitively() {
        let tagged = FeedItemDTO(id: UUID(), creatorId: UUID(), createdAt: Date(), fitCheckPhotos: [],
                                 fitCheckVotes: [], fitCheckComments: [], tags: ["Denim"])
        let plain = FeedItemDTO(id: UUID(), creatorId: UUID(), createdAt: Date(), fitCheckPhotos: [],
                                fitCheckVotes: [], fitCheckComments: [])
        var filter = ExploreFilter()
        filter.tag = "denim"
        XCTAssertEqual(filter.apply(to: [tagged, plain]).map(\.id), [tagged.id])
        XCTAssertEqual(filter.activeCount, 1)
        XCTAssertEqual(ExploreFilter.availableTags(in: [tagged, plain]), ["denim"])
    }
}
