import Foundation

enum TaskError: LocalizedError {
  case emptyTitle, missingTask, duplicatePlanItem, invalidReview
  case invalidDayKey(String)
  case duplicateTaskID, invalidSortOrder

  var errorDescription: String? {
    switch self {
    case .emptyTitle: "A task needs a title."
    case .missingTask: "This task no longer exists."
    case .duplicatePlanItem: "A task can only appear once in a plan."
    case .invalidReview: "The unfinished tasks have changed. Review the plan and try again."
    case .invalidDayKey(let key): "The task date '\(key)' is not a valid calendar day."
    case .duplicateTaskID: "The task file contains duplicate task identifiers."
    case .invalidSortOrder: "The task file contains an invalid task order."
    }
  }
}
