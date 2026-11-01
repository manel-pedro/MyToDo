import AppKit

@MainActor
final class BoardViewController: NSViewController {
  private let store: TaskStore
  private let board = NSStackView()
  private let rangeLabel = NSTextField(labelWithString: "")
  private let viewMode = NSSegmentedControl(
    labels: ["Default", "Month"], trackingMode: .selectOne, target: nil, action: nil)
  private let previous = NSButton(title: "‹", target: nil, action: nil)
  private let next = NSButton(title: "›", target: nil, action: nil)
  private let unfinishedButton = NSButton(title: "Unfinished tasks", target: nil, action: nil)
  private(set) var unfinishedPopover: UnfinishedTasksPopover?
  private var showedStartupReview = false
  private var unfinishedDragSource: TaskRowView?
  private(set) var editor: TaskEditorPopover?
  private var popoverClickMonitors: [Any] = []
  private var needsRenderAfterEditing = false
  private var shownError: String?

  init(store: TaskStore) {
    self.store = store
    super.init(nibName: nil, bundle: nil)
    store.onChange = { [weak self] in self?.renderDays() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func loadView() {
    view = NSView()
    view.wantsLayer = true

    let title = NSTextField(labelWithString: "Seven Day Todo")
    title.font = .systemFont(ofSize: 28, weight: .bold)
    rangeLabel.textColor = .secondaryLabelColor
    rangeLabel.font = .systemFont(ofSize: 12)

    unfinishedButton.target = self
    unfinishedButton.action = #selector(toggleUnfinishedTasks)
    unfinishedButton.toolTip = "Review and reschedule unfinished tasks from earlier days"
    previous.target = self
    previous.action = #selector(previousDay)
    next.target = self
    next.action = #selector(nextDay)
    viewMode.target = self
    viewMode.action = #selector(changeViewMode)
    viewMode.selectedSegment = 0
    viewMode.setAccessibilityLabel("Calendar view")
    let today = NSButton(title: "Today", target: self, action: #selector(returnToToday))
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let header = NSStackView(views: [title, unfinishedButton, spacer, viewMode, rangeLabel, previous, today, next])
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 8

    board.orientation = .horizontal
    board.alignment = .top
    board.distribution = .fillEqually
    board.spacing = 12

    let root = NSStackView(views: [header, board])
    root.translatesAutoresizingMaskIntoConstraints = false
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = 20
    view.addSubview(root)
    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      root.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
      root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
      header.widthAnchor.constraint(equalTo: root.widthAnchor),
      board.widthAnchor.constraint(equalTo: root.widthAnchor),
    ])
    renderDays()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    guard !showedStartupReview else { return }
    showedStartupReview = true
    DispatchQueue.main.async { [weak self] in
      guard let self, self.view.window != nil else { return }
      self.store.reload()
      if !self.store.unfinishedItems.isEmpty { self.showUnfinishedTasks() }
    }
  }

  @objc private func toggleUnfinishedTasks() {
    if let unfinishedPopover, unfinishedPopover.isShown {
      closeUnfinishedTasks()
    } else {
      store.reload()
      showUnfinishedTasks()
    }
  }

  private func showUnfinishedTasks() {
    guard closeActiveEditor() else { return }
    let popover = UnfinishedTasksPopover(store: store)
    popover.behavior = .applicationDefined
    popover.onBeginTaskDrag = { [weak self, weak popover] row in
      guard let self else { return }
      // Keep the native drag source alive after its popover closes.
      self.unfinishedDragSource = row
      row.onDragEnded = { [weak self] in self?.unfinishedDragSource = nil }
      // Let AppKit finish starting the drag before revealing the day cards.
      DispatchQueue.main.async { [weak popover] in popover?.close() }
    }
    popover.onOpenTask = { [weak self, weak popover] item in
      guard let self, let date = DayKey.date(for: item.dayKey),
        let anchor = popover?.contentViewController?.view else { return }
      // Anchor to the stable content view, since saving rebuilds the task rows.
      self.openEditor(item: item, on: date, anchor: anchor, fromUnfinished: true)
    }
    popover.onClose = { [weak self, weak popover] in
      guard let self, self.unfinishedPopover === popover else { return }
      if self.editor?.behavior == .applicationDefined { self.editor?.performClose(nil) }
      self.unfinishedPopover = nil
      self.popoverClickMonitors.forEach { NSEvent.removeMonitor($0) }
      self.popoverClickMonitors.removeAll()
    }
    unfinishedPopover = popover
    popover.show(relativeTo: unfinishedButton.bounds, of: unfinishedButton, preferredEdge: .minY)
    monitorUnfinishedTaskClicks()
  }

  @discardableResult
  private func closeActiveEditor() -> Bool {
    guard let editor else { return true }
    editor.performClose(nil)
    return !editor.isShown
  }

  @discardableResult
  private func closeUnfinishedTasks() -> Bool {
    // Use the editor's normal close request so outside clicks still save changes.
    if let editor, editor.behavior == .applicationDefined {
      guard closeActiveEditor() else { return false }
    }
    unfinishedPopover?.performClose(nil)
    return unfinishedPopover == nil
  }

  private func monitorUnfinishedTaskClicks() {
    guard popoverClickMonitors.isEmpty else { return }
    let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    if let monitor = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
      guard let self else { return event }
      // Include child windows (for example, controls' auxiliary windows).
      var window = event.window
      while let candidate = window {
        if candidate === self.editor?.contentViewController?.view.window { return event }
        if candidate === self.unfinishedPopover?.contentViewController?.view.window {
          // Returning to the list saves and dismisses only its child editor.
          return self.closeActiveEditor() ? event : nil
        }
        window = candidate.parent
      }
      // Menus and utility panels belong to the controls being used in a popover.
      if event.window?.level == .popUpMenu
        || (event.window as? NSPanel)?.becomesKeyOnlyIfNeeded == true { return event }
      // Let the button's action close the group without reopening it on mouse-up.
      if event.window === self.unfinishedButton.window,
        self.unfinishedButton.bounds.contains(self.unfinishedButton.convert(event.locationInWindow, from: nil)) {
        return event
      }
      self.closeUnfinishedTasks()
      return event
    }) { popoverClickMonitors.append(monitor) }
    if let monitor = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
      Task { @MainActor [weak self] in self?.closeUnfinishedTasks() }
    }) { popoverClickMonitors.append(monitor) }
  }

  override func viewWillDisappear() {
    closeUnfinishedTasks()
    super.viewWillDisappear()
  }

  private func renderDays() {
    guard isViewLoaded else { return }
    if let error = store.errorMessage {
      if error != shownError {
        shownError = error
        let alert = NSAlert()
        alert.messageText = "Seven Day Todo couldn't save this change"
        alert.informativeText = error
        alert.runModal()
      }
      return
    }
    shownError = nil
    unfinishedButton.title = "Unfinished tasks (\(store.unfinishedItems.count))"
    unfinishedPopover?.refresh()
    // Saving from a close request must not remove the positioning view.
    guard editor == nil else {
      needsRenderAfterEditing = true
      return
    }
    needsRenderAfterEditing = false
    board.arrangedSubviews.forEach {
      board.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    let isMonth = store.viewMode == .month
    viewMode.selectedSegment = isMonth ? 1 : 0
    previous.toolTip = isMonth ? "Previous month" : "Previous day"
    next.toolTip = isMonth ? "Next month" : "Next day"
    board.orientation = isMonth ? .vertical : .horizontal
    board.distribution = isMonth ? .fill : .fillEqually
    board.alignment = isMonth ? .leading : .top
    board.spacing = isMonth ? 6 : 12
    if isMonth {
      rangeLabel.stringValue = store.focusedDate.formatted(.dateTime.month(.wide).year())
      let headings = NSStackView()
      headings.distribution = .fillEqually
      headings.spacing = 6
      for date in store.days.prefix(7) {
        let label = NSTextField(labelWithString: date.formatted(.dateTime.weekday(.abbreviated)))
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        headings.addArrangedSubview(label)
      }
      board.addArrangedSubview(headings)
      headings.widthAnchor.constraint(equalTo: board.widthAnchor).isActive = true
      headings.heightAnchor.constraint(equalToConstant: 18).isActive = true
      var firstWeek: NSStackView?
      for offset in stride(from: 0, to: store.days.count, by: 7) {
        let week = NSStackView()
        week.distribution = .fillEqually
        week.alignment = .top
        week.spacing = 6
        board.addArrangedSubview(week)
        week.widthAnchor.constraint(equalTo: board.widthAnchor).isActive = true
        week.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        if let firstWeek {
          week.heightAnchor.constraint(equalTo: firstWeek.heightAnchor).isActive = true
        } else {
          firstWeek = week
        }
        for date in store.days[offset..<(offset + 7)] {
          let card = makeCard(for: date, compact: true)
          week.addArrangedSubview(card)
          card.heightAnchor.constraint(equalTo: week.heightAnchor).isActive = true
        }
      }
    } else {
      if let first = store.days.first, let last = store.days.last {
        rangeLabel.stringValue =
          "\(first.formatted(.dateTime.day().month(.abbreviated).year())) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
      }
      for date in store.days {
        let card = makeCard(for: date, compact: false)
        board.addArrangedSubview(card)
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 470).isActive = true
      }
    }
  }

  private func makeCard(for date: Date, compact: Bool) -> DayCardView {
    let card = DayCardView(date: date, items: store.items(for: date), compact: compact)
    if compact && !Calendar.current.isDate(date, equalTo: store.focusedDate, toGranularity: .month) {
      card.alphaValue = 0.5
    }
    card.onAdd = { [weak self] anchor in
      self?.openEditor(item: nil, on: date, anchor: anchor)
    }
    card.onOpen = { [weak self] item, anchor in
      self?.openEditor(item: item, on: date, anchor: anchor)
    }
    card.onToggle = { [weak self] item in self?.store.toggle(item) }
    card.onDelete = { [weak self] item in self?.store.delete(item) }
    card.onDrop = { [weak self] id, index in self?.store.move(itemID: id, to: date, at: index) }
    return card
  }

  @objc private func changeViewMode() {
    store.setViewMode(viewMode.selectedSegment == 1 ? .month : .days)
  }

  private func openEditor(item: TodoItem?, on date: Date, anchor: NSView, fromUnfinished: Bool = false) {
    if !fromUnfinished, !closeUnfinishedTasks() { return }
    guard closeActiveEditor() else { return }
    if let item {
      // Closing the previous editor may have just updated this same task.
      guard let current = (store.items + store.unfinishedItems).first(where: { $0.id == item.id }) else { return }
      store.beginEditing(current)
    } else { store.beginNewTask(on: date) }
    let popover = TaskEditorPopover(store: store)
    if fromUnfinished { popover.behavior = .applicationDefined }
    popover.onClose = { [weak self, weak popover] in
      guard let self, self.editor === popover else { return }
      self.editor = nil
      if self.needsRenderAfterEditing { self.renderDays() }
    }
    editor = popover
    popover.show(near: anchor)
  }

  @objc private func previousDay() { store.shiftDays(-1) }
  @objc private func nextDay() { store.shiftDays(1) }
  @objc private func returnToToday() { store.returnToToday() }
}

