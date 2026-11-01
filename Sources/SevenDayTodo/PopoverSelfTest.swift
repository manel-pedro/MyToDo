import AppKit

/// Exercises real popovers with disposable storage; never opens the user's task file.
@MainActor
enum PopoverSelfTest {
  static func run() throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TaskStore(repository: try LocalTaskRepository(
      fileURL: directory.appendingPathComponent("tasks.json")))
    let board = BoardViewController(store: store)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 680),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = board
    window.center()
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    pump()

    for iteration in 0..<24 {
      try autoreleasepool {
        store.setViewMode(iteration.isMultiple(of: 2) ? .days : .month)
        board.view.layoutSubtreeIfNeeded()
        guard let add = descendants(board.view).compactMap({ $0 as? NSButton })
          .first(where: { $0.title == "+ Add" || $0.title == "+" }) else {
          throw SelfTest.Failure.assertion("missing add button")
        }
        add.performClick(nil)
        pump()
        guard let editor = board.editor, editor.isShown,
          let content = editor.contentViewController?.view else {
          throw SelfTest.Failure.assertion("editor should be visible")
        }
        var closedAfterHiding = false
        let onClose = editor.onClose
        editor.onClose = { [weak editor] in
          closedAfterHiding = editor?.isShown == false
          onClose?()
        }
        if iteration.isMultiple(of: 3) {
          try button("Cancel", in: content).performClick(nil)
        } else {
          content.window?.makeFirstResponder(nil)
          let fields = descendants(content).compactMap { $0 as? NSTextField }
          fields.first { $0.placeholderString == "Task title" }?.stringValue = "UI test \(iteration)"
          descendants(content).compactMap { $0 as? NSTextView }.first(where: { !$0.isFieldEditor })?.string = "# Heading\n**Note**"
          var anchorPreserved = true
          let onChange = store.onChange
          store.onChange = {
            onChange?()
            if editor.isShown && add.window == nil { anchorPreserved = false }
          }
          if iteration.isMultiple(of: 2) {
            // The transient popover's click-outside/close-request path.
            editor.performClose(nil)
          } else {
            try button("Create", in: content).performClick(nil)
          }
          store.onChange = onChange
          try require(anchorPreserved, "saving removed the anchor while editor was visible")
        }
        pump()
        try require(closedAfterHiding, "editor ownership released before popover finished closing")
        try require(board.editor == nil && store.draft == nil, "editor should close cleanly")
        if !iteration.isMultiple(of: 3) {
          try require(store.items.contains {
            $0.title == "UI test \(iteration)" && $0.notes == "# Heading\n**Note**"
          }, "closing should persist title and notes at cycle \(iteration): \(store.items.map { ($0.title, $0.notes) })")
        }
        guard let reviewButton = descendants(board.view).compactMap({ $0 as? NSButton })
          .first(where: { $0.title.hasPrefix("Unfinished tasks") }) else {
          throw SelfTest.Failure.assertion("missing unfinished tasks button")
        }
        reviewButton.performClick(nil)
        pump()
        guard let review = board.unfinishedPopover, review.isShown else {
          throw SelfTest.Failure.assertion("review should open")
        }
        var reviewClosedAfterHiding = false
        let reviewOnClose = review.onClose
        review.onClose = { [weak review] in
          reviewClosedAfterHiding = review?.isShown == false
          reviewOnClose?()
        }
        review.performClose(nil)
        pump()
        try require(reviewClosedAfterHiding && board.unfinishedPopover == nil,
          "review ownership should be released only after closing")

      }
    }
    try checkUnfinishedEditing(board: board, store: store)
    print("24 editor and 24 review popover cycles passed: Cancel, Create, transient close; Default and Month views")
  }

  private static func checkUnfinishedEditing(board: BoardViewController, store: TaskStore) throws {
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
    store.beginNewTask(on: yesterday)
    store.setDraft(title: "Unfinished edit regression", notes: "Original", date: yesterday, isCompleted: false)
    try require(store.saveDraft(), "could not seed unfinished task")

    for mode in [TaskStore.ViewMode.days, .month] {
      store.setViewMode(mode)
      board.view.layoutSubtreeIfNeeded()
      guard let reviewButton = descendants(board.view).compactMap({ $0 as? NSButton })
        .first(where: { $0.title.hasPrefix("Unfinished tasks") }) else {
        throw SelfTest.Failure.assertion("missing unfinished tasks button")
      }
      reviewButton.performClick(nil)
      pump()
      guard let review = board.unfinishedPopover, let reviewContent = review.contentViewController?.view,
        let row = descendants(reviewContent).compactMap({ $0 as? TaskRowView }).first else {
        throw SelfTest.Failure.assertion("missing unfinished task row")
      }
      row.onOpen?()
      pump()
      guard let editor = board.editor, let content = editor.contentViewController?.view else {
        throw SelfTest.Failure.assertion("unfinished task editor did not open")
      }
      try require(review.isShown && editor.isShown, "editing must keep unfinished tasks open")
      try click(in: reviewContent)
      try require(review.isShown && editor.isShown, "clicking review must keep both popovers open")
      try click(in: content)
      try require(review.isShown && editor.isShown, "clicking editor must keep both popovers open")
      content.window?.makeFirstResponder(nil)
      descendants(content).compactMap { $0 as? NSTextField }
        .first { $0.placeholderString == "Task title" }?.stringValue = "Edited unfinished task"
      try click(in: board.view)
      try require(!review.isShown && !editor.isShown, "outside click must close both popovers")
      try require(board.unfinishedPopover == nil && board.editor == nil && store.draft == nil,
        "outside click must clean up both popovers")
      try require(store.unfinishedItems.contains { $0.title == "Edited unfinished task" },
        "outside click must save the unfinished task edit")

      reviewButton.performClick(nil)
      pump()
      guard let reopened = board.unfinishedPopover,
        let reopenedContent = reopened.contentViewController?.view,
        let reopenedRow = descendants(reopenedContent).compactMap({ $0 as? TaskRowView }).first else {
        throw SelfTest.Failure.assertion("could not reopen unfinished tasks")
      }
      reopenedRow.onOpen?()
      pump()
      guard let reopenedEditor = board.editor, let reopenedEditorContent = reopenedEditor.contentViewController?.view else {
        throw SelfTest.Failure.assertion("could not reopen unfinished editor")
      }
      try button("Save", in: reopenedEditorContent).performClick(nil)
      pump()
      try require(reopened.isShown && board.editor == nil, "saving must leave unfinished tasks open")
      reopenedRow.onOpen?()
      pump()
      guard let cancelledContent = board.editor?.contentViewController?.view else {
        throw SelfTest.Failure.assertion("could not open editor for cancel")
      }
      try button("Cancel", in: cancelledContent).performClick(nil)
      pump()
      try require(reopened.isShown && board.editor == nil, "cancelling must leave unfinished tasks open")
      try click(in: board.view)
      try require(board.unfinishedPopover == nil, "outside click must also close review alone")
    }
    print("Unfinished task editing passed in Default and Month views: both stay open, outside click saves and closes both, Save/Cancel preserve review")
  }

  private static func click(in view: NSView) throws {
    guard let window = view.window,
      let event = NSEvent.mouseEvent(with: .leftMouseDown,
        location: view.convert(NSPoint(x: 3, y: 3), to: nil), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else {
      throw SelfTest.Failure.assertion("could not create click event")
    }
    NSApp.sendEvent(event)
    pump()
  }

  private static func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  private static func button(_ title: String, in view: NSView) throws -> NSButton {
    guard let button = descendants(view).compactMap({ $0 as? NSButton })
      .first(where: { $0.title == title }) else {
      throw SelfTest.Failure.assertion("missing \(title) button")
    }
    return button
  }

  private static func pump() {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.12))
  }

  private static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw SelfTest.Failure.assertion(message) }
  }
}
