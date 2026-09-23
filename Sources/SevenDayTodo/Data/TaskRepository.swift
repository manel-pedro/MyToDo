import Foundation

@MainActor
protocol TaskRepository {
    func tasks(dayKeys: [String]) throws -> [TodoItem]
    func add(title: String, dayKey: String) throws
    func toggle(_ item: TodoItem) throws
    func rename(_ item: TodoItem, title: String) throws
    func move(_ item: TodoItem, to dayKey: String) throws
    func delete(_ item: TodoItem) throws
}

