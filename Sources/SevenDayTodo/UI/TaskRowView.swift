import AppKit

@MainActor
final class TaskRowView: NSView, NSDraggingSource {
  static let pasteboardType = NSPasteboard.PasteboardType("com.sevendaytodo.task-id")
  var onOpen: (() -> Void)?
  var onToggle: (() -> Void)?
  var onDelete: (() -> Void)?
  var onDragBegan: ((TaskRowView) -> Void)?
  var onDragEnded: (() -> Void)?
  var taskID: UUID { item.id }
  var isCompleted: Bool { item.isCompleted }
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
    grip.image = NSImage(
      systemSymbolName: "line.3.horizontal", accessibilityDescription: "Drag task")
    grip.contentTintColor = .tertiaryLabelColor
    grip.imageScaling = .scaleProportionallyDown
    grip.toolTip = "Drag to move to another day"
    grip.widthAnchor.constraint(equalToConstant: compact ? 10 : 13).isActive = true
    grip.heightAnchor.constraint(equalToConstant: 16).isActive = true
    let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle))
    checkbox.state = item.isCompleted ? .on : .off
    checkbox.setAccessibilityLabel("Complete \(item.title)")
    label.stringValue = item.title
    label.font = .systemFont(ofSize: 12)
    label.textColor = item.isCompleted ? .secondaryLabelColor : .labelColor
    label.lineBreakMode = .byTruncatingTail
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let delete = NSButton(
      title: "", target: self, action: #selector(deleteTask))
    delete.image = NSImage(
      systemSymbolName: "trash", accessibilityDescription: "Delete \(item.title)")
    delete.setAccessibilityLabel("Delete \(item.title)")
    delete.isBordered = false
    delete.contentTintColor = .tertiaryLabelColor
    label.setContentHuggingPriority(.init(249), for: .horizontal)
    delete.setContentHuggingPriority(.required, for: .horizontal)
    let stack = AppUI.stack(
      compact ? [grip, checkbox, label] : [delete, grip, checkbox, label],
      axis: .horizontal, spacing: 4, alignment: .centerY)
    AppUI.pin(stack, in: self, horizontal: 3, vertical: 2)
    heightAnchor.constraint(greaterThanOrEqualToConstant: compact ? 22 : 31).isActive = true
    setAccessibilityRole(.group)
    setAccessibilityLabel(item.title)
    toolTip =
      item.title + "\nDrag the handle or title to move; click to edit."
      + (item.notes.isEmpty ? "" : "\n" + item.notes)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverTracking { removeTrackingArea(hoverTracking) }
    let tracking = NSTrackingArea(
      rect: .zero,
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

  override func accessibilityPerformPress() -> Bool {
    guard let onOpen else { return false }
    onOpen()
    return true
  }

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
      NSRect(x: point.x - 24, y: point.y - 42, width: image.size.width, height: image.size.height),
      contents: image)
    let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = true
  }

  private func dragPreview() -> NSImage {
    let size = NSSize(width: min(320, max(220, bounds.width)), height: 68)
    let image = NSImage(size: size)
    image.lockFocus()
    effectiveAppearance.performAsCurrentDrawingAppearance {
      let card = NSBezierPath(
        roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6),
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
      NSBezierPath(
        roundedRect: NSRect(x: 14, y: 17, width: 3, height: 34), xRadius: 1.5, yRadius: 1.5
      ).fill()
      let paragraph = NSMutableParagraphStyle()
      paragraph.lineBreakMode = .byTruncatingTail
      (item.title as NSString).draw(
        in: NSRect(x: 26, y: 34, width: size.width - 44, height: 19),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 13, weight: .medium),
          .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ])
      ("Move to another day" as NSString).draw(
        at: NSPoint(x: 26, y: 17),
        withAttributes: [
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
