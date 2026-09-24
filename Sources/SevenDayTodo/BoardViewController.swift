import AppKit

@MainActor
final class BoardViewController: NSViewController {
  private let store: TaskStore
  private let board = NSStackView()
  private let rangeLabel = NSTextField(labelWithString: "")
  private var editor: TaskEditorPanel?
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

    let previous = NSButton(title: "‹", target: self, action: #selector(previousDay))
    previous.toolTip = "Previous day"
    let next = NSButton(title: "›", target: self, action: #selector(nextDay))
    next.toolTip = "Next day"
    let today = NSButton(title: "Today", target: self, action: #selector(returnToToday))
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let header = NSStackView(views: [title, spacer, rangeLabel, previous, today, next])
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

  private func renderDays() {
    guard isViewLoaded else { return }
    if let error = store.errorMessage, error != shownError {
      shownError = error
      let alert = NSAlert()
      alert.messageText = "Seven Day Todo couldn't save this change"
      alert.informativeText = error
      alert.runModal()
    } else if store.errorMessage == nil {
      shownError = nil
    }
    board.arrangedSubviews.forEach {
      board.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    if let first = store.days.first, let last = store.days.last {
      rangeLabel.stringValue =
        "\(first.formatted(.dateTime.day().month(.abbreviated).year())) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
    for date in store.days {
      let card = DayCardView(date: date, items: store.items(for: date))
      card.onAdd = { [weak self, weak card] in self?.openEditor(item: nil, on: date, anchor: card) }
      card.onOpen = { [weak self, weak card] item in
        self?.openEditor(item: item, on: date, anchor: card)
      }
      card.onToggle = { [weak self] item in self?.store.toggle(item) }
      card.onDelete = { [weak self] item in self?.store.delete(item) }
      card.onDrop = { [weak self] id, index in self?.store.move(itemID: id, to: date, at: index) }
      board.addArrangedSubview(card)
      card.heightAnchor.constraint(greaterThanOrEqualToConstant: 470).isActive = true
    }
  }

  private func openEditor(item: TodoItem?, on date: Date, anchor: NSView?) {
    let anchorRect = anchor.flatMap { anchorView -> NSRect? in
      guard let window = anchorView.window else { return nil }
      return window.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
    }
    editor?.close()
    if let item { store.beginEditing(item) } else { store.beginNewTask(on: date) }
    let panel = TaskEditorPanel(store: store) { [weak self] in self?.editor = nil }
    editor = panel
    panel.show(near: anchorRect, parent: view.window)
  }

  @objc private func previousDay() { store.shiftDays(-1) }
  @objc private func nextDay() { store.shiftDays(1) }
  @objc private func returnToToday() { store.returnToToday() }
}

@MainActor
private final class DayCardView: NSView {
  var onAdd: (() -> Void)?
  var onOpen: ((TodoItem) -> Void)?
  var onToggle: ((TodoItem) -> Void)?
  var onDelete: ((TodoItem) -> Void)?
  var onDrop: ((UUID, Int) -> Void)?

  private let date: Date
  private let items: [TodoItem]
  private let rows = NSStackView()

  init(date: Date, items: [TodoItem]) {
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
    layer?.cornerRadius = 14
    layer?.borderWidth = Calendar.current.isDateInToday(date) ? 2 : 1
    layer?.borderColor =
      Calendar.current.isDateInToday(date)
      ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
    layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

    let dayName = NSTextField(
      labelWithString: Calendar.current.isDateInToday(date)
        ? "TODAY" : date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
    dayName.font = .systemFont(ofSize: 11, weight: .bold)
    dayName.textColor =
      Calendar.current.isDateInToday(date) ? .controlAccentColor : .secondaryLabelColor
    let dayNumber = NSTextField(
      labelWithString: date.formatted(.dateTime.day().month(.abbreviated)))
    dayNumber.font = .systemFont(ofSize: 20, weight: .bold)

    rows.orientation = .vertical
    rows.alignment = .leading
    rows.spacing = 7
    if items.isEmpty {
      let empty = NSTextField(labelWithString: "Nothing planned")
      empty.textColor = .tertiaryLabelColor
      empty.font = .systemFont(ofSize: 11)
      rows.addArrangedSubview(empty)
    } else {
      for item in items {
        let row = TaskRowView(item: item)
        row.onOpen = { [weak self] in self?.onOpen?(item) }
        row.onToggle = { [weak self] in self?.onToggle?(item) }
        row.onDelete = { [weak self] in self?.onDelete?(item) }
        rows.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
      }
    }

    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.documentView = rows
    rows.translatesAutoresizingMaskIntoConstraints = false
    rows.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

    let add = NSButton(title: "+ Add", target: self, action: #selector(addTask))
    let stack = NSStackView(views: [dayName, dayNumber, separator(), scroll, add])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
      scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
  }

  private func separator() -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    return box
  }
  @objc private func addTask() { onAdd?() }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    dragOperation(sender)
  }
  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    dragOperation(sender)
  }
  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    layer?.borderColor = NSColor.separatorColor.cgColor
  }

  private func dragOperation(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard draggedID(sender) != nil else { return [] }
    layer?.borderColor = NSColor.controlAccentColor.cgColor
    return .move
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    layer?.borderColor = NSColor.separatorColor.cgColor
    guard let id = draggedID(sender) else { return false }
    let point = convert(sender.draggingLocation, from: nil)
    var index = items.count
    for (offset, row) in rows.arrangedSubviews.enumerated() where row is TaskRowView {
      let frame = convert(row.bounds, from: row)
      if point.y > frame.midY {
        index = offset
        break
      }
    }
    if let sourceIndex = items.firstIndex(where: { $0.id == id }), sourceIndex < index {
      index -= 1
    }
    onDrop?(id, index)
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
private final class TaskRowView: NSView, NSDraggingSource {
  static let pasteboardType = NSPasteboard.PasteboardType("com.sevendaytodo.task-id")
  var onOpen: (() -> Void)?
  var onToggle: (() -> Void)?
  var onDelete: (() -> Void)?
  private let item: TodoItem
  private var dragging = false

  init(item: TodoItem) {
    self.item = item
    super.init(frame: .zero)
    let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle))
    checkbox.state = item.isCompleted ? .on : .off
    let label = NSTextField(labelWithString: item.title)
    label.font = .systemFont(ofSize: 12)
    label.lineBreakMode = .byTruncatingTail
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let delete = NSButton(
      image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")!,
      target: self, action: #selector(deleteTask))
    delete.isBordered = false
    delete.contentTintColor = .tertiaryLabelColor
    let stack = NSStackView(views: [checkbox, label, delete])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.spacing = 4
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      heightAnchor.constraint(greaterThanOrEqualToConstant: 27),
    ])
    toolTip = item.notes.isEmpty ? "Drag to move; click to edit" : item.notes
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    return hit is NSTextField ? self : hit
  }

  override func mouseUp(with event: NSEvent) {
    if !dragging { onOpen?() }
    dragging = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard !dragging else { return }
    dragging = true
    let writer = NSPasteboardItem()
    writer.setString(item.id.uuidString, forType: Self.pasteboardType)
    let image = NSImage(size: NSSize(width: max(bounds.width, 120), height: 28))
    image.lockFocus()
    NSColor.controlBackgroundColor.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    (item.title as NSString).draw(
      at: NSPoint(x: 8, y: 6), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
    image.unlockFocus()
    let draggingItem = NSDraggingItem(pasteboardWriter: writer)
    draggingItem.setDraggingFrame(NSRect(origin: .zero, size: image.size), contents: image)
    beginDraggingSession(with: [draggingItem], event: event, source: self)
  }

  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation { .move }
  @objc private func toggle() { onToggle?() }
  @objc private func deleteTask() { onDelete?() }
}
