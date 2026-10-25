import Foundation
import Testing
@testable import PackFit

struct DateRangeSelectionTests {
    private let cal = Calendar.current
    private let today = Calendar.current.startOfDay(for: .now)

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: today)!
    }

    @Test func firstTapSetsDepartSecondSetsReturn() {
        var s = DateRangeSelection()
        s.tap(day(3))
        #expect(s.start == day(3) && s.end == nil && s.isPickingReturn)
        s.tap(day(10))
        #expect(s.end == day(10))
        #expect(s.nights == 7)
    }

    @Test func tapBeforeOrOnDepartRestartsRange() {
        var s = DateRangeSelection()
        s.tap(day(5))
        s.tap(day(2))
        #expect(s.start == day(2) && s.end == nil)
        s.tap(day(2))
        #expect(s.start == day(2) && s.end == nil)
    }

    @Test func tapAfterFullRangeStartsOver() {
        var s = DateRangeSelection(start: day(1), end: day(4))
        s.tap(day(8))
        #expect(s.start == day(8) && s.end == nil)
    }

    @Test func pastDaysAndLongTripsAreDisabled() {
        let s = DateRangeSelection(start: day(0), end: nil)
        #expect(s.isDisabled(day(-1), today: today))
        #expect(!s.isDisabled(day(DateRangeSelection.maxNights), today: today))
        #expect(s.isDisabled(day(DateRangeSelection.maxNights + 1), today: today))
        let full = DateRangeSelection(start: day(0), end: day(3))
        #expect(!full.isDisabled(day(200), today: today))
    }
}
