import Foundation

/// User choices survive view refreshes; scheduling rules are independent of AppKit.
struct ReviewPlan {
  enum Choice: Int, CaseIterable {
    case later, today, tomorrow, date, completed

    var title: String {
      switch self {
      case .later: "Decide later"
      case .today: "Today"
      case .tomorrow: "Tomorrow"
      case .date: "Choose a date…"
      case .completed: "Already completed"
      }
    }
  }

  struct Selection {
    var choice: Choice = .later
    var date: Date
  }

  private var selections: [UUID: Selection] = [:]
  var hasUpdates: Bool { selections.values.contains { $0.choice != .later } }

  func selection(for id: UUID, today: Date, calendar: Calendar = .current) -> Selection {
    selections[id] ?? Selection(date: calendar.date(byAdding: .day, value: 2, to: today) ?? today)
  }

  mutating func set(_ selection: Selection, for id: UUID) { selections[id] = selection }
  mutating func retainTasks(_ ids: Set<UUID>) {
    selections = selections.filter { ids.contains($0.key) }
  }
  mutating func reset() { selections.removeAll() }

  func updates(for items: [TodoItem], today: Date, calendar: Calendar = .current)
    -> [TaskPlanUpdate]
  {
    let today = calendar.startOfDay(for: today)
    return items.compactMap { item in
      guard let selection = selections[item.id], selection.choice != .later else { return nil }
      let date: Date
      switch selection.choice {
      case .today: date = today
      case .tomorrow: date = calendar.date(byAdding: .day, value: 1, to: today) ?? today
      case .date: date = max(today, calendar.startOfDay(for: selection.date))
      case .completed:
        return TaskPlanUpdate(id: item.id, dayKey: item.dayKey, isCompleted: true)
      case .later: return nil
      }
      return TaskPlanUpdate(
        id: item.id, dayKey: DayKey.value(for: date, calendar: calendar), isCompleted: false)
    }
  }
}
