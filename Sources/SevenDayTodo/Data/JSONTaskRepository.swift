import Foundation

@MainActor
final class JSONTaskRepository: TaskRepository {
    private let fileURL: URL
    private var allItems: [TodoItem]

    init(fileURL: URL? = nil) throws {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support.appendingPathComponent("SevenDayTodo", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("tasks.json")
        }

        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            let data = try Data(contentsOf: self.fileURL)
            allItems = try JSONDecoder.storage.decode([TodoItem].self, from: data)
        } else {
            allItems = []
        }
    }

    func tasks(dayKeys: [String]) throws -> [TodoItem] {
        let wanted = Set(dayKeys)
        return allItems
            .filter { $0.deletedAt == nil && wanted.contains($0.dayKey) }
            .sorted {
                ($0.dayKey, $0.sortOrder, $0.createdAt) < ($1.dayKey, $1.sortOrder, $1.createdAt)
            }
    }

    func add(title: String, dayKey: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let order = Double(allItems.filter { $0.dayKey == dayKey && $0.deletedAt == nil }.count)
        allItems.append(TodoItem(title: title, dayKey: dayKey, sortOrder: order))
        try save()
    }

    func toggle(id: UUID) throws {
        try mutate(id: id) { $0.isCompleted.toggle() }
    }

    func rename(id: UUID, title: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        try mutate(id: id) { $0.title = title }
    }

    func move(id: UUID, to dayKey: String) throws {
        try mutate(id: id) { $0.dayKey = dayKey }
    }

    func delete(id: UUID) throws {
        try mutate(id: id) { $0.deletedAt = .now }
    }

    private func mutate(id: UUID, change: (inout TodoItem) -> Void) throws {
        guard let index = allItems.firstIndex(where: { $0.id == id }) else { return }
        change(&allItems[index])
        allItems[index].updatedAt = .now
        allItems[index].syncState = "pending"
        try save()
    }

    private func save() throws {
        let data = try JSONEncoder.storage.encode(allItems)
        try data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var storage: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var storage: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
