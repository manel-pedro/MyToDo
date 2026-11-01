import Foundation

struct TaskDraft {
  var title: String
  var notes: String
  var date: Date
  var isCompleted: Bool
}

@MainActor
final class TaskStore {
  enum ViewMode { case days, month }

  private(set) var viewMode: ViewMode = .days
  private(set) var focusedDate: Date = Calendar.current.startOfDay(for: .now)
  private let tasks: any TaskRepository
  private(set) var items: [TodoItem] = []
  private(set) var unfinishedItems: [TodoItem] = []
  private var reviewUndo: [TaskPlanUpdate]?
  var canUndoReview: Bool { reviewUndo != nil }
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
    focusedDate = Calendar.current.startOfDay(for: now)
    updateDays()
  }

  func setViewMode(_ mode: ViewMode) {
    viewMode = mode
    updateDays()
  }

  func shiftDays(_ offset: Int) {
    guard let date = Calendar.current.date(
      byAdding: viewMode == .month ? .month : .day, value: offset, to: focusedDate)
    else { return }
    focusedDate = date
    updateDays()
  }

  private func updateDays() {
    let calendar = Calendar.current
    if viewMode == .month,
      let month = calendar.dateInterval(of: .month, for: focusedDate),
      let count = calendar.range(of: .day, in: .month, for: focusedDate)
    {
      let padding = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
      let cellCount = ((padding + count.count + 6) / 7) * 7
      days = (0..<cellCount).compactMap {
        calendar.date(byAdding: .day, value: $0 - padding, to: month.start)
      }
    } else {
      days = (-1...2).compactMap {
        calendar.date(byAdding: .day, value: $0, to: focusedDate)
      }
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
      reviewUndo = nil
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

  @discardableResult
  func applyReviewPlan(_ updates: [TaskPlanUpdate]) -> Bool {
    let originals = unfinishedItems.filter { item in updates.contains { $0.id == item.id } }
      .sorted { ($0.dayKey, $0.sortOrder) < ($1.dayKey, $1.sortOrder) }
    guard !updates.isEmpty, originals.count == updates.count else { return false }
    let undo = originals.map {
      TaskPlanUpdate(id: $0.id, dayKey: $0.dayKey, isCompleted: $0.isCompleted,
                     destinationIndex: Int($0.sortOrder))
    }
    do {
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
    do {
      try tasks.applyPlan(reviewUndo)
      self.reviewUndo = nil
      reload()
    } catch { report(error) }
  }

  func reload(now: Date = .now) {
    do {
      let visible = try tasks.tasks(dayKeys: days.map { DayKey.value(for: $0) })
      let unfinished = try tasks.unfinishedTasks(before: DayKey.value(for: now))
      items = visible
      unfinishedItems = unfinished
      errorMessage = nil
      onChange?()
    } catch { report(error) }
  }

  private func perform(_ change: () throws -> Void) {
    do {
      try change()
      reviewUndo = nil
      reload()
    } catch { report(error) }
  }

  private func report(_ error: Error) {
    errorMessage = error.localizedDescription
    onChange?()
  }
}
