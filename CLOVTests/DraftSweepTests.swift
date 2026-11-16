import XCTest
@testable import CLOV

final class DraftSweepTests: XCTestCase {
    func testCutoffIsOneHourBeforeNow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(DraftSweep.cutoff(now: now), now.addingTimeInterval(-3600))
    }

    /// A post in progress is seconds or minutes old; only leftovers are older than the cutoff.
    func testADraftYoungerThanTheCutoffIsNotStale() {
        let now = Date()
        XCTAssertFalse(DraftSweep.isStale(createdAt: now.addingTimeInterval(-600), now: now))
        XCTAssertTrue(DraftSweep.isStale(createdAt: now.addingTimeInterval(-7200), now: now))
    }

    func testStoragePathsUseLowercaseOwnerAndDraftFolders() {
        let owner = UUID(), draft = UUID()
        let paths = DraftSweep.storagePaths(creatorId: owner, draftId: draft, fileNames: ["a.jpg", "b.jpg"])
        XCTAssertEqual(paths, ["\(owner.uuidString.lowercased())/\(draft.uuidString.lowercased())/a.jpg",
                               "\(owner.uuidString.lowercased())/\(draft.uuidString.lowercased())/b.jpg"])
    }

    func testStoragePathsSkipBlankNames() {
        let paths = DraftSweep.storagePaths(creatorId: UUID(), draftId: UUID(), fileNames: ["", "  ", "a.jpg"])
        XCTAssertEqual(paths.count, 1)
    }
}
