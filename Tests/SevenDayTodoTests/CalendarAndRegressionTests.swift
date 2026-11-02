import Foundation

@MainActor
final class CalendarAndRegressionTests {
  func testDayKeysRoundTripAcrossDSTAndTimeZones() throws {
    for zone in ["Europe/Copenhagen", "America/New_York", "Pacific/Auckland", "UTC"] {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = try Checks.unwrap(TimeZone(identifier: zone))
      for key in ["2026-03-29", "2026-10-25", "2028-02-29", "2026-12-31", "2027-01-01"] {
        let date = try Checks.unwrap(DayKey.date(for: key, calendar: calendar), "\(zone): \(key)")
        try Checks.require(DayKey.value(for: date, calendar: calendar) == key, "\(zone)")
      }
    }
  }

  func testInvalidDayKeysAreRejected() throws {
    for key in ["", "2026-02-29", "2026-02-31", "2026-13-01", "2026-00-01", "2026-01-00", "2026-1-2", "abc", "2026-01-01-extra"] {
      try Checks.require(DayKey.date(for: key) == nil, "\(key)")
    }
  }

  func testMonthNavigationFromLastDayStaysInAdjacentMonth() throws {
    let store = TaskStore(repository: try LocalTaskRepository(storage: TestStorage()))
    store.returnToToday(now: try Checks.unwrap(DayKey.date(for: "2028-01-31")))
    store.setViewMode(.month)
    store.shiftDays(1)
    try Checks.require(DayKey.value(for: store.focusedDate) == "2028-02-29")
    try Checks.require(store.days.filter { Calendar.current.component(.month, from: $0) == 2 }.count == 29)
  }

}

@MainActor
extension CalendarAndRegressionTests {
  static var checks: [(String, () throws -> Void)] {
    let suite = CalendarAndRegressionTests()
    return [
      ("CalendarAndRegressionTests.testDayKeysRoundTripAcrossDSTAndTimeZones", { try suite.testDayKeysRoundTripAcrossDSTAndTimeZones() }),
      ("CalendarAndRegressionTests.testInvalidDayKeysAreRejected", { try suite.testInvalidDayKeysAreRejected() }),
      ("CalendarAndRegressionTests.testMonthNavigationFromLastDayStaysInAdjacentMonth", { try suite.testMonthNavigationFromLastDayStaysInAdjacentMonth() }),
    ]
  }
}
