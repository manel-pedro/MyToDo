import Foundation

@MainActor
final class PersistenceTests {
  func testMissingFileLoadsEmptyWithoutCreatingIt() throws {
    try withTaskFile { (file: URL) throws -> Void in
      try Checks.require(try JSONFileTaskStorage(fileURL: file).load().isEmpty)
      try Checks.require(!(FileManager.default.fileExists(atPath: file.path)))
    }
  }

  func testCorruptFileIsNotOverwritten() throws {
    try withTaskFile { (file: URL) throws -> Void in
      let original = Data("not valid JSON".utf8)
      try original.write(to: file)
      try Checks.expectError((any Error).self) { try LocalTaskRepository(fileURL: file) }
      try Checks.require(try Data(contentsOf: file) == original)
    }
  }

  func testUnsupportedVersionIsRejectedWithoutRewriting() throws {
    try withTaskFile { (file: URL) throws -> Void in
      let original = Data(#"{"version":999,"tasks":[]}"#.utf8)
      try original.write(to: file)
      try Checks.expectError(StorageError.self) { try LocalTaskRepository(fileURL: file) }
      try Checks.require(try Data(contentsOf: file) == original)
    }
  }

  func testLegacyEnvelopeMigratesAndDefaultsOptionalFields() throws {
    try withTaskFile { (file: URL) throws -> Void in
      let task = TodoItem(title: "Legacy", dayKey: "2026-09-23")
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      var object = try Checks.unwrap(try JSONSerialization.jsonObject(with: encoder.encode(task)) as? [String: Any])
      object.removeValue(forKey: "notes")
      object.removeValue(forKey: "syncState")
      let envelope: [String: Any] = ["version": 1, "tasks": [object]]
      try JSONSerialization.data(withJSONObject: envelope).write(to: file)
      let tasks = try JSONFileTaskStorage(fileURL: file).load()
      try Checks.require(tasks.map(\.id) == [task.id])
      try Checks.require(tasks.first?.notes == "")
      try Checks.require(tasks.first?.syncState == "pending")
      try Checks.require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]] != nil)
      try Checks.require(try JSONFileTaskStorage(fileURL: file).load().map(\.id) == [task.id])
    }
  }

  func testRoundTripPreservesUnicodeNotesAndDeletionMetadata() throws {
    try withTaskFile { (file: URL) throws -> Void in
      var task = TodoItem(title: "Læs 📚", notes: "# Notes\n**bold**\n日本語\n", dayKey: "2026-09-23", isCompleted: true)
      task.createdAt = Date(timeIntervalSince1970: 1_700_000_000.123)
      task.updatedAt = task.createdAt.addingTimeInterval(0.456)
      task.deletedAt = task.updatedAt.addingTimeInterval(0.789)
      task.syncState = "synced"
      let storage = try JSONFileTaskStorage(fileURL: file)
      try storage.save([task])
      let restored = try Checks.unwrap(try JSONFileTaskStorage(fileURL: file).load().first)
      try Checks.require(restored.id == task.id)
      try Checks.require(restored.title == task.title)
      try Checks.require(restored.notes == task.notes)
      try Checks.require(restored.dayKey == task.dayKey)
      try Checks.require(restored.isCompleted == task.isCompleted)
      try Checks.require(restored.syncState == task.syncState)
      try Checks.require(abs((restored.createdAt.timeIntervalSince1970) - (task.createdAt.timeIntervalSince1970)) <= 0.001)
      try Checks.require(abs((restored.updatedAt.timeIntervalSince1970) - (task.updatedAt.timeIntervalSince1970)) <= 0.001)
      try Checks.require(abs((try Checks.unwrap(restored.deletedAt).timeIntervalSince1970) - (task.deletedAt!.timeIntervalSince1970)) <= 0.001)
      try Checks.require(try LocalTaskRepository(fileURL: file).tasks(dayKeys: [task.dayKey]).isEmpty)
    }
  }
}

@MainActor
extension PersistenceTests {
  static var checks: [(String, () throws -> Void)] {
    let suite = PersistenceTests()
    return [
      ("PersistenceTests.testMissingFileLoadsEmptyWithoutCreatingIt", { try suite.testMissingFileLoadsEmptyWithoutCreatingIt() }),
      ("PersistenceTests.testCorruptFileIsNotOverwritten", { try suite.testCorruptFileIsNotOverwritten() }),
      ("PersistenceTests.testUnsupportedVersionIsRejectedWithoutRewriting", { try suite.testUnsupportedVersionIsRejectedWithoutRewriting() }),
      ("PersistenceTests.testLegacyEnvelopeMigratesAndDefaultsOptionalFields", { try suite.testLegacyEnvelopeMigratesAndDefaultsOptionalFields() }),
      ("PersistenceTests.testRoundTripPreservesUnicodeNotesAndDeletionMetadata", { try suite.testRoundTripPreservesUnicodeNotesAndDeletionMetadata() }),
    ]
  }
}
