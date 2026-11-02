import AppKit

/// Owns editor/review lifetimes, nested-popover dismissal, and native drag-source retention.
/// The board only renders dates and task data.
@MainActor
final class TaskPopoverCoordinator {
  private let store: TaskStore
  private(set) var editor: TaskEditorPopover?
  private(set) var review: UnfinishedTasksPopover?
  var onEditorClosed: (() -> Void)?
  private weak var reviewAnchor: NSView?
  private var editorFromReview = false
  private var dragSource: TaskRowView?
  private var clickMonitor: Any?
  private var resignObserver: NSObjectProtocol?
  var isMonitoringOutsideClicks: Bool { clickMonitor != nil || resignObserver != nil }

  init(store: TaskStore) { self.store = store }

  var actions: TaskActions {
    TaskActions(
      open: { [weak self] item, anchor in
        self?.openEditor(item: item, on: DayKey.date(for: item.dayKey) ?? .now, anchor: anchor)
      },
      toggle: { [weak self] item in
        guard let self, self.editor?.requestClose() != false else { return }
        self.store.toggle(item)
      },
      delete: { [weak self] item in
        guard let self, self.editor?.requestClose() != false else { return }
        self.store.delete(item)
      })
  }

  func refreshReview() { review?.refresh() }

  func toggleReview(near anchor: NSView) {
    if review != nil {
      closeReview()
    } else {
      store.reload()
      showReview(near: anchor)
    }
  }

  func showReview(near anchor: NSView) {
    guard anchor.window != nil, closeAll() else { return }
    var actions = self.actions
    actions.open = { [weak self] item, _ in
      guard let self, let content = self.review?.contentViewController?.view,
        let date = DayKey.date(for: item.dayKey)
      else { return }
      self.openEditor(item: item, on: date, anchor: content, fromReview: true)
    }
    actions.beginDrag = { [weak self] row in self?.beginReviewDrag(row) }
    let popover = UnfinishedTasksPopover(store: store, actions: actions)
    popover.onClose = { [weak self, weak popover] in
      guard let self, self.review === popover else { return }
      self.review = nil
      self.reviewAnchor = nil
      self.stopMonitoring()
    }
    review = popover
    reviewAnchor = anchor
    if popover.present(near: anchor, preferredEdge: .minY) {
      startMonitoring()
    } else {
      review = nil
      reviewAnchor = nil
    }
  }

  func openEditor(item: TodoItem?, on date: Date, anchor: NSView, fromReview: Bool = false) {
    guard let content = anchor.window?.contentView else { return }
    let requestedRect = anchor.convert(anchor.bounds, to: content)
    if fromReview {
      guard editor?.requestClose() != false else { return }
    } else {
      guard closeAll() else { return }
    }
    // Closing may flush a queued board render. An old row may no longer be attached.
    guard content.window != nil else { return }
    if let item {
      guard let current = (store.items + store.unfinishedItems).first(where: { $0.id == item.id })
      else { return }
      store.beginEditing(current)
    } else {
      store.beginNewTask(on: date)
    }
    let popover = TaskEditorPopover(store: store)
    editorFromReview = fromReview
    if fromReview { popover.behavior = .applicationDefined }
    popover.onClose = { [weak self, weak popover] in
      guard let self, self.editor === popover else { return }
      self.editor = nil
      self.editorFromReview = false
      self.onEditorClosed?()
    }
    editor = popover
    if !popover.present(in: content, positioningRect: requestedRect, preferredEdge: .maxX) {
      store.closeEditor()
      editor = nil
      editorFromReview = false
      onEditorClosed?()
    }
  }

  @discardableResult
  func closeReview() -> Bool {
    if editorFromReview, editor?.requestClose() == false { return false }
    return review?.requestClose() ?? true
  }

  @discardableResult
  func closeAll() -> Bool {
    guard editor?.requestClose() != false else { return false }
    return closeReview()
  }

  private func beginReviewDrag(_ row: TaskRowView) {
    // AppKit still needs the source after the review closes to reveal the day cards.
    dragSource = row
    row.onDragEnded = { [weak self] in self?.dragSource = nil }
    DispatchQueue.main.async { [weak self] in self?.closeReview() }
  }

  private func startMonitoring() {
    guard !isMonitoringOutsideClicks else { return }
    let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    clickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
      guard let self else { return event }
      var window = event.window
      while let candidate = window {
        if candidate === self.editor?.contentViewController?.view.window { return event }
        if candidate === self.review?.contentViewController?.view.window {
          return self.editor?.requestClose() != false ? event : nil
        }
        window = candidate.parent
      }
      if event.window?.level == .popUpMenu
        || (event.window as? NSPanel)?.becomesKeyOnlyIfNeeded == true
      {
        return event
      }
      if let anchor = self.reviewAnchor, event.window === anchor.window,
        anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil))
      {
        return event
      }
      // Failed validation consumes the click so it cannot navigate away or discard the draft.
      return self.closeReview() ? event : nil
    }
    // App deactivation covers clicks in other apps without a global input monitor.
    resignObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.closeReview() }
    }
  }

  private func stopMonitoring() {
    if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    clickMonitor = nil
    resignObserver = nil
  }
}
