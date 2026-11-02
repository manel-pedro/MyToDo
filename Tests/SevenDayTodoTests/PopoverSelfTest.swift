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
    let store = TaskStore(
      repository: try LocalTaskRepository(
        fileURL: directory.appendingPathComponent("tasks.json")))
    let board = BoardViewController(store: store)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1260, height: 680),
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
        guard
          let add = descendants(board.view).compactMap({ $0 as? NSButton })
            .first(where: { $0.title == "+ Add" || $0.title == "+" })
        else {
          throw SelfTest.Failure.assertion("missing add button")
        }
        add.performClick(nil)
        pump()
        guard let editor = board.editor, editor.isShown,
          let content = editor.contentViewController?.view
        else {
          throw SelfTest.Failure.assertion(
            "editor should be visible at cycle \(iteration); anchor attached: \(add.window != nil), editor exists: \(board.editor != nil), shown: \(board.editor?.isShown ?? false)"
          )
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
          fields.first { $0.placeholderString == "Task title" }?.stringValue =
            "UI test \(iteration)"
          guard
            let notes = descendants(content).compactMap({ $0 as? NSTextView })
              .first(where: { !$0.isFieldEditor })
          else {
            throw SelfTest.Failure.assertion("missing notes field")
          }
          if iteration == 1 {
            let compactHeight = editor.contentSize.height
            notes.string = Array(repeating: "A line of notes", count: 24).joined(separator: "\n")
            notes.didChangeText()
            try require(
              editor.contentSize.height > compactHeight && editor.contentSize.height <= 480,
              "Notes should expand as text grows and remain bounded for scrolling")
          }
          notes.string = "# Heading\n**Note**"
          notes.didChangeText()
          var anchorPreserved = true
          let onChange = store.onChange
          store.onChange = {
            onChange?()
            if editor.isShown && add.window == nil { anchorPreserved = false }
          }
          // The editor saves through its outside-click/close-request path.
          editor.performClose(nil)
          store.onChange = onChange
          try require(anchorPreserved, "saving removed the anchor while editor was visible")
        }
        pump()
        try require(closedAfterHiding, "editor ownership released before popover finished closing")
        try require(board.editor == nil && store.draft == nil, "editor should close cleanly")
        if !iteration.isMultiple(of: 3) {
          try require(
            store.items.contains {
              $0.title == "UI test \(iteration)" && $0.notes == "# Heading\n**Note**"
            },
            "closing should persist title and notes at cycle \(iteration): \(store.items.map { ($0.title, $0.notes) })"
          )
        }
        guard
          let reviewButton = descendants(board.view).compactMap({ $0 as? NSButton })
            .first(where: { $0.title.hasPrefix("Unfinished tasks") })
        else {
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
        try require(
          reviewClosedAfterHiding && board.unfinishedPopover == nil,
          "review ownership should be released only after closing")

      }
    }
    try checkUnfinishedEditing(board: board, store: store)
    try checkFailedEditorSwitch()
    try checkLayouts(board: board, store: store, window: window)
    print(
      "24 editor and 24 review popover cycles passed: Cancel, autosave, transient close; Default and Month views"
    )
  }

  private static func checkUnfinishedEditing(board: BoardViewController, store: TaskStore) throws {
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
    store.beginNewTask(on: yesterday)
    store.setDraft(
      title: "Unfinished edit regression", notes: "Original", date: yesterday, isCompleted: false)
    try require(store.saveDraft(), "could not seed unfinished task")

    for mode in [TaskStore.ViewMode.days, .month] {
      store.setViewMode(mode)
      board.view.layoutSubtreeIfNeeded()
      guard
        let reviewButton = descendants(board.view).compactMap({ $0 as? NSButton })
          .first(where: { $0.title.hasPrefix("Unfinished tasks") })
      else {
        throw SelfTest.Failure.assertion("missing unfinished tasks button")
      }
      reviewButton.performClick(nil)
      pump()
      guard let review = board.unfinishedPopover,
        let reviewContent = review.contentViewController?.view,
        let row = descendants(reviewContent).compactMap({ $0 as? TaskRowView }).first
      else {
        throw SelfTest.Failure.assertion("missing unfinished task row")
      }
      row.onOpen?()
      pump()
      guard let editor = board.editor, let content = editor.contentViewController?.view else {
        throw SelfTest.Failure.assertion("unfinished task editor did not open")
      }
      try require(review.isShown && editor.isShown, "editing must keep unfinished tasks open")
      try click(in: content)
      try require(review.isShown && editor.isShown, "clicking editor must keep both popovers open")
      content.window?.makeFirstResponder(nil)
      descendants(content).compactMap { $0 as? NSTextField }
        .first { $0.placeholderString == "Task title" }?.stringValue = "Edited unfinished task"
      try click(in: reviewContent)
      try require(
        review.isShown && !editor.isShown && board.editor == nil,
        "clicking review must save and close only the editor")
      try require(
        store.unfinishedItems.contains { $0.title == "Edited unfinished task" },
        "returning to the list must save edits")
      guard let currentRow = descendants(reviewContent).compactMap({ $0 as? TaskRowView }).first
      else {
        throw SelfTest.Failure.assertion("missing updated unfinished task row")
      }
      currentRow.onOpen?()
      pump()
      guard let outsideEditor = board.editor else {
        throw SelfTest.Failure.assertion("could not reopen editor after returning to list")
      }
      try click(in: board.view)
      try require(
        !review.isShown && !outsideEditor.isShown, "outside click must close both popovers")
      try require(
        board.unfinishedPopover == nil && board.editor == nil && store.draft == nil,
        "outside click must clean up both popovers")
      try require(
        store.unfinishedItems.contains { $0.title == "Edited unfinished task" },
        "outside click must save the unfinished task edit")

      reviewButton.performClick(nil)
      pump()
      guard let reopened = board.unfinishedPopover,
        let reopenedContent = reopened.contentViewController?.view,
        let reopenedRow = descendants(reopenedContent).compactMap({ $0 as? TaskRowView }).first
      else {
        throw SelfTest.Failure.assertion("could not reopen unfinished tasks")
      }
      reopenedRow.onOpen?()
      pump()
      guard let reopenedEditor = board.editor,
        let reopenedEditorContent = reopenedEditor.contentViewController?.view
      else {
        throw SelfTest.Failure.assertion("could not reopen unfinished editor")
      }
      reopenedEditorContent.window?.makeFirstResponder(nil)
      descendants(reopenedEditorContent).compactMap { $0 as? NSTextField }
        .first { $0.placeholderString == "Task title" }?.stringValue =
        "Saved before switching editors"
      // Programmatic switching must use the same save path as clicking outside.
      reopenedRow.onOpen?()
      pump()
      try require(
        !reopenedEditor.isShown && reopened.isShown,
        "switching editors must close the previous editor and keep review open")
      try require(
        store.draft?.title == "Saved before switching editors",
        "reopening a task must load its freshly saved contents")
      guard let switchedEditor = board.editor else {
        throw SelfTest.Failure.assertion("missing replacement editor")
      }
      switchedEditor.performClose(nil)
      pump()
      try require(
        reopened.isShown && board.editor == nil, "autosaving must leave unfinished tasks open")
      reopenedRow.onOpen?()
      pump()
      guard let cancelledContent = board.editor?.contentViewController?.view else {
        throw SelfTest.Failure.assertion("could not open editor for cancel")
      }
      try button("Cancel", in: cancelledContent).performClick(nil)
      pump()
      try require(
        reopened.isShown && board.editor == nil, "cancelling must leave unfinished tasks open")
      try click(in: board.view)
      try require(board.unfinishedPopover == nil, "outside click must also close review alone")
    }
    print(
      "Unfinished task editing passed in Default and Month views: clicking review saves and closes editor, outside click closes both, switching preserves edits, autosave/Cancel preserve review"
    )
  }

  private static func checkFailedEditorSwitch() throws {
    let storage = MemoryStorage()
    let store = TaskStore(repository: try LocalTaskRepository(storage: storage))
    let coordinator = TaskPopoverCoordinator(store: store)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let anchor = NSButton(frame: NSRect(x: 30, y: 30, width: 100, height: 30))
    window.contentView?.addSubview(anchor)
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    coordinator.openEditor(item: nil, on: .now, anchor: anchor)
    pump()
    guard let original = coordinator.editor, let content = original.contentViewController?.view
    else {
      throw SelfTest.Failure.assertion("could not open failure-test editor")
    }
    content.window?.makeFirstResponder(nil)
    descendants(content).compactMap { $0 as? NSTextField }
      .first { $0.placeholderString == "Task title" }?.stringValue = "Unsaved draft"
    storage.shouldFail = true
    coordinator.openEditor(item: nil, on: .now, anchor: anchor)
    try require(
      coordinator.editor === original && original.isShown,
      "failed autosave must prevent replacing the editor")
    try require(
      store.draft?.title == "Unsaved draft" && !coordinator.closeAll(),
      "failed window/app close must retain the draft")
    try button("Cancel", in: content).performClick(nil)
    try require(
      coordinator.editor == nil && store.draft == nil, "Cancel must still discard explicitly")
    storage.shouldFail = false
    coordinator.showReview(near: anchor)
    try require(
      coordinator.isMonitoringOutsideClicks, "review should install its dismissal monitor")
    try require(
      coordinator.closeAll() && !coordinator.isMonitoringOutsideClicks,
      "closing review must remove every monitor")
    print("Failed-save editor switching, close validation and monitor cleanup passed")
  }

  private static func checkLayouts(board: BoardViewController, store: TaskStore, window: NSWindow)
    throws
  {
    for mode in [TaskStore.ViewMode.days, .month] {
      for size in [NSSize(width: 1080, height: 540), NSSize(width: 1260, height: 680)] {
        store.setViewMode(mode)
        window.setContentSize(size)
        board.view.layoutSubtreeIfNeeded()
        let cards = descendants(board.view).compactMap { $0 as? DayCardView }
        try require(cards.count == store.days.count, "every visible date should have a card")
        for card in cards {
          try require(
            card.bounds.width > 80 && card.bounds.height >= 64,
            "cards should fit the minimum window size")
        }
      }
    }
    if let output = ProcessInfo.processInfo.environment["SEVEN_DAY_TODO_SNAPSHOTS"] {
      let directory = URL(fileURLWithPath: output, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for mode in [TaskStore.ViewMode.days, .month] {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
          store.setViewMode(mode)
          window.appearance = NSAppearance(named: appearance)
          board.view.layoutSubtreeIfNeeded()
          board.view.displayIfNeeded()
          if let bitmap = board.view.bitmapImageRepForCachingDisplay(in: board.view.bounds) {
            board.view.cacheDisplay(in: board.view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
              try data.write(to: directory.appendingPathComponent("\(mode)-\(name).png"))
            }
          }
        }
      }
    }
    print("Default/Month layout checks passed at minimum and normal window sizes")
  }

  private static func click(in view: NSView) throws {
    guard let window = view.window,
      let event = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: view.convert(NSPoint(x: 3, y: 3), to: nil), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    else {
      throw SelfTest.Failure.assertion("could not create click event")
    }
    NSApp.sendEvent(event)
    pump()
  }

  private static func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  private static func button(_ title: String, in view: NSView) throws -> NSButton {
    guard
      let button = descendants(view).compactMap({ $0 as? NSButton })
        .first(where: { $0.title == title })
    else {
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
