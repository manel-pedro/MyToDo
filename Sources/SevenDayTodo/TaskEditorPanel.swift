import AppKit
import WebKit

@MainActor
final class TaskEditorPanel: NSPanel, NSWindowDelegate, WKNavigationDelegate {
  private let store: TaskStore
  private let onClose: () -> Void
  private let titleField = NSTextField()
  private let notesView = NSTextView()
  private let renderedNotes: WKWebView
  private var markdownPreview: MarkdownLivePreview?
  private var previewUpdate: DispatchWorkItem?
  private let datePicker = NSDatePicker()
  private let completed = NSButton(checkboxWithTitle: "Completed", target: nil, action: nil)

  init(store: TaskStore, onClose: @escaping () -> Void) {
    self.store = store
    self.onClose = onClose
    let webConfiguration = WKWebViewConfiguration()
    webConfiguration.defaultWebpagePreferences.allowsContentJavaScript = false
    renderedNotes = WKWebView(frame: .zero, configuration: webConfiguration)
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 450, height: 630),
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
    markdownPreview?.onChange = { [weak self] in self?.scheduleRenderedPreview() }
    renderedNotes.underPageBackgroundColor = .textBackgroundColor
    renderedNotes.navigationDelegate = self
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
      section("Rendered Preview"), renderedNotes,
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
      notesScroll.heightAnchor.constraint(equalToConstant: 210),
      renderedNotes.widthAnchor.constraint(equalTo: stack.widthAnchor),
      renderedNotes.heightAnchor.constraint(equalToConstant: 180),
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
    updateRenderedPreview()
    datePicker.dateValue = draft.date
    completed.state = draft.isCompleted ? .on : .off
    makeFirstResponder(titleField)
  }

  private func captureDraft() {
    store.setDraft(
      title: titleField.stringValue, notes: notesView.string,
      date: datePicker.dateValue, isCompleted: completed.state == .on)
  }

  private func scheduleRenderedPreview() {
    previewUpdate?.cancel()
    let update = DispatchWorkItem { [weak self] in self?.updateRenderedPreview() }
    previewUpdate = update
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: update)
  }

  private func updateRenderedPreview() {
    let support = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("SevenDayTodo", isDirectory: true)
    renderedNotes.loadHTMLString(MarkdownHTMLRenderer.render(notesView.string), baseURL: support)
  }

  @objc private func saveAction() {
    captureDraft()
    if store.saveDraft() { close() }
  }

  @objc private func cancelAction() { close() }

  func windowWillClose(_ notification: Notification) {
    previewUpdate?.cancel()
    store.closeEditor()
    onClose()
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
  ) async -> WKNavigationActionPolicy {
    guard navigationAction.navigationType == .linkActivated else {
      return .allow
    }
    if let url = navigationAction.request.url,
      ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
    {
      NSWorkspace.shared.open(url)
    }
    return .cancel
  }
}
