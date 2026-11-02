import Foundation

@MainActor
final class TestStorage: TaskPersistence {
  enum Failure: Error { case writeRejected }
  var items: [TodoItem] = []
  var rejectWrites = false
  var writes = 0

  func load() throws -> [TodoItem] { items }
  func save(_ tasks: [TodoItem]) throws {
    if rejectWrites { throw Failure.writeRejected }
    items = tasks
    writes += 1
  }
}

@MainActor
func createTask(_ repository: LocalTaskRepository, title: String = "Task", day: String = "2026-09-23") throws -> TodoItem {
  try repository.create(title: title, notes: "Original notes", dayKey: day, isCompleted: false)
}

func withTaskFile(_ body: (URL) throws -> Void) throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  try body(directory.appendingPathComponent("tasks.json"))
}

func taskSnapshot(_ items: [TodoItem]) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  return try encoder.encode(items)
}
