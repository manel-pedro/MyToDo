import Foundation

/// Calendar navigation without any persistence or view concerns.
struct BoardCalendar {
  enum ViewMode { case days, month }
  let calendar: Calendar
  private(set) var viewMode: ViewMode = .days
  private(set) var focusedDate: Date
  private var preferredDay: Int

  init(calendar: Calendar = .current, today: Date) {
    self.calendar = calendar
    focusedDate = calendar.startOfDay(for: today)
    preferredDay = calendar.component(.day, from: today)
  }

  var days: [Date] {
    if viewMode == .month,
      let month = calendar.dateInterval(of: .month, for: focusedDate),
      let count = calendar.range(of: .day, in: .month, for: focusedDate)
    {
      let padding =
        (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
      let cellCount = ((padding + count.count + 6) / 7) * 7
      return (0..<cellCount).compactMap {
        calendar.date(byAdding: .day, value: $0 - padding, to: month.start)
      }
    }
    return (-1...2).compactMap { calendar.date(byAdding: .day, value: $0, to: focusedDate) }
  }

  mutating func returnToToday(_ today: Date) {
    focusedDate = calendar.startOfDay(for: today)
    preferredDay = calendar.component(.day, from: today)
  }

  mutating func setViewMode(_ mode: ViewMode) { viewMode = mode }

  mutating func shift(_ offset: Int) {
    if viewMode == .month {
      guard let start = calendar.dateInterval(of: .month, for: focusedDate)?.start,
        let target = calendar.date(byAdding: .month, value: offset, to: start),
        let days = calendar.range(of: .day, in: .month, for: target),
        let date = calendar.date(
          byAdding: .day, value: min(preferredDay, days.count) - 1, to: target)
      else { return }
      focusedDate = date
    } else if let date = calendar.date(byAdding: .day, value: offset, to: focusedDate) {
      focusedDate = date
      preferredDay = calendar.component(.day, from: date)
    }
  }
}
