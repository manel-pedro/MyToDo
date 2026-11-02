import Foundation

@MainActor
protocol TaskRepository {
  func tasks(dayKeys: [String]) throws -> [TodoItem]
  func unfinishedTasks(before dayKey: String) throws -> [TodoItem]
  func applyPlan(_ updates: [TaskPlanUpdate]) throws
  func create(title: String, notes: String, dayKey: String, isCompleted: Bool) throws -> TodoItem
  func update(id: UUID, title: String, notes: String, dayKey: String, isCompleted: Bool) throws
  func updateNotes(id: UUID, notes: String) throws
  func toggle(id: UUID) throws
  func move(id: UUID, to dayKey: String, at destinationIndex: Int) throws
  func delete(id: UUID) throws
}

extension TaskRepository {
  func move(id: UUID, to dayKey: String) throws {
    try move(id: id, to: dayKey, at: Int.max)
  }
}
