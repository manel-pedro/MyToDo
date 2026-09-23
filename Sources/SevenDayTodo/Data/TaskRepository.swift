import Foundation

@MainActor
protocol TaskRepository {
    func tasks(dayKeys: [String]) throws -> [TodoItem]
    func add(title: String, dayKey: String) throws
    func toggle(id: UUID) throws
    func rename(id: UUID, title: String) throws
    func move(id: UUID, to dayKey: String) throws
    func delete(id: UUID) throws
}
