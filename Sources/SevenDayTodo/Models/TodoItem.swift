import Foundation

struct TodoItem: Codable, Identifiable, Sendable {
    var id: UUID
    var title: String
    /// A calendar day (`yyyy-MM-dd`), deliberately independent of time zones.
    var dayKey: String
    var isCompleted: Bool
    var sortOrder: Double
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    /// Reserved for a future remote sync engine.
    var syncState: String

    init(title: String, dayKey: String, sortOrder: Double = 0) {
        self.id = UUID()
        self.title = title
        self.dayKey = dayKey
        self.isCompleted = false
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncState = "pending"
    }
}
