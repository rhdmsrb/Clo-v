import XCTest
@testable import CLOV

final class PostProgressTests: XCTestCase {
    private func progress(draftFingerprint: String = "d", photos: [String] = []) -> PostProgress {
        PostProgress(draftId: UUID(), draftFingerprint: draftFingerprint, draftDropped: false,
                     photos: photos.map { UploadedPhoto(fingerprint: $0, path: "p/\($0)", rowInserted: true) })
    }

    func testNoPreviousAttemptStartsFresh() {
        XCTAssertEqual(PostResume.decide(nil, draftFingerprint: "d", photoFingerprints: ["a", "b"], serverState: .draft), .fresh)
    }

    func testMatchingAttemptResumes() {
        XCTAssertEqual(PostResume.decide(progress(photos: ["a"]), draftFingerprint: "d",
                                         photoFingerprints: ["a", "b"], serverState: .draft), .resume)
    }

    func testAttemptWithNoPhotosYetResumes() {
        XCTAssertEqual(PostResume.decide(progress(), draftFingerprint: "d",
                                         photoFingerprints: ["a", "b"], serverState: .draft), .resume)
    }

    func testChangedDetailsDiscardTheOldAttempt() {
        XCTAssertEqual(PostResume.decide(progress(draftFingerprint: "old", photos: ["a"]), draftFingerprint: "new",
                                         photoFingerprints: ["a", "b"], serverState: .draft), .discardThenFresh)
    }

    func testReplacedPhotoDiscardsTheOldAttempt() {
        XCTAssertEqual(PostResume.decide(progress(photos: ["a", "b"]), draftFingerprint: "d",
                                         photoFingerprints: ["a", "different"], serverState: .draft), .discardThenFresh)
    }

    func testFewerPhotosThanAlreadyUploadedDiscards() {
        XCTAssertEqual(PostResume.decide(progress(photos: ["a", "b", "c", "d"]), draftFingerprint: "d",
                                         photoFingerprints: ["a", "b"], serverState: .draft), .discardThenFresh)
    }

    func testLivePostMeansAlreadyPublishedEvenIfEdited() {
        XCTAssertEqual(PostResume.decide(progress(draftFingerprint: "old"), draftFingerprint: "new",
                                         photoFingerprints: ["a"], serverState: .live), .alreadyPublished)
    }

    func testMissingDraftStartsOver() {
        XCTAssertEqual(PostResume.decide(progress(photos: ["a"]), draftFingerprint: "d",
                                         photoFingerprints: ["a", "b"], serverState: .missing), .discardThenFresh)
    }

    func testUnknownServerStateStillResumes() {
        XCTAssertEqual(PostResume.decide(progress(photos: ["a"]), draftFingerprint: "d",
                                         photoFingerprints: ["a", "b"], serverState: .unknown), .resume)
    }

    func testPhotoFingerprintIsStableAndContentSensitive() {
        let a = Data([1, 2, 3]), b = Data([1, 2, 4])
        XCTAssertEqual(PostResume.fingerprint(of: a), PostResume.fingerprint(of: a))
        XCTAssertNotEqual(PostResume.fingerprint(of: a), PostResume.fingerprint(of: b))
    }

    func testDraftFingerprintChangesWithAnyField() {
        let group = UUID()
        func fp(caption: String? = "c", occasion: String? = "o", groupId: UUID? = nil, tags: [String] = ["t"],
                prompt: String? = "p", audience: String = "public") -> String {
            PostResume.draftFingerprint(caption: caption, occasion: occasion, groupId: groupId, tags: tags,
                                        votePrompt: prompt, audience: audience)
        }
        let base = fp()
        XCTAssertEqual(base, fp())
        XCTAssertNotEqual(base, fp(caption: "x"))
        XCTAssertNotEqual(base, fp(occasion: nil))
        XCTAssertNotEqual(base, fp(groupId: group))
        XCTAssertNotEqual(base, fp(tags: ["t", "u"]))
        XCTAssertNotEqual(base, fp(prompt: nil))
        XCTAssertNotEqual(base, fp(audience: "friends"))
    }

    func testUploadedPathsListEveryStoredFile() {
        XCTAssertEqual(progress(photos: ["a", "b"]).uploadedPaths, ["p/a", "p/b"])
    }
}
