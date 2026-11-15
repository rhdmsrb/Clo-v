import XCTest
import Supabase
@testable import CLOV

final class FitCheckSubmissionTests: XCTestCase {
    private func encodedKeys<T: Encodable>(_ value: T) throws -> Set<String> {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try JSONSerialization.jsonObject(with: encoder.encode(value))
        return Set((object as? [String: Any] ?? [:]).keys)
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
        XCTAssertEqual(PostCardContent.handle(accountCode: "CLOV-AB12", nickname: "maya"), "@CLOV-AB12")
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
