import AppKit

@MainActor
final class TaskEditorPanel: NSPanel, NSWindowDelegate {
  private let store: TaskStore
  private let onClose: () -> Void
  private let titleField = NSTextField()
  private let notesView = NSTextView()
  private var markdownPreview: MarkdownLivePreview?
  private let datePicker = NSDatePicker()
  private let completed = NSButton(checkboxWithTitle: "Completed", target: nil, action: nil)

  init(store: TaskStore, onClose: @escaping () -> Void) {
    self.store = store
    self.onClose = onClose
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 450, height: 480),
      styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
    isFloatingPanel = true
    level = .floating
    delegate = self
    title = store.selectedTask == nil ? "New Task" : "Edit Task"
    buildView()
    loadDraft()
  }

  func show(near anchor: NSRect?, parent: NSWindow?) {
    if let anchor {
      let screen = parent?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor
      let proposedX = anchor.maxX + 8
      let x = min(max(proposedX, screen.minX), screen.maxX - frame.width)
      let y = min(max(anchor.maxY - frame.height, screen.minY), screen.maxY - frame.height)
      setFrameOrigin(NSPoint(x: x, y: y))
    } else {
      center()
    }
    makeKeyAndOrderFront(nil)
  }

  private func buildView() {
    let content = NSView()
    contentView = content
    titleField.placeholderString = "Task title"

    datePicker.datePickerStyle = .textFieldAndStepper
    datePicker.datePickerElements = [.yearMonthDay]
    let dateRow = NSStackView(views: [NSTextField(labelWithString: "Date"), datePicker, completed])
    dateRow.orientation = .horizontal
    dateRow.spacing = 12

    let notesScroll = textScroll(for: notesView)
    markdownPreview = MarkdownLivePreview(textView: notesView)
    let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
    let save = NSButton(
      title: store.selectedTask == nil ? "Create" : "Save", target: self,
      action: #selector(saveAction))
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let actions = NSStackView(views: [spacer, cancel, save])
    actions.orientation = .horizontal
    actions.spacing = 8

    let stack = NSStackView(views: [
      section("Title"), titleField,
      section("Notes"), notesScroll,
      dateRow,
      actions,
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
      titleField.widthAnchor.constraint(equalTo: stack.widthAnchor),
      notesScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
      notesScroll.heightAnchor.constraint(equalToConstant: 270),
      actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
  }

  private func section(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    return label
  }

  private func textScroll(for textView: NSTextView) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    scroll.drawsBackground = true
    textView.frame = NSRect(x: 0, y: 0, width: 400, height: 270)
    textView.minSize = NSSize(width: 0, height: 270)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.isRichText = true
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.font = .systemFont(ofSize: 12)
    textView.textContainerInset = NSSize(width: 5, height: 5)
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: 400,
      height: CGFloat.greatestFiniteMagnitude)
    scroll.documentView = textView
    return scroll
  }

  private func loadDraft() {
    guard let draft = store.draft else { return }
    titleField.stringValue = draft.title
    notesView.string = draft.notes
    markdownPreview?.render()
    datePicker.dateValue = draft.date
    completed.state = draft.isCompleted ? .on : .off
    makeFirstResponder(titleField)
  }

  private func captureDraft() {
    store.setDraft(
      title: titleField.stringValue, notes: notesView.string,
      date: datePicker.dateValue, isCompleted: completed.state == .on)
  }

  @objc private func saveAction() {
    captureDraft()
    if store.saveDraft() { close() }
  }

  @objc private func cancelAction() { close() }

  func windowWillClose(_ notification: Notification) {
    store.closeEditor()
    onClose()
  }
}
