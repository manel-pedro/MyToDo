import Foundation

struct TaskDraft {
  var title: String
  var notes: String
  var date: Date
  var isCompleted: Bool
}

@MainActor
final class TaskStore {
  typealias ViewMode = BoardCalendar.ViewMode
  private let tasks: any TaskRepository
  private let now: () -> Date
  private var dateRange: BoardCalendar
  private var itemsByDay: [String: [TodoItem]] = [:]
  private var reviewUndo: [TaskPlanUpdate]?
  private(set) var items: [TodoItem] = []
  private(set) var unfinishedItems: [TodoItem] = []
  private(set) var selectedTask: TodoItem?
  private(set) var draft: TaskDraft?
  private(set) var errorMessage: String?
  var onChange: (() -> Void)?

  var viewMode: ViewMode { dateRange.viewMode }
  var focusedDate: Date { dateRange.focusedDate }
  var days: [Date] { dateRange.days }
  var canUndoReview: Bool { reviewUndo != nil }

  init(
    repository: any TaskRepository, calendar: Calendar = .current,
    now: @escaping () -> Date = Date.init
  ) {
    tasks = repository
    self.now = now
    dateRange = BoardCalendar(calendar: calendar, today: now())
    reload()
  }

  func returnToToday(now date: Date? = nil) {
    dateRange.returnToToday(date ?? now())
    reload()
  }

  func setViewMode(_ mode: ViewMode) {
    guard viewMode != mode else { return }
    dateRange.setViewMode(mode)
    reload()
  }

  func shiftDays(_ offset: Int) {
    guard offset != 0 else { return }
    dateRange.shift(offset)
    reload()
  }

  func items(for date: Date) -> [TodoItem] {
    itemsByDay[DayKey.value(for: date, calendar: dateRange.calendar)] ?? []
  }

  func beginNewTask(on date: Date) {
    selectedTask = nil
    draft = TaskDraft(title: "", notes: "", date: date, isCompleted: false)
  }

  func beginEditing(_ item: TodoItem) {
    selectedTask = item
    draft = TaskDraft(
      title: item.title, notes: item.notes,
      date: DayKey.date(for: item.dayKey, calendar: dateRange.calendar) ?? now(),
      isCompleted: item.isCompleted)
  }

  func setDraft(title: String, notes: String, date: Date, isCompleted: Bool) {
    guard draft != nil else { return }
    draft = TaskDraft(title: title, notes: notes, date: date, isCompleted: isCompleted)
  }

  @discardableResult
  func saveDraft() -> Bool {
    guard let draft else { return false }
    return perform {
      let dayKey = DayKey.value(for: draft.date, calendar: dateRange.calendar)
      if let selectedTask {
        try tasks.update(
          id: selectedTask.id, title: draft.title, notes: draft.notes,
          dayKey: dayKey, isCompleted: draft.isCompleted)
      } else {
        _ = try tasks.create(
          title: draft.title, notes: draft.notes,
          dayKey: dayKey, isCompleted: draft.isCompleted)
      }
      // Close only after the repository commits; a failed save retains the draft.
      closeEditor()
    }
  }

  func closeEditor() {
    selectedTask = nil
    draft = nil
  }

  @discardableResult
  func toggle(_ item: TodoItem) -> Bool { perform { try tasks.toggle(id: item.id) } }
  @discardableResult
  func delete(_ item: TodoItem) -> Bool { perform { try tasks.delete(id: item.id) } }

  @discardableResult
  func move(itemID: UUID, to date: Date, at index: Int) -> Bool {
    perform {
      try tasks.move(
        id: itemID,
        to: DayKey.value(for: date, calendar: dateRange.calendar), at: index)
    }
  }

  @discardableResult
  func applyReviewPlan(_ updates: [TaskPlanUpdate]) -> Bool {
    guard !updates.isEmpty else { return false }
    do {
      let ids = Set(updates.map(\.id))
      guard ids.count == updates.count else { throw TaskError.duplicatePlanItem }
      let originals = unfinishedItems.filter { ids.contains($0.id) }
      guard originals.count == ids.count else { throw TaskError.invalidReview }
      // Use actual positions, not a conversion from persisted floating-point sortOrder.
      let originalDays = Array(Set(originals.map(\.dayKey)))
      let groups = Dictionary(grouping: try tasks.tasks(dayKeys: originalDays), by: \.dayKey)
      let positions = groups.values.reduce(into: [UUID: Int]()) { result, items in
        for (index, item) in items.enumerated() { result[item.id] = index }
      }
      let undo = originals.map {
        TaskPlanUpdate(
          id: $0.id, dayKey: $0.dayKey, isCompleted: $0.isCompleted,
          destinationIndex: positions[$0.id])
      }.sorted { ($0.dayKey, $0.destinationIndex ?? 0) < ($1.dayKey, $1.destinationIndex ?? 0) }
      try tasks.applyPlan(updates)
      reviewUndo = undo
      reload()
      return true
    } catch {
      report(error)
      return false
    }
  }

  func undoReviewPlan() {
    guard let reviewUndo else { return }
    _ = perform { try tasks.applyPlan(reviewUndo) }
  }

  func reload(now date: Date? = nil) {
    do {
      let visible = try tasks.tasks(
        dayKeys: days.map { DayKey.value(for: $0, calendar: dateRange.calendar) })
      let unfinished = try tasks.unfinishedTasks(
        before: DayKey.value(for: date ?? now(), calendar: dateRange.calendar))
      items = visible
      itemsByDay = Dictionary(grouping: visible, by: \.dayKey)
      unfinishedItems = unfinished
      errorMessage = nil
      onChange?()
    } catch { report(error) }
  }

  @discardableResult
  private func perform(_ change: () throws -> Void) -> Bool {
    do {
      try change()
      reviewUndo = nil
      reload()
      return true
    } catch {
      report(error)
      return false
    }
  }

  private func report(_ error: Error) {
    errorMessage = error.localizedDescription
    onChange?()
  }
}
