import Foundation

struct TodoItem: Codable, Identifiable, Sendable {
  var id: UUID
  var title: String
  var notes: String
  /// A calendar day (`yyyy-MM-dd`), deliberately independent of time zones.
  var dayKey: String
  var isCompleted: Bool
  var sortOrder: Double
  var createdAt: Date
  var updatedAt: Date
  var deletedAt: Date?
  /// Reserved for a future remote sync engine.
  var syncState: String

  enum CodingKeys: String, CodingKey {
    case id, title, notes, dayKey, isCompleted, sortOrder
    case createdAt, updatedAt, deletedAt, syncState
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decode(String.self, forKey: .title)
    notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
    dayKey = try values.decode(String.self, forKey: .dayKey)
    isCompleted = try values.decode(Bool.self, forKey: .isCompleted)
    sortOrder = try values.decode(Double.self, forKey: .sortOrder)
    createdAt = try values.decode(Date.self, forKey: .createdAt)
    updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    deletedAt = try values.decodeIfPresent(Date.self, forKey: .deletedAt)
    syncState = try values.decodeIfPresent(String.self, forKey: .syncState) ?? "pending"
  }

  init(
    title: String, notes: String = "", dayKey: String, sortOrder: Double = 0,
    isCompleted: Bool = false
  ) {
    self.id = UUID()
    self.title = title
    self.notes = notes
    self.dayKey = dayKey
    self.isCompleted = isCompleted
    self.sortOrder = sortOrder
    self.createdAt = .now
    self.updatedAt = .now
    self.deletedAt = nil
    self.syncState = "pending"
  }
}
