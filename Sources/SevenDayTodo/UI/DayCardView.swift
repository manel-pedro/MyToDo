import AppKit

@MainActor
final class DayCardView: NSView {
  var onAdd: ((NSView) -> Void)?
  var onDrop: ((UUID, Int) -> Bool)?

  private let date: Date
  private let compact: Bool
  private let items: [TodoItem]
  private let list: StackScrollView
  private let actions: TaskActions
  private var rows: NSStackView { list.stack }
  private var taskScroll: StackScrollView { list }
  private var isDropTarget = false
  private let insertionMarker = TaskInsertionMarker()
  private let dropHint = NSTextField(labelWithString: "")

  init(date: Date, items: [TodoItem], compact: Bool = false, actions: TaskActions) {
    self.list = StackScrollView(spacing: compact ? 2 : 7)
    self.actions = actions
    self.compact = compact
    self.date = date
    self.items = items
    super.init(frame: .zero)
    registerForDraggedTypes([TaskRowView.pasteboardType])
    buildView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func buildView() {
    wantsLayer = true
    layer?.cornerRadius = compact ? 8 : 14
    setDropHighlighted(false)

    let dayName = NSTextField(
      labelWithString: Calendar.current.isDateInToday(date)
        ? "TODAY" : date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
    dayName.font = .systemFont(ofSize: 11, weight: .bold)
    dayName.textColor =
      Calendar.current.isDateInToday(date) ? .controlAccentColor : .secondaryLabelColor
    let dayNumber = NSTextField(
      labelWithString: compact
        ? date.formatted(.dateTime.day()) : date.formatted(.dateTime.day().month(.abbreviated)))
    dayNumber.font = .systemFont(ofSize: compact ? 12 : 20, weight: .bold)
    if Calendar.current.isDateInToday(date) { dayNumber.textColor = .controlAccentColor }

    if items.isEmpty && !compact {
      let empty = NSTextField(labelWithString: "Nothing planned")
      empty.textColor = .tertiaryLabelColor
      empty.font = .systemFont(ofSize: 11)
      rows.addArrangedSubview(empty)
    } else {
      for item in items {
        let row = TaskRowView(item: item, compact: compact)
        actions.configure(row, for: item)
        rows.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
      }
    }

    let scroll = list

    let add = NSButton(title: compact ? "+" : "+ Add", target: self, action: #selector(addTask(_:)))
    add.toolTip = "Add task on \(date.formatted(date: .complete, time: .omitted))"
    let content: [NSView]
    if compact {
      add.isBordered = false
      content = [
        AppUI.stack([dayNumber, AppUI.spacer(), add], axis: .horizontal, alignment: .centerY),
        scroll,
      ]
    } else {
      content = [dayName, dayNumber, AppUI.separator(), scroll, add]
    }
    let stack = AppUI.stack(content, spacing: compact ? 2 : 10)
    AppUI.pin(stack, in: self, horizontal: compact ? 6 : 12, vertical: compact ? 4 : 14)
    scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    if compact { content[0].widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }

    insertionMarker.isHidden = true
    addSubview(insertionMarker)
    dropHint.font = .systemFont(ofSize: 11, weight: .medium)
    dropHint.textColor = .controlAccentColor
    dropHint.backgroundColor = .controlBackgroundColor
    dropHint.drawsBackground = true
    dropHint.alignment = .center
    dropHint.wantsLayer = true
    dropHint.layer?.cornerRadius = 6
    dropHint.layer?.masksToBounds = true
    dropHint.toolTip = "Move task to \(date.formatted(date: .complete, time: .omitted))"
    dropHint.translatesAutoresizingMaskIntoConstraints = false
    addSubview(dropHint)
    NSLayoutConstraint.activate([
      dropHint.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 6),
      dropHint.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
      dropHint.centerXAnchor.constraint(equalTo: centerXAnchor),
      dropHint.bottomAnchor.constraint(equalTo: bottomAnchor, constant: compact ? -5 : -50),
      dropHint.heightAnchor.constraint(equalToConstant: 22),
    ])
  }

  @objc private func addTask(_ sender: NSButton) { onAdd?(sender) }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    updateDropFeedback(sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    if let event = NSApp.currentEvent,
      taskScroll.bounds.contains(taskScroll.convert(sender.draggingLocation, from: nil))
    {
      _ = taskScroll.contentView.autoscroll(with: event)
    }
    return updateDropFeedback(sender)
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    setDropHighlighted(false)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func setDropHighlighted(_ highlighted: Bool) {
    isDropTarget = highlighted
    updateColors()
    insertionMarker.isHidden = !highlighted
    dropHint.isHidden = !highlighted
  }

  private func updateColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      let today = Calendar.current.isDateInToday(date)
      layer?.borderWidth = isDropTarget || today ? 2 : 1
      layer?.borderColor =
        (isDropTarget || today ? NSColor.controlAccentColor : .separatorColor).cgColor
      layer?.backgroundColor =
        (isDropTarget
        ? NSColor.controlAccentColor.withAlphaComponent(0.10) : .controlBackgroundColor).cgColor
      dropHint.backgroundColor = .controlBackgroundColor
    }
  }

  private func updateDropFeedback(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard sender.draggingSource is TaskRowView, let id = draggedID(sender) else {
      setDropHighlighted(false)
      return []
    }
    setDropHighlighted(true)
    dropHint.stringValue =
      compact
      ? "Drop here"
      : "Move to \(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    let point = convert(sender.draggingLocation, from: nil)
    let placement = dropPlacement(for: id, at: point)
    let visibleList = convert(taskScroll.contentView.bounds, from: taskScroll.contentView)
    let y = min(max(placement.y, visibleList.minY + 4), visibleList.maxY - 4)
    let inset: CGFloat = compact ? 6 : 12
    insertionMarker.frame = NSRect(
      x: inset, y: y - 3, width: max(0, bounds.width - 2 * inset), height: 6)
    insertionMarker.needsDisplay = true
    return .move
  }

  // Use the same placement for the visual marker and the persisted order.
  private func dropPlacement(for id: UUID, at point: NSPoint) -> (index: Int, y: CGFloat) {
    let targets = rows.arrangedSubviews.compactMap { $0 as? TaskRowView }.filter { $0.taskID != id }
    for (index, row) in targets.enumerated() {
      let frame = convert(row.bounds, from: row)
      if point.y > frame.midY { return (index, frame.maxY + rows.spacing / 2) }
    }
    if let last = targets.last {
      return (targets.count, convert(last.bounds, from: last).minY - rows.spacing / 2)
    }
    let visibleList = convert(taskScroll.contentView.bounds, from: taskScroll.contentView)
    return (0, visibleList.maxY - 12)
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    setDropHighlighted(false)
    guard sender.draggingSource is TaskRowView, let id = draggedID(sender) else { return false }
    let point = convert(sender.draggingLocation, from: nil)
    return onDrop?(id, dropPlacement(for: id, at: point).index) ?? false
  }

  private func draggedID(_ sender: any NSDraggingInfo) -> UUID? {
    guard let value = sender.draggingPasteboard.string(forType: TaskRowView.pasteboardType) else {
      return nil
    }
    return UUID(uuidString: value)
  }
}

@MainActor
private final class TaskInsertionMarker: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.controlAccentColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 6, height: 6)).fill()
    NSBezierPath(
      roundedRect: NSRect(x: 3, y: 1.5, width: max(0, bounds.width - 3), height: 3),
      xRadius: 1.5, yRadius: 1.5
    ).fill()
  }
}
