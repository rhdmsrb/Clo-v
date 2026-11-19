import XCTest
@testable import CLOV

final class DraftSweepTests: XCTestCase {
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
