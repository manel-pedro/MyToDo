import Foundation

@MainActor
final class LocalTaskRepository: TaskRepository {
  private let persistence: any TaskPersistence
  private var items: [TodoItem]

  init(storage: any TaskPersistence) throws {
    persistence = storage
    items = try storage.load()
  }

  convenience init(fileURL: URL? = nil) throws {
    try self.init(storage: JSONFileTaskStorage(fileURL: fileURL))
  }

  func tasks(dayKeys: [String]) throws -> [TodoItem] {
    let keys = Set(dayKeys)
    return items.filter { $0.deletedAt == nil && keys.contains($0.dayKey) }
      .sorted(by: Self.taskOrder)
  }

  func create(title: String, notes: String, dayKey: String, isCompleted: Bool) throws -> TodoItem {
    let title = try Self.validatedTitle(title)
    return try commit { items in
      let nextOrder = (Self.activeTasks(in: items, on: dayKey).map(\.sortOrder).max() ?? -1) + 1
      let item = TodoItem(
        title: title, notes: notes, dayKey: dayKey,
        sortOrder: nextOrder, isCompleted: isCompleted)
      items.append(item)
      return item
    }
  }

  func update(id: UUID, title: String, notes: String, dayKey: String, isCompleted: Bool) throws {
    let title = try Self.validatedTitle(title)
    try commit { items in
      let index = try Self.activeTaskIndex(id, in: items)
      if items[index].dayKey != dayKey {
        Self.reorder(id: id, to: dayKey, at: Self.activeTasks(in: items, on: dayKey).count,
                     in: &items)
      }
      let current = try Self.activeTaskIndex(id, in: items)
      items[current].title = title
      items[current].notes = notes
      items[current].isCompleted = isCompleted
      Self.markPending(&items[current])
    }
  }

  func updateNotes(id: UUID, notes: String) throws {
    try mutateTask(id: id) { $0.notes = notes }
  }

  func toggle(id: UUID) throws {
    try mutateTask(id: id) { $0.isCompleted.toggle() }
  }

  func delete(id: UUID) throws {
    try mutateTask(id: id) { $0.deletedAt = .now }
  }

  func move(id: UUID, to dayKey: String) throws {
    try move(id: id, to: dayKey, at: Self.activeTasks(in: items, on: dayKey).count)
  }

  func move(id: UUID, to dayKey: String, at destinationIndex: Int) throws {
    try commit { items in
      _ = try Self.activeTaskIndex(id, in: items)
      Self.reorder(id: id, to: dayKey, at: destinationIndex, in: &items)
    }
  }

  private func mutateTask(id: UUID, change: (inout TodoItem) -> Void) throws {
    try commit { items in
      let index = try Self.activeTaskIndex(id, in: items)
      change(&items[index])
      Self.markPending(&items[index])
    }
  }

  @discardableResult
  private func commit<T>(_ change: (inout [TodoItem]) throws -> T) throws -> T {
    var candidate = items
    let result = try change(&candidate)
    try persistence.save(candidate)
    items = candidate
    return result
  }

  private static func validatedTitle(_ title: String) throws -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw TaskError.emptyTitle }
    return trimmed
  }

  private static func activeTaskIndex(_ id: UUID, in items: [TodoItem]) throws -> Int {
    guard let index = items.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
      throw TaskError.missingTask
    }
    return index
  }

  private static func activeTasks(in items: [TodoItem], on dayKey: String) -> [TodoItem] {
    items.filter { $0.dayKey == dayKey && $0.deletedAt == nil }.sorted(by: taskOrder)
  }

  private static func taskOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
    (lhs.dayKey, lhs.sortOrder, lhs.createdAt, lhs.id.uuidString) <
      (rhs.dayKey, rhs.sortOrder, rhs.createdAt, rhs.id.uuidString)
  }

  private static func reorder(id: UUID, to dayKey: String, at index: Int, in items: inout [TodoItem]) {
    guard let task = items.first(where: { $0.id == id }) else { return }
    let sourceDay = task.dayKey
    let sourceIDs = activeTasks(in: items, on: sourceDay).map(\.id).filter { $0 != id }
    var destinationIDs = sourceDay == dayKey
      ? sourceIDs : activeTasks(in: items, on: dayKey).map(\.id)
    destinationIDs.insert(id, at: min(max(index, 0), destinationIDs.count))
    if sourceDay != dayKey { applyOrder(sourceIDs, on: sourceDay, in: &items) }
    applyOrder(destinationIDs, on: dayKey, in: &items)
  }

  private static func applyOrder(_ ids: [UUID], on dayKey: String, in items: inout [TodoItem]) {
    for (order, id) in ids.enumerated() {
      guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
      guard items[index].dayKey != dayKey || items[index].sortOrder != Double(order) else {
        continue
      }
      items[index].dayKey = dayKey
      items[index].sortOrder = Double(order)
      markPending(&items[index])
    }
  }

  private static func markPending(_ task: inout TodoItem) {
    task.updatedAt = max(.now, task.updatedAt.addingTimeInterval(0.001))
    task.syncState = "pending"
  }
}
