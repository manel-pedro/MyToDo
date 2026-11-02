import AppKit

/// One binding for task actions, shared by calendar cards and unfinished-task rows.
@MainActor
struct TaskActions {
  var open: ((TodoItem, NSView) -> Void)?
  var toggle: ((TodoItem) -> Void)?
  var delete: ((TodoItem) -> Void)?
  var beginDrag: ((TaskRowView) -> Void)?

  func configure(_ row: TaskRowView, for item: TodoItem) {
    row.onOpen = { [weak row] in
      guard let row else { return }
      open?(item, row)
    }
    row.onToggle = { toggle?(item) }
    row.onDelete = { delete?(item) }
    row.onDragBegan = beginDrag
  }
}
