import XCTest
@testable import CLOV

final class PhotoCommentsTests: XCTestCase {
    private let photoA = UUID()
    private let photoB = UUID()

    private func comment(_ body: String, photo: UUID?) -> CommentDTO {
        CommentDTO(id: UUID(), body: body, createdAt: Date(), profiles: nil, photoId: photo)
    }

    func testShowsOnlyThePhotosOwnCommentsPlusGeneralOnes() {
        let all = [comment("a1", photo: photoA), comment("b1", photo: photoB), comment("general", photo: nil)]
        let shown = PhotoComments.visible(all, photoId: photoA).map(\.body)
        XCTAssertEqual(shown, ["a1", "general"])
    }

    func testPhotoOwnCommentsComeBeforeGeneralOnesAndKeepOrder() {
        let all = [comment("general", photo: nil), comment("a1", photo: photoA), comment("a2", photo: photoA)]
        XCTAssertEqual(PhotoComments.visible(all, photoId: photoA).map(\.body), ["a1", "a2", "general"])
    }

    func testUnknownPhotoShowsOnlyGeneralComments() {
        let all = [comment("a1", photo: photoA), comment("general", photo: nil)]
        XCTAssertEqual(PhotoComments.visible(all, photoId: UUID()).map(\.body), ["general"])
        XCTAssertEqual(PhotoComments.visible(all, photoId: nil).map(\.body), ["general"])
    }

    func testCountCountsOnlyCommentsTiedToThatPhoto() {
        let all = [comment("a1", photo: photoA), comment("a2", photo: photoA), comment("b1", photo: photoB), comment("general", photo: nil)]
        XCTAssertEqual(PhotoComments.count(all, photoId: photoA), 2)
        XCTAssertEqual(PhotoComments.count(all, photoId: photoB), 1)
        XCTAssertEqual(PhotoComments.count([], photoId: photoA), 0)
    }
}
