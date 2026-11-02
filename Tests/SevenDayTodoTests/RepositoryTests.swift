import Foundation

@MainActor
final class RepositoryTests {
  func testBlankTitlesDoNotWriteOrChangeExistingTasks() throws {
    let storage = TestStorage()
    let repository = try LocalTaskRepository(storage: storage)
    let task = try createTask(repository)
    for title in ["", " ", "\n\t"] {
      try Checks.expectError(TaskError.self) { try createTask(repository, title: title) }
      try Checks.expectError(TaskError.self) { try repository.update(id: task.id, title: title, notes: "Changed", dayKey: task.dayKey, isCompleted: true) }
    }
    try Checks.require(storage.writes == 1)
    try Checks.require(try repository.tasks(dayKeys: [task.dayKey]).map(\.title) == [task.title])
  }

  func testFailedMutationsPreserveMemoryAndPersistedSnapshot() throws {
    let operations: [(String, (LocalTaskRepository, TodoItem) throws -> Void)] = [
      ("create", { r, _ in _ = try createTask(r, title: "New") }),
      ("update", { r, t in try r.update(id: t.id, title: "Changed", notes: "Changed", dayKey: "2026-09-24", isCompleted: true) }),
      ("notes", { r, t in try r.updateNotes(id: t.id, notes: "Changed") }),
      ("toggle", { r, t in try r.toggle(id: t.id) }),
      ("delete", { r, t in try r.delete(id: t.id) }),
      ("move", { r, t in try r.move(id: t.id, to: "2026-09-24", at: 0) }),
    ]
    for (name, operation) in operations {
      let storage = TestStorage()
      let repository = try LocalTaskRepository(storage: storage)
      let task = try createTask(repository)
      let before = try taskSnapshot(storage.items)
      storage.rejectWrites = true
      try Checks.expectError(TestStorage.Failure.self, "\(name)") { try operation(repository, task) }
      try Checks.require(try taskSnapshot(storage.items) == before, "\(name)")
      try Checks.require(try taskSnapshot(repository.tasks(dayKeys: [task.dayKey, "2026-09-24"])) == before, "\(name)")
    }
  }

  func testDeletedTasksCannotBeMutatedOrResurrected() throws {
    let storage = TestStorage()
    let repository = try LocalTaskRepository(storage: storage)
    let task = try createTask(repository)
    try repository.delete(id: task.id)
    let writes = storage.writes
    try Checks.expectError(TaskError.self) { try repository.update(id: task.id, title: "Changed", notes: "", dayKey: task.dayKey, isCompleted: false) }
    try Checks.expectError(TaskError.self) { try repository.toggle(id: task.id) }
    try Checks.expectError(TaskError.self) { try repository.updateNotes(id: task.id, notes: "Changed") }
    try Checks.expectError(TaskError.self) { try repository.move(id: task.id, to: "2026-09-24") }
    try Checks.expectError(TaskError.self) { try repository.delete(id: task.id) }
    try Checks.require(storage.writes == writes)
    try Checks.require(try repository.tasks(dayKeys: [task.dayKey]).isEmpty)
    try Checks.require(try repository.unfinishedTasks(before: "2026-09-24").isEmpty)
    try Checks.require(storage.items.first?.deletedAt != nil)
  }

  func testMovesClampInsertionAndNormalizeBothDays() throws {
    let repository = try LocalTaskRepository(storage: TestStorage())
    let a = try createTask(repository, title: "A")
    let b = try createTask(repository, title: "B")
    let c = try createTask(repository, title: "C", day: "2026-09-24")
    try repository.move(id: b.id, to: c.dayKey, at: -99)
    try Checks.require(try repository.tasks(dayKeys: [c.dayKey]).map(\.id) == [b.id, c.id])
    try Checks.require(try repository.tasks(dayKeys: [a.dayKey]).map(\.sortOrder) == [0])
    try repository.move(id: b.id, to: c.dayKey, at: 999)
    try Checks.require(try repository.tasks(dayKeys: [c.dayKey]).map(\.id) == [c.id, b.id])
    try Checks.require(try repository.tasks(dayKeys: [c.dayKey]).map(\.sortOrder) == [0, 1])
  }

  func testInvalidPlanDoesNotPartiallyCommitOrWrite() throws {
    let storage = TestStorage()
    let repository = try LocalTaskRepository(storage: storage)
    let task = try createTask(repository)
    try Checks.expectError(TaskError.self) { try repository.applyPlan([
      TaskPlanUpdate(id: task.id, dayKey: "2026-09-24", isCompleted: true),
      TaskPlanUpdate(id: UUID(), dayKey: "2026-09-24", isCompleted: false),
    ]) }
    try Checks.require(storage.writes == 1)
    try Checks.require(try repository.tasks(dayKeys: [task.dayKey]).map(\.id) == [task.id])
    try Checks.require(try repository.tasks(dayKeys: ["2026-09-24"]).isEmpty)
  }

  func testEmptyPlanDoesNotWrite() throws {
    let storage = TestStorage()
    let repository = try LocalTaskRepository(storage: storage)
    try repository.applyPlan([])
    try Checks.require(storage.writes == 0)
  }

  func testEditsPreserveIdentityCreationDateAndAdvanceSyncTimestamp() throws {
    let storage = TestStorage()
    var task = TodoItem(title: "Task", notes: "Original notes", dayKey: "2026-09-23")
    task.syncState = "synced"
    storage.items = [task]
    let repository = try LocalTaskRepository(storage: storage)
    try repository.update(id: task.id, title: "  Edited \n", notes: "New notes", dayKey: "2026-09-24", isCompleted: true)
    let edited = try Checks.unwrap(try repository.tasks(dayKeys: ["2026-09-24"]).first)
    try Checks.require(edited.id == task.id)
    try Checks.require(edited.createdAt == task.createdAt)
    try Checks.require(edited.updatedAt > task.updatedAt)
    try Checks.require(edited.title == "Edited")
    try Checks.require(edited.notes == "New notes")
    try Checks.require(edited.isCompleted)
    try Checks.require(edited.syncState == "pending")
    try Checks.require(storage.items.count == 1)
  }
}

@MainActor
extension RepositoryTests {
  static var checks: [(String, () throws -> Void)] {
    let suite = RepositoryTests()
    return [
      ("RepositoryTests.testBlankTitlesDoNotWriteOrChangeExistingTasks", { try suite.testBlankTitlesDoNotWriteOrChangeExistingTasks() }),
      ("RepositoryTests.testFailedMutationsPreserveMemoryAndPersistedSnapshot", { try suite.testFailedMutationsPreserveMemoryAndPersistedSnapshot() }),
      ("RepositoryTests.testDeletedTasksCannotBeMutatedOrResurrected", { try suite.testDeletedTasksCannotBeMutatedOrResurrected() }),
      ("RepositoryTests.testMovesClampInsertionAndNormalizeBothDays", { try suite.testMovesClampInsertionAndNormalizeBothDays() }),
      ("RepositoryTests.testInvalidPlanDoesNotPartiallyCommitOrWrite", { try suite.testInvalidPlanDoesNotPartiallyCommitOrWrite() }),
      ("RepositoryTests.testEmptyPlanDoesNotWrite", { try suite.testEmptyPlanDoesNotWrite() }),
      ("RepositoryTests.testEditsPreserveIdentityCreationDateAndAdvanceSyncTimestamp", { try suite.testEditsPreserveIdentityCreationDateAndAdvanceSyncTimestamp() }),
    ]
  }
}
