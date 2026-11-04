import XCTest
@testable import CLOV

@MainActor
final class ResultShareImageTests: XCTestCase {
    private func rows(count: Int) -> [ResultShareImage.Row] {
        (1...count).map { position in
            ResultShareImage.Row(id: UUID(), position: position, percent: position == 1 ? 63 : 37 / (count - 1),
                                 imageURL: nil, isLeading: position == 1, isMine: position == 1)
        }
    }

    private func render(showsPhotos: Bool, count: Int = 2, prompt: String? = "Which one feels more effortless?") async throws -> UIImage {
        let item = ResultShareImage(prompt: prompt, totalVotes: 41, rows: rows(count: count), showsPhotos: showsPhotos)
        let data = try await item.renderPNG()
        return try XCTUnwrap(UIImage(data: data))
    }

    func testRendersBarsOnlyCardAsPNG() async throws {
        let image = try await render(showsPhotos: false)
        XCTAssertEqual(image.size.width * image.scale, 1080, accuracy: 1)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testRendersCreatorCardWithPlaceholdersWhenPhotosMissing() async throws {
        let image = try await render(showsPhotos: true, count: 4)
        XCTAssertEqual(image.size.width * image.scale, 1080, accuracy: 1)
    }

    func testBlankPromptFallsBackToDefaultQuestion() async throws {
        let image = try await render(showsPhotos: false, prompt: "   ")
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testFourLookCardIsTallerThanTwoLookCard() async throws {
        let two = try await render(showsPhotos: true, count: 2)
        let four = try await render(showsPhotos: true, count: 4)
        XCTAssertNotEqual(two.size.height, four.size.height)
    }
}
