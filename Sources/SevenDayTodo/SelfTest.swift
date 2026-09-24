import Foundation

@MainActor
enum SelfTest {
  enum Failure: Error { case assertion(String) }

  static func run() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("tasks.json")
    let firstDay = "2026-09-23"
    let secondDay = "2026-09-24"

    // A task-only array from the first version may have no notes field.
    let legacy = TodoItem(title: "Legacy", dayKey: firstDay)
    var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder.storage.encode([legacy]))
      as! [[String: Any]]
    legacyJSON[0].removeValue(forKey: "notes")
    try JSONSerialization.data(withJSONObject: legacyJSON).write(to: file)
    let repository = try LocalTaskRepository(fileURL: file)
    var tasks = try repository.tasks(dayKeys: [firstDay])
    try require(tasks.count == 1 && tasks[0].notes.isEmpty, "old task array should load")

    // The intermediate object format must return to a task-only array on load.
    let priorObject: [String: Any] = [
      "version": 1,
      "tasks": legacyJSON,
      "obsolete": [["body": "discarded prior entry"]],
    ]
    try JSONSerialization.data(withJSONObject: priorObject).write(to: file)
    let migrated = try LocalTaskRepository(fileURL: file)
    tasks = try migrated.tasks(dayKeys: [firstDay])
    try require(tasks.count == 1 && tasks[0].id == legacy.id, "object format should preserve tasks")
    let currentJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
    try require(currentJSON is [[String: Any]], "storage should now contain only a task array")

    let created = try migrated.create(
      title: "First", notes: "Long note\nSecond paragraph",
      dayKey: firstDay, isCompleted: false)
    try migrated.updateNotes(id: created.id, notes: "Updated note")
    try migrated.toggle(id: created.id)
    let reopened = try LocalTaskRepository(fileURL: file)
    tasks = try reopened.tasks(dayKeys: [firstDay])
    try require(tasks.first(where: { $0.id == created.id })?.notes == "Updated note", "notes should persist")
    try require(tasks.first(where: { $0.id == created.id })?.isCompleted == true,
                "completion should persist")

    let a = try reopened.create(title: "A", notes: "", dayKey: secondDay, isCompleted: false)
    let b = try reopened.create(title: "B", notes: "", dayKey: secondDay, isCompleted: false)
    try reopened.move(id: created.id, to: secondDay, at: 1)
    try require(try reopened.tasks(dayKeys: [secondDay]).map(\.id) == [a.id, created.id, b.id],
                "cross-day drop should insert at destination index")
    try reopened.move(id: b.id, to: secondDay, at: 0)
    try require(try reopened.tasks(dayKeys: [secondDay]).map(\.id) == [b.id, a.id, created.id],
                "same-day reorder should be exact")
    try require(try reopened.tasks(dayKeys: [secondDay]).map(\.sortOrder) == [0, 1, 2],
                "sort values should normalize after moves")
    try reopened.delete(id: created.id)
    try require(try reopened.tasks(dayKeys: [secondDay]).allSatisfy { $0.id != created.id },
                "soft-deleted task should be hidden")

    let today = date(2026, 9, 24)
    let store = TaskStore(repository: reopened)
    store.returnToToday(now: today)
    let original = store.days.map { DayKey.value(for: $0) }
    try require(original.count == 7 && original[0] == "2026-09-21" && original[6] == "2026-09-27",
                "default range should center on today")
    store.shiftDays(-1)
    try require(DayKey.value(for: store.days[0]) == "2026-09-20", "previous should shift one day")
    store.shiftDays(1)
    try require(store.days.map { DayKey.value(for: $0) } == original, "next should shift one day")
    store.shiftDays(5)
    store.returnToToday(now: today)
    try require(store.days.map { DayKey.value(for: $0) } == original,
                "today should restore default range")

    let distant = "2027-02-12"
    _ = try reopened.create(title: "Outside range", notes: "", dayKey: distant, isCompleted: false)
    try require(try reopened.tasks(dayKeys: [distant]).count == 1,
                "arbitrary date should remain stored")
    try require(DayKey.value(for: date(2026, 1, 2)) == "2026-01-02", "day key needs zero padding")
    try require(DayKey.date(for: "2026-02-31") == nil, "invalid day key should not parse")

    let failingStorage = FailingTaskPersistence()
    let isolated = try LocalTaskRepository(storage: failingStorage)
    let stable = try isolated.create(
      title: "Stable", notes: "Original", dayKey: firstDay, isCompleted: false)
    failingStorage.shouldFail = true
    do {
      try isolated.updateNotes(id: stable.id, notes: "Should not persist")
      throw Failure.assertion("failed storage write should throw")
    } catch is FailingTaskPersistence.WriteError {}
    try require(try isolated.tasks(dayKeys: [firstDay]).first?.notes == "Original",
                "failed save should leave repository state unchanged")
  }

  private static func require(_ condition: @autoclosure () throws -> Bool,
                              _ description: String) throws {
    guard try condition() else { throw Failure.assertion(description) }
  }

  private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
  }
}

@MainActor
private final class FailingTaskPersistence: TaskPersistence {
  enum WriteError: Error { case rejected }
  var shouldFail = false
  private var items: [TodoItem] = []

  func load() throws -> [TodoItem] { items }
  func save(_ tasks: [TodoItem]) throws {
    if shouldFail { throw WriteError.rejected }
    items = tasks
  }
}

private extension JSONEncoder {
  static var storage: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}
