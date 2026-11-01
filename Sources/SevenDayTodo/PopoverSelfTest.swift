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
    print("24 editor and 24 review popover cycles passed: Cancel, Create, transient close; Default and Month views")
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
