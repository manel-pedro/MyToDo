import Foundation

struct TaskPlanUpdate: Equatable, Sendable {
  var id: UUID
  var dayKey: String
  var isCompleted: Bool
  var destinationIndex: Int? = nil
}