@MainActor
private final class DayCardView: NSView {
  var onAdd: ((NSView) -> Void)?
  var onOpen: ((TodoItem, NSView) -> Void)?
  var onToggle: ((TodoItem) -> Void)?
  var onDelete: ((TodoItem) -> Void)?
  var onDrop: ((UUID, Int) -> Void)?

  private let date: Date
  private let compact: Bool
  private let items: [TodoItem]
  private let rows = NSStackView()
  private let taskScroll = NSScrollView()
  private let insertionMarker = TaskInsertionMarker()
  private let dropHint = NSTextField(labelWithString: "")

  init(date: Date, items: [TodoItem], compact: Bool = false) {
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
      labelWithString: compact ? date.formatted(.dateTime.day()) : date.formatted(.dateTime.day().month(.abbreviated)))
    dayNumber.font = .systemFont(ofSize: compact ? 12 : 20, weight: .bold)
    if Calendar.current.isDateInToday(date) { dayNumber.textColor = .controlAccentColor }

    rows.orientation = .vertical
    rows.alignment = .leading
    rows.spacing = compact ? 2 : 7
    if items.isEmpty && !compact {
      let empty = NSTextField(labelWithString: "Nothing planned")
      empty.textColor = .tertiaryLabelColor
      empty.font = .systemFont(ofSize: 11)
      rows.addArrangedSubview(empty)
    } else {
      for item in items {
        let row = TaskRowView(item: item, compact: compact)
        row.onOpen = { [weak self, weak row] in
          guard let row else { return }
          self?.onOpen?(item, row)
        }
        row.onToggle = { [weak self] in self?.onToggle?(item) }
        row.onDelete = { [weak self] in self?.onDelete?(item) }
        rows.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
      }
    }

