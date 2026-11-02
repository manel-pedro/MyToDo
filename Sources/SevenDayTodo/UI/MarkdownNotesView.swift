import AppKit

/// One editable source document; styling never replaces its Markdown characters.
@MainActor
final class MarkdownNotesView: NSScrollView {
  var onChange: (() -> Void)?
  private let editor: MarkdownSourceTextView
  private let preview: MarkdownLivePreview

  var source: String {
    get { editor.string }
    set {
      editor.string = newValue
      preview.render()
      editor.needsDisplay = true
    }
  }

  override init(frame frameRect: NSRect) {
    let editor = MarkdownSourceTextView()
    self.editor = editor
    preview = MarkdownLivePreview(textView: editor)
    super.init(frame: frameRect)
    hasVerticalScroller = true
    autohidesScrollers = true
    borderType = .noBorder
    drawsBackground = false
    editor.frame = NSRect(x: 0, y: 0, width: 318, height: 74)
    editor.minSize = .zero
    editor.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.isEditable = true
    editor.isSelectable = true
    editor.isRichText = true
    editor.importsGraphics = false
    editor.allowsUndo = true
    editor.drawsBackground = false
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.font = .systemFont(ofSize: 13)
    editor.textContainerInset = NSSize(width: 0, height: 5)
    editor.autoresizingMask = [.width]
    editor.textContainer?.widthTracksTextView = true
    editor.textContainer?.containerSize = NSSize(
      width: 400, height: CGFloat.greatestFiniteMagnitude)
    editor.setAccessibilityLabel("Notes")
    documentView = editor
    preview.onChange = { [weak self] in self?.onChange?() }
    editor.onFocusChange = { [weak self] focused in
      guard let self else { return }
      self.preview.render(activeSelection: focused ? self.editor.selectedRange() : nil)
    }
  }

  func preferredHeight(minimum: CGFloat, maximum: CGFloat) -> CGFloat {
    guard let container = editor.textContainer, let layout = editor.layoutManager else {
      return maximum
    }
    layout.ensureLayout(for: container)
    return min(maximum, max(minimum, ceil(layout.usedRect(for: container).height) + 16))
  }

  convenience init() { self.init(frame: .zero) }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
private final class MarkdownSourceTextView: NSTextView {
  var onFocusChange: ((Bool) -> Void)?

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { onFocusChange?(true) }
    return accepted
  }

  override func resignFirstResponder() -> Bool {
    let accepted = super.resignFirstResponder()
    if accepted { onFocusChange?(false) }
    return accepted
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard string.isEmpty else { return }
    let placeholder = NSAttributedString(
      string: "Add notes",
      attributes: [
        .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor,
      ])
    placeholder.draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height))
  }

  // Clipboard formatting and attachments must not enter a Markdown source document.
  override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}
