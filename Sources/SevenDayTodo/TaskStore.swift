import Foundation

struct TaskDraft {
  var title: String
  var notes: String
  var date: Date
  var isCompleted: Bool
}

@MainActor
final class TaskStore {
  private let tasks: any TaskRepository
  private(set) var items: [TodoItem] = []
  private(set) var days: [Date] = []
  private(set) var selectedTask: TodoItem?
  private(set) var draft: TaskDraft?
  private(set) var errorMessage: String?
  var onChange: (() -> Void)?

  init(repository: any TaskRepository) {
    tasks = repository
    returnToToday()
  }

  func returnToToday(now: Date = .now) {
    let today = Calendar.current.startOfDay(for: now)
    days = (-3...3).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    reload()
  }

  func shiftDays(_ offset: Int) {
    guard let first = days.first else { return }
    days = (0..<7).compactMap {
      Calendar.current.date(byAdding: .day, value: $0 + offset, to: first)
    }
    reload()
  }

  func items(for date: Date) -> [TodoItem] {
    items.filter { $0.dayKey == DayKey.value(for: date) }
  }

  func beginNewTask(on date: Date) {
    selectedTask = nil
    draft = TaskDraft(title: "", notes: "", date: date, isCompleted: false)
  }

  func beginEditing(_ item: TodoItem) {
    selectedTask = item
    draft = TaskDraft(
      title: item.title, notes: item.notes,
      date: DayKey.date(for: item.dayKey) ?? .now,
      isCompleted: item.isCompleted)
  }

  func setDraft(title: String, notes: String, date: Date, isCompleted: Bool) {
    guard draft != nil else { return }
    draft?.title = title
    draft?.notes = notes
    draft?.date = date
    draft?.isCompleted = isCompleted
  }

  @discardableResult
  func saveDraft() -> Bool {
    guard let draft else { return false }
    do {
      if let selectedTask {
        try tasks.update(
          id: selectedTask.id, title: draft.title, notes: draft.notes,
          dayKey: DayKey.value(for: draft.date), isCompleted: draft.isCompleted)
      } else {
        _ = try tasks.create(
          title: draft.title, notes: draft.notes,
          dayKey: DayKey.value(for: draft.date),
          isCompleted: draft.isCompleted)
      }
      closeEditor()
      reload()
      return true
    } catch {
      report(error)
      return false
    }
  }

  func closeEditor() {
    selectedTask = nil
    draft = nil
  }

  func toggle(_ item: TodoItem) { perform { try tasks.toggle(id: item.id) } }
  func delete(_ item: TodoItem) { perform { try tasks.delete(id: item.id) } }

  func move(itemID: UUID, to date: Date, at index: Int) {
    perform { try tasks.move(id: itemID, to: DayKey.value(for: date), at: index) }
  }

  func reload() {
    do {
      items = try tasks.tasks(dayKeys: days.map { DayKey.value(for: $0) })
      errorMessage = nil
      onChange?()
    } catch { report(error) }
  }

  private func perform(_ change: () throws -> Void) {
    do {
      try change()
      reload()
    } catch { report(error) }
  }

  private func report(_ error: Error) {
    errorMessage = error.localizedDescription
    onChange?()
  }
}
