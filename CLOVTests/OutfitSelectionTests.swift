import XCTest
@testable import CLOV

final class OutfitSelectionTests: XCTestCase {
    private func item(_ category: String) -> WardrobeItem {
        WardrobeItem(id: UUID(), ownerId: UUID(), imageUrl: "", name: nil, category: category)
    }

    func testAddingToEmptySelectionSelectsItem() {
        let top = item("top")
        XCTAssertEqual(OutfitSelection.toggling(top, selected: [], in: [top]), [top.id])
    }

    func testTappingSelectedItemDeselectsIt() {
        let top = item("top")
        XCTAssertEqual(OutfitSelection.toggling(top, selected: [top.id], in: [top]), [])
    }

    func testNewTopReplacesExistingTopAndKeepsBottom() {
        let oldTop = item("top"), newTop = item("top"), bottom = item("bottom")
        let result = OutfitSelection.toggling(newTop, selected: [oldTop.id, bottom.id], in: [oldTop, newTop, bottom])
        XCTAssertEqual(result, [newTop.id, bottom.id])
    }

    func testOuterwearReplacesTopBecauseTheyShareUpperBodySlot() {
        let top = item("top"), coat = item("outerwear")
        XCTAssertEqual(OutfitSelection.toggling(coat, selected: [top.id], in: [top, coat]), [coat.id])
    }

    func testDressReplacesTopBottomAndOuterwearButKeepsShoes() {
        let top = item("top"), bottom = item("bottom"), coat = item("outerwear")
        let shoes = item("shoes"), dress = item("dress")
        let all = [top, bottom, coat, shoes, dress]
        let result = OutfitSelection.toggling(dress, selected: [top.id, bottom.id, coat.id, shoes.id], in: all)
        XCTAssertEqual(result, [dress.id, shoes.id])
    }

    func testBottomReplacesDressButKeepsTop() {
        let dress = item("dress"), bottom = item("bottom"), top = item("top")
        let result = OutfitSelection.toggling(bottom, selected: [dress.id, top.id], in: [dress, bottom, top])
        XCTAssertEqual(result, [bottom.id, top.id])
    }

    func testTopReplacesDress() {
        let dress = item("dress"), top = item("top")
        XCTAssertEqual(OutfitSelection.toggling(top, selected: [dress.id], in: [dress, top]), [top.id])
    }

    func testOnlyOneItemPerOtherCategory() {
        let shoesA = item("shoes"), shoesB = item("shoes")
        XCTAssertEqual(OutfitSelection.toggling(shoesB, selected: [shoesA.id], in: [shoesA, shoesB]), [shoesB.id])
    }
}

final class OutfitSelectionResolveTests: XCTestCase {
    private func item() -> WardrobeItem {
        WardrobeItem(id: UUID(), ownerId: UUID(), imageUrl: "", name: nil, category: "top")
    }

    func testAllPiecesPresent() {
        let a = item(), b = item()
        let result = OutfitSelection.resolve([a.id, b.id], in: [a, b])
        XCTAssertEqual(result.present, [a.id, b.id])
        XCTAssertEqual(result.missingCount, 0)
    }

    func testDeletedPiecesAreCountedAsMissing() {
        let a = item(), gone = UUID()
        let result = OutfitSelection.resolve([a.id, gone], in: [a])
        XCTAssertEqual(result.present, [a.id])
        XCTAssertEqual(result.missingCount, 1)
    }

    func testEmptyLookResolvesToNothing() {
        let result = OutfitSelection.resolve([], in: [item()])
        XCTAssertTrue(result.present.isEmpty)
        XCTAssertEqual(result.missingCount, 0)
    }
}
