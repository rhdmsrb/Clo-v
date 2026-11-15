import Testing
import CoreGraphics
@testable import CLOV

struct GroupsLogicTests {
    private func eval(_ offset: CGFloat, last: CGFloat = 0, content: CGFloat = 2000, viewport: CGFloat = 600)
        -> AvatarRowScrollRule.Result {
        AvatarRowScrollRule.evaluate(offset: offset, lastOffset: last, contentHeight: content, viewportHeight: viewport)
    }

    @Test func scrollingDownBeyondThresholdHides() {
        #expect(eval(-20).shouldShow == false)
    }

    @Test func smallMovementIsIgnored() {
        let r = eval(-24, last: -20)
        #expect(r.shouldShow == nil)
        #expect(r.anchor == -20)
    }

    @Test func scrollingUpShows() {
        #expect(eval(-100, last: -150).shouldShow == true)
    }

    @Test func topOverscrollShows() {
        #expect(eval(40, last: -100).shouldShow == true)
    }

    @Test func bottomBounceDoesNotShowRow() {
        // Max scroll is 1400; the bounce overshoots to -1450 and returns.
        let atBottom = eval(-1400, last: -1300)
        #expect(atBottom.shouldShow == false)
        let bounce = eval(-1450, last: atBottom.anchor)
        #expect(bounce.shouldShow == nil)
        let back = eval(-1405, last: atBottom.anchor)
        #expect(back.shouldShow == nil)
    }

    @Test func shortContentNeverHides() {
        #expect(eval(-30, content: 500, viewport: 600).shouldShow == true)
    }

    @Test func nameValidatorTrimsAndChecksLength() throws {
        #expect(try GroupNameValidator.validated("  Ab  ") == "Ab")
        #expect(throws: (any Error).self) { try GroupNameValidator.validated(" a ") }
        #expect(throws: (any Error).self) { try GroupNameValidator.validated("   ") }
        #expect(throws: (any Error).self) { try GroupNameValidator.validated(String(repeating: "x", count: 41)) }
        #expect(try GroupNameValidator.validated(String(repeating: "x", count: 40)).count == 40)
    }

    @Test func inviteCodeNormalizes() {
        #expect(InviteCodeInput.normalize(" ab c 2 34 ") == "ABC234")
    }

    @Test func inviteCodeAmbiguityDetected() {
        #expect(InviteCodeInput.hasAmbiguousCharacters("abc0de"))
        #expect(InviteCodeInput.hasAmbiguousCharacters("Il2345"))
        #expect(!InviteCodeInput.hasAmbiguousCharacters("ABC234"))
        #expect(!InviteCodeInput.hasAmbiguousCharacters(""))
    }
}
