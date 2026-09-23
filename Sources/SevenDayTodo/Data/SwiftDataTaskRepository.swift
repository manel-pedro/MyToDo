import Foundation
import SwiftData

@MainActor
final class SwiftDataTaskRepository: TaskRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func tasks(dayKeys: [String]) throws -> [TodoItem] {
        let wantedKeys = Set(dayKeys)
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\TodoItem.dayKey),
                SortDescriptor(\TodoItem.sortOrder),
                SortDescriptor(\TodoItem.createdAt)
            ]
        )
        return try context.fetch(descriptor).filter { wantedKeys.contains($0.dayKey) }
    }

    func add(title: String, dayKey: String) throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let existing = try tasks(dayKeys: [dayKey])
        let item = TodoItem(title: cleanTitle, dayKey: dayKey, sortOrder: Double(existing.count))
        context.insert(item)
        try context.save()
    }

    func toggle(_ item: TodoItem) throws {
        item.isCompleted.toggle()
        touch(item)
        try context.save()
    }

    func rename(_ item: TodoItem, title: String) throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        item.title = cleanTitle
        touch(item)
        try context.save()
    }

    func move(_ item: TodoItem, to dayKey: String) throws {
        item.dayKey = dayKey
        touch(item)
        try context.save()
    }

    func delete(_ item: TodoItem) throws {
        // A tombstone lets a future sync service propagate this deletion.
        item.deletedAt = .now
        touch(item)
        try context.save()
    }

    private func touch(_ item: TodoItem) {
        item.updatedAt = .now
        item.syncState = "pending"
    }
}
