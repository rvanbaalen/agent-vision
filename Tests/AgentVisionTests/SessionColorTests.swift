import Testing
@testable import AgentVisionShared

@Suite struct SessionColorTests {
    @Test func paletteHasSevenColors() {
        #expect(SessionColors.palette.count == 7)
    }

    @Test func colorForIndexWrapsAround() {
        let first = SessionColors.color(forIndex: 0)
        let wrapped = SessionColors.color(forIndex: 7)
        #expect(first.red == wrapped.red)
        #expect(first.green == wrapped.green)
        #expect(first.blue == wrapped.blue)
    }

    @Test func nextColorIndexStartsAtZero() {
        let existing: [Int] = []
        #expect(SessionColors.nextColorIndex(existing: existing) == 0)
    }

    @Test func nextColorIndexIncrementsSequentially() {
        #expect(SessionColors.nextColorIndex(existing: [0]) == 1)
        #expect(SessionColors.nextColorIndex(existing: [0, 1]) == 2)
    }

    @Test func nextColorIndexFillsGaps() {
        // If session with color 1 was removed, next should still be max+1
        #expect(SessionColors.nextColorIndex(existing: [0, 2]) == 3)
    }
}
