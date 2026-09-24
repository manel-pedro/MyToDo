import Foundation

@MainActor
protocol TaskPersistence {
  func load() throws -> [TodoItem]
  func save(_ tasks: [TodoItem]) throws
}

enum StorageError: LocalizedError {
  case unsupportedVersion(Int)

  var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let version): "Storage version \(version) is not supported."
    }
  }
}

@MainActor
final class JSONFileTaskStorage: TaskPersistence {
  private struct PreviousEnvelope: Decodable {
    let version: Int
    let tasks: [TodoItem]
  }

  private let fileURL: URL

  init(fileURL: URL? = nil) throws {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      let support = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask,
        appropriateFor: nil, create: true
      )
      let directory = support.appendingPathComponent("SevenDayTodo", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      self.fileURL = directory.appendingPathComponent("tasks.json")
    }
  }

  func load() throws -> [TodoItem] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    if let tasks = try? Self.decoder.decode([TodoItem].self, from: data) {
      return tasks
    }
    // The previous release stored tasks in an object. Read only the task collection.
    let previous = try Self.decoder.decode(PreviousEnvelope.self, from: data)
    guard previous.version == 1 else { throw StorageError.unsupportedVersion(previous.version) }
    try save(previous.tasks)
    return previous.tasks
  }

  func save(_ tasks: [TodoItem]) throws {
    let data = try Self.encoder.encode(tasks)
    try data.write(to: fileURL, options: .atomic)
  }

  private static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, value in
      var container = value.singleValueContainer()
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      try container.encode(formatter.string(from: date))
    }
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  private static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { value in
      let container = try value.singleValueContainer()
      let string = try container.decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: string) { return date }
      formatter.formatOptions = [.withInternetDateTime]
      if let date = formatter.date(from: string) { return date }
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid ISO-8601 date")
    }
    return decoder
  }
}
