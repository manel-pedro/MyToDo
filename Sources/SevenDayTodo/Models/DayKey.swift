import Foundation

enum DayKey {
  static func value(for date: Date, calendar: Calendar = .current) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }

  static func date(for key: String, calendar: Calendar = .current) -> Date? {
    let parts = key.split(separator: "-")
    guard parts.count == 3,
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
      let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
      value(for: date, calendar: calendar) == key
    else { return nil }
    return date
  }
}
