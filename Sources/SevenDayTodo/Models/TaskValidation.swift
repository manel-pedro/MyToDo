import Foundation

enum TaskValidation {
  static func dayKey(_ value: String) throws {
    guard DayKey.date(for: value) != nil else { throw TaskError.invalidDayKey(value) }
  }

  static func tasks(_ items: [TodoItem]) throws {
    var ids = Set<UUID>()
    for item in items {
      guard ids.insert(item.id).inserted else { throw TaskError.duplicateTaskID }
      try dayKey(item.dayKey)
      guard item.sortOrder.isFinite else { throw TaskError.invalidSortOrder }
    }
  }
}