    let scroll = taskScroll
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    // Keep short lists at the top, where an empty day's drop marker appears.
    let document = TaskListDocumentView()
    document.translatesAutoresizingMaskIntoConstraints = false
    rows.translatesAutoresizingMaskIntoConstraints = false
    document.addSubview(rows)
    scroll.documentView = document
    NSLayoutConstraint.activate([
      document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
      rows.leadingAnchor.constraint(equalTo: document.leadingAnchor),
      rows.trailingAnchor.constraint(equalTo: document.trailingAnchor),
      rows.topAnchor.constraint(equalTo: document.topAnchor),
      rows.bottomAnchor.constraint(equalTo: document.bottomAnchor),
    ])

    let add = NSButton(title: compact ? "+" : "+ Add", target: self, action: #selector(addTask(_:)))
    add.toolTip = "Add task on \(date.formatted(date: .complete, time: .omitted))"
    let dateHeader = NSStackView()
    if compact {
      dateHeader.addArrangedSubview(dayNumber)
      dateHeader.addArrangedSubview(NSView())
      dateHeader.addArrangedSubview(add)
    }
    dateHeader.distribution = .fill
    dateHeader.alignment = .centerY
    if compact { add.isBordered = false }
    let stack = NSStackView(views: compact ? [dateHeader, scroll] : [dayName, dayNumber, separator(), scroll, add])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = compact ? 2 : 10
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: compact ? 6 : 12),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: compact ? -6 : -12),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: compact ? 4 : 14),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: compact ? -4 : -14),
      scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
    if compact { dateHeader.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }

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

  private func separator() -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    return box
  }
  @objc private func addTask(_ sender: NSButton) { onAdd?(sender) }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    updateDropFeedback(sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    if let event = NSApp.currentEvent,
      taskScroll.bounds.contains(taskScroll.convert(sender.draggingLocation, from: nil)) {
      _ = taskScroll.contentView.autoscroll(with: event)
    }
    return updateDropFeedback(sender)
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    setDropHighlighted(false)
  }

  private func setDropHighlighted(_ highlighted: Bool) {
    let today = Calendar.current.isDateInToday(date)
    layer?.borderWidth = highlighted || today ? 2 : 1
    layer?.borderColor = highlighted || today
      ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
    layer?.backgroundColor = highlighted
      ? NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
      : NSColor.controlBackgroundColor.cgColor
    insertionMarker.isHidden = !highlighted
    dropHint.isHidden = !highlighted
  }

  private func updateDropFeedback(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard let id = draggedID(sender) else {
      setDropHighlighted(false)
      return []
    }
    setDropHighlighted(true)
    dropHint.stringValue = compact ? "Drop here" : "Move to \(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    let point = convert(sender.draggingLocation, from: nil)
    let placement = dropPlacement(for: id, at: point)
    let visibleList = convert(taskScroll.contentView.bounds, from: taskScroll.contentView)
    let y = min(max(placement.y, visibleList.minY + 4), visibleList.maxY - 4)
    let inset: CGFloat = compact ? 6 : 12
    insertionMarker.frame = NSRect(x: inset, y: y - 3, width: max(0, bounds.width - 2 * inset), height: 6)
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
    guard let id = draggedID(sender) else { return false }
    let point = convert(sender.draggingLocation, from: nil)
    onDrop?(id, dropPlacement(for: id, at: point).index)
    return true
  }

  private func draggedID(_ sender: any NSDraggingInfo) -> UUID? {
    guard let value = sender.draggingPasteboard.string(forType: TaskRowView.pasteboardType) else {
      return nil
    }
    return UUID(uuidString: value)
  }
}

