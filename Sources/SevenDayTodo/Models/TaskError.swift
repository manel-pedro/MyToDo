import Foundation

enum TaskError: LocalizedError {
  case emptyTitle, missingTask

  var errorDescription: String? {
    switch self {
    case .emptyTitle: "A task needs a title."
    case .missingTask: "This task no longer exists."
    }
  }
}
