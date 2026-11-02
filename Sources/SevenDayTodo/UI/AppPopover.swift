import AppKit

/// Centralizes safe popover ownership: owners release only after AppKit has closed it.
@MainActor
class AppPopover: NSPopover, NSPopoverDelegate {
  var onClose: (() -> Void)?
  private var notifiedClose = false

  init(size: NSSize, behavior: NSPopover.Behavior = .transient) {
    super.init()
    self.behavior = behavior
    // Avoid the AppKit window-transform teardown crash seen on macOS 27.
    animates = false
    delegate = self
    let controller = NSViewController()
    controller.view = NSView(frame: NSRect(origin: .zero, size: size))
    contentViewController = controller
    contentSize = size
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @discardableResult
  func present(near anchor: NSView, preferredEdge: NSRectEdge) -> Bool {
    guard let content = anchor.window?.contentView else { return false }
    return present(
      in: content, positioningRect: anchor.convert(anchor.bounds, to: content),
      preferredEdge: preferredEdge)
  }

  @discardableResult
  func present(in content: NSView, positioningRect: NSRect, preferredEdge: NSRectEdge) -> Bool {
    guard content.window != nil else { return false }
    let visible = content.visibleRect
    guard !visible.isEmpty else { return false }
    // AppKit silently refuses offscreen positioning rectangles after a resize or
    // queued render. Clamp both editor and review anchors to the visible content.
    let width = min(positioningRect.width, visible.width)
    let height = min(positioningRect.height, visible.height)
    let rect = NSRect(
      x: min(max(positioningRect.minX, visible.minX), visible.maxX - width),
      y: min(max(positioningRect.minY, visible.minY), visible.maxY - height),
      width: width, height: height)
    show(relativeTo: rect, of: content, preferredEdge: preferredEdge)
    return isShown
  }

  /// A validated close request, including autosave. False means the editor must stay open.
  @discardableResult
  func requestClose() -> Bool {
    guard isShown else { return true }
    performClose(nil)
    return !isShown
  }

  func popoverShouldClose(_ popover: NSPopover) -> Bool { true }
  func didShow() {}
  func didClose() {}

  func popoverWillShow(_ notification: Notification) { notifiedClose = false }
  func popoverDidShow(_ notification: Notification) { didShow() }
  func popoverDidClose(_ notification: Notification) {
    guard !notifiedClose else { return }
    notifiedClose = true
    didClose()
    onClose?()
  }
}