@MainActor
final class TaskRowView: NSView, NSDraggingSource {
  static let pasteboardType = NSPasteboard.PasteboardType("com.sevendaytodo.task-id")
  var onOpen: (() -> Void)?
  var onToggle: (() -> Void)?
  var onDelete: (() -> Void)?
  var onDragBegan: ((TaskRowView) -> Void)?
  var onDragEnded: (() -> Void)?
  var taskID: UUID { item.id }
  private let item: TodoItem
  private let grip = NSImageView()
  private let label = NSTextField(labelWithString: "")
  private var dragging = false
  private var mouseDownPoint: NSPoint?
  private var hoverTracking: NSTrackingArea?

  init(item: TodoItem, compact: Bool = false) {
    self.item = item
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 6
    grip.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Drag task")
    grip.contentTintColor = .tertiaryLabelColor
    grip.imageScaling = .scaleProportionallyDown
    grip.toolTip = "Drag to move to another day"
    grip.widthAnchor.constraint(equalToConstant: compact ? 10 : 13).isActive = true
    grip.heightAnchor.constraint(equalToConstant: 16).isActive = true
    let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle))
    checkbox.state = item.isCompleted ? .on : .off
    label.stringValue = item.title
    label.font = .systemFont(ofSize: 12)
    label.textColor = item.isCompleted ? .secondaryLabelColor : .labelColor
    label.lineBreakMode = .byTruncatingTail
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let delete = NSButton(
      image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")!,
      target: self, action: #selector(deleteTask))
    delete.isBordered = false
    delete.contentTintColor = .tertiaryLabelColor
    let stack = NSStackView(views: compact ? [grip, checkbox, label] : [delete, grip, checkbox, label])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.alignment = .centerY
    stack.spacing = 4
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
      heightAnchor.constraint(greaterThanOrEqualToConstant: compact ? 22 : 31),
    ])
    toolTip = item.title + "\nDrag the handle or title to move; click to edit."
      + (item.notes.isEmpty ? "" : "\n" + item.notes)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverTracking { removeTrackingArea(hoverTracking) }
    let tracking = NSTrackingArea(rect: .zero,
      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    addTrackingArea(tracking)
    hoverTracking = tracking
  }

  override func mouseEntered(with event: NSEvent) {
    layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.07).cgColor
    grip.contentTintColor = .secondaryLabelColor
  }

  override func mouseExited(with event: NSEvent) {
    layer?.backgroundColor = nil
    grip.contentTintColor = .tertiaryLabelColor
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    addCursorRect(convert(grip.bounds, from: grip), cursor: .openHand)
    addCursorRect(convert(label.bounds, from: label), cursor: .openHand)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    return hit is NSTextField || hit === grip ? self : hit
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    mouseDownPoint = convert(event.locationInWindow, from: nil)
    dragging = false
  }

  override func mouseUp(with event: NSEvent) {
    if !dragging { onOpen?() }
    mouseDownPoint = nil
    dragging = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard !dragging, let start = mouseDownPoint else { return }
    let point = convert(event.locationInWindow, from: nil)
    guard hypot(point.x - start.x, point.y - start.y) >= 5 else { return }
    dragging = true
    let writer = NSPasteboardItem()
    writer.setString(item.id.uuidString, forType: Self.pasteboardType)
    let image = dragPreview()
    let draggingItem = NSDraggingItem(pasteboardWriter: writer)
    draggingItem.setDraggingFrame(
      NSRect(x: point.x - 24, y: point.y - 42, width: image.size.width, height: image.size.height), contents: image)
    let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = true
  }

  private func dragPreview() -> NSImage {
    let size = NSSize(width: min(320, max(220, bounds.width)), height: 68)
    let image = NSImage(size: size)
    image.lockFocus()
    effectiveAppearance.performAsCurrentDrawingAppearance {
      let card = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6),
                              xRadius: 10, yRadius: 10)
      NSGraphicsContext.saveGraphicsState()
      let shadow = NSShadow()
      shadow.shadowColor = NSColor.shadowColor.withAlphaComponent(0.25)
      shadow.shadowBlurRadius = 6
      shadow.shadowOffset = NSSize(width: 0, height: -2)
      shadow.set()
      NSColor.controlBackgroundColor.setFill()
      card.fill()
      NSGraphicsContext.restoreGraphicsState()
      NSColor.separatorColor.setStroke()
      card.lineWidth = 1
      card.stroke()
      NSColor.controlAccentColor.setFill()
      NSBezierPath(roundedRect: NSRect(x: 14, y: 17, width: 3, height: 34), xRadius: 1.5, yRadius: 1.5).fill()
      let paragraph = NSMutableParagraphStyle()
      paragraph.lineBreakMode = .byTruncatingTail
      (item.title as NSString).draw(in: NSRect(x: 26, y: 34, width: size.width - 44, height: 19), withAttributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
      ])
      ("Move to another day" as NSString).draw(at: NSPoint(x: 26, y: 17), withAttributes: [
        .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
      ])
    }
    image.unlockFocus()
    return image
  }

  func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
    alphaValue = 0.35
    onDragBegan?(self)
  }

  func draggingSession(
    _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
  ) {
    alphaValue = 1
    mouseDownPoint = nil
    layer?.backgroundColor = nil
    // Keep mouse-up from opening the editor after a drag. Next mouse-down resets it.
    onDragEnded?()
  }

  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation { context == .withinApplication ? .move : [] }
  @objc private func toggle() { onToggle?() }
  @objc private func deleteTask() { onDelete?() }
}

@MainActor
private final class TaskInsertionMarker: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.controlAccentColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 6, height: 6)).fill()
    NSBezierPath(roundedRect: NSRect(x: 3, y: 1.5, width: max(0, bounds.width - 3), height: 3),
                 xRadius: 1.5, yRadius: 1.5).fill()
  }
}

@MainActor
private final class TaskListDocumentView: NSView {
  override var isFlipped: Bool { true }
}
