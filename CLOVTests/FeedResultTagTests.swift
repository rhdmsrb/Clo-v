import Testing
@testable import CLOV

struct FeedResultTagTests {
    @Test("The result tag spells out the viewer's pick and the leader instead of icons")
    func resultTagText() {
        #expect(HomeFitCard.resultTagText(percent: 63, isMine: true, isLeading: true) == "63% · Your pick · Top")
        #expect(HomeFitCard.resultTagText(percent: 37, isMine: false, isLeading: false) == "37%")
        #expect(HomeFitCard.resultTagText(percent: 50, isMine: false, isLeading: true) == "50% · Top")
    }
}
