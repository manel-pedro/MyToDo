import Foundation

@MainActor
final class TaskStoreTests {
  func testFailedSaveRetainsDraftAndSelectionThenCanRetry() throws {
    let storage = TestStorage()
    let repository = try LocalTaskRepository(storage: storage)
    let task = try createTask(repository)
    let store = TaskStore(repository: repository)
    store.beginEditing(task)
    store.setDraft(title: "Edited", notes: "Unsaved notes", date: try Checks.unwrap(DayKey.date(for: task.dayKey)), isCompleted: true)
    storage.rejectWrites = true
    try Checks.require(!(store.saveDraft()))
    try Checks.require(store.selectedTask?.id == task.id)
    try Checks.require(store.draft?.notes == "Unsaved notes")
    try Checks.require(store.errorMessage != nil)
    try Checks.require(storage.items.first?.notes == "Original notes")
    storage.rejectWrites = false
    try Checks.require(store.saveDraft())
    try Checks.require(store.draft == nil)
    try Checks.require(store.selectedTask == nil)
    try Checks.require(store.errorMessage == nil)
    try Checks.require(storage.items.first?.notes == "Unsaved notes")
    try Checks.require(storage.items.first?.id == task.id)
  }

  func testClosingAnEditedDraftDiscardsChanges() throws {
    let repository = try LocalTaskRepository(storage: TestStorage())
    let task = try createTask(repository)
    let store = TaskStore(repository: repository)
    store.beginEditing(task)
    store.setDraft(title: "Discard", notes: "Discard", date: .now, isCompleted: true)
    store.closeEditor()
    try Checks.require(store.draft == nil)
    try Checks.require(store.selectedTask == nil)
    try Checks.require(try repository.tasks(dayKeys: [task.dayKey]).first?.title == task.title)
  }

  func testSavingNewDraftOnceDoesNotCreateDuplicates() throws {
    let storage = TestStorage()
    let store = TaskStore(repository: try LocalTaskRepository(storage: storage))
    store.beginNewTask(on: .now)
    store.setDraft(title: "New task", notes: "Notes", date: .now, isCompleted: false)
    try Checks.require(store.saveDraft())
    try Checks.require(!(store.saveDraft()))
    try Checks.require(storage.items.count == 1)
    try Checks.require(storage.writes == 1)
  }

  func testBlankDraftSaveCanBeCorrectedWithoutLosingNotes() throws {
    let storage = TestStorage()
    let store = TaskStore(repository: try LocalTaskRepository(storage: storage))
    store.beginNewTask(on: .now)
    store.setDraft(title: " \n", notes: "Keep these notes", date: .now, isCompleted: false)
    try Checks.require(!(store.saveDraft()))
    try Checks.require(store.draft?.notes == "Keep these notes")
    try Checks.require(storage.items.isEmpty)
    let draft = try Checks.unwrap(store.draft)
    store.setDraft(title: "Corrected", notes: draft.notes, date: .now, isCompleted: false)
    try Checks.require(store.saveDraft())
    try Checks.require(store.errorMessage == nil)
    try Checks.require(storage.items.first?.notes == "Keep these notes")
  }

  func testFailedUndoCanBeRetriedWithoutPartialRestoration() throws {
    let storage = TestStorage()
    let repository = try LocalTaskRepository(storage: storage)
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
    let task = try createTask(repository, day: DayKey.value(for: yesterday))
    let store = TaskStore(repository: repository)
    let today = DayKey.value(for: .now)
    try Checks.require(store.applyReviewPlan([TaskPlanUpdate(id: task.id, dayKey: today, isCompleted: false)]))
    storage.rejectWrites = true
    store.undoReviewPlan()
    try Checks.require(store.canUndoReview)
    try Checks.require(store.errorMessage != nil)
    try Checks.require(storage.items.first?.dayKey == today)
    storage.rejectWrites = false
    store.undoReviewPlan()
    try Checks.require(!(store.canUndoReview))
    try Checks.require(store.errorMessage == nil)
    try Checks.require(store.unfinishedItems.map(\.id) == [task.id])
  }

  func testEditingAfterReviewInvalidatesUndo() throws {
    let repository = try LocalTaskRepository(storage: TestStorage())
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
    let task = try createTask(repository, day: DayKey.value(for: yesterday))
    let store = TaskStore(repository: repository)
    try Checks.require(store.applyReviewPlan([TaskPlanUpdate(id: task.id, dayKey: task.dayKey, isCompleted: true)]))
    try Checks.require(store.canUndoReview)
    store.beginEditing(try Checks.unwrap(try repository.tasks(dayKeys: [task.dayKey]).first))
    store.setDraft(title: "Edited", notes: "", date: yesterday, isCompleted: true)
    try Checks.require(store.saveDraft())
    try Checks.require(!(store.canUndoReview))
    store.undoReviewPlan()
    try Checks.require(try Checks.unwrap(try repository.tasks(dayKeys: [task.dayKey]).first).isCompleted)
  }
}

@MainActor
extension TaskStoreTests {
  static var checks: [(String, () throws -> Void)] {
    let suite = TaskStoreTests()
    return [
      ("TaskStoreTests.testFailedSaveRetainsDraftAndSelectionThenCanRetry", { try suite.testFailedSaveRetainsDraftAndSelectionThenCanRetry() }),
      ("TaskStoreTests.testClosingAnEditedDraftDiscardsChanges", { try suite.testClosingAnEditedDraftDiscardsChanges() }),
      ("TaskStoreTests.testSavingNewDraftOnceDoesNotCreateDuplicates", { try suite.testSavingNewDraftOnceDoesNotCreateDuplicates() }),
      ("TaskStoreTests.testBlankDraftSaveCanBeCorrectedWithoutLosingNotes", { try suite.testBlankDraftSaveCanBeCorrectedWithoutLosingNotes() }),
      ("TaskStoreTests.testFailedUndoCanBeRetriedWithoutPartialRestoration", { try suite.testFailedUndoCanBeRetriedWithoutPartialRestoration() }),
      ("TaskStoreTests.testEditingAfterReviewInvalidatesUndo", { try suite.testEditingAfterReviewInvalidatesUndo() }),
    ]
  }
}
