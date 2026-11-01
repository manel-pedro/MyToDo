import AppKit

@MainActor
final class TaskEditorPopover: NSPopover, NSPopoverDelegate {
  private let store: TaskStore
  var onClose: (() -> Void)?
  private var hasFinishedEditing = false
  private var isSaving = false
  private let titleField = NSTextField()
  private let notesView = EditorNotesView()
  private var markdownPreview: MarkdownLivePreview?
  private var notesHeight: NSLayoutConstraint!
  private let datePicker = NSDatePicker()
  private let completed = NSButton(checkboxWithTitle: "Completed", target: nil, action: nil)
  private let compactNotes = true
  private let showsSaveButton = true

  init(store: TaskStore) {
    self.store = store
    super.init()
    behavior = .transient
    // Keep dismissal immediate and avoid AppKit window-transform teardown issues.
    animates = false
    delegate = self
    contentViewController = NSViewController()
    buildView()
    loadDraft()
    updatePreferredSize()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func show(near anchor: NSView) {
    show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
  }

  func dismiss() {
    if isShown { close() } else { finishEditing() }
  }

  private func buildView() {
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 300))
    contentViewController?.view = content
    titleField.placeholderString = "Task title"
    titleField.font = .systemFont(ofSize: 21, weight: .medium)
    titleField.isBordered = false
    titleField.isBezeled = false
    titleField.drawsBackground = false
    titleField.focusRingType = .none
    titleField.setAccessibilityLabel("Task title")

    let accent = NSView()
    accent.wantsLayer = true
    accent.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
    accent.layer?.cornerRadius = 2
    let titleRow = NSStackView(views: [accent, titleField])
    titleRow.alignment = .centerY
    titleRow.spacing = 10
    accent.widthAnchor.constraint(equalToConstant: 4).isActive = true
    accent.heightAnchor.constraint(equalToConstant: 28).isActive = true
    titleField.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true

    datePicker.datePickerStyle = .textFieldAndStepper
    datePicker.datePickerElements = [.yearMonthDay]
    datePicker.isBordered = false
    datePicker.isBezeled = false
    datePicker.drawsBackground = false
    datePicker.font = .systemFont(ofSize: 13)
    datePicker.setAccessibilityLabel("Scheduled date")
    completed.font = .systemFont(ofSize: 13)
    let dateRow = propertyRow(symbol: "calendar", label: "Date", control: datePicker)
    let statusRow = propertyRow(symbol: "checkmark.circle", label: "Status", control: completed)

    let notesScroll = textScroll()
    let notesIcon = symbol("note.text")
    let notesRow = NSStackView(views: [notesIcon, notesScroll])
    notesRow.alignment = .top
    notesRow.spacing = 10
    notesHeight = notesScroll.heightAnchor.constraint(equalToConstant: 74)
    notesHeight.isActive = true
    markdownPreview = MarkdownLivePreview(textView: notesView)
    markdownPreview?.onChange = { [weak self] in self?.updatePreferredSize() }

    let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
    let save = NSButton(title: store.selectedTask == nil ? "Create" : "Save", target: self,
                        action: #selector(saveAction))
    save.bezelStyle = .rounded
    save.keyEquivalent = "\r"
    save.keyEquivalentModifierMask = .command
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let actions = NSStackView(views: showsSaveButton ? [spacer, cancel, save] : [spacer, cancel])
    actions.spacing = 8

    let stack = NSStackView(views: [titleRow, separator(), dateRow, statusRow, separator(), notesRow, actions])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
      titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
      dateRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
      statusRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
      notesRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
      actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
  }

  private func symbol(_ name: String) -> NSImageView {
    let image = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil)!)
    image.contentTintColor = .secondaryLabelColor
    image.imageScaling = .scaleProportionallyDown
    image.widthAnchor.constraint(equalToConstant: 16).isActive = true
    image.heightAnchor.constraint(equalToConstant: 20).isActive = true
    return image
  }

  private func propertyRow(symbol name: String, label: String, control: NSView) -> NSStackView {
    let caption = NSTextField(labelWithString: label)
    caption.font = .systemFont(ofSize: 12)
    caption.textColor = .secondaryLabelColor
    caption.widthAnchor.constraint(equalToConstant: 54).isActive = true
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let row = NSStackView(views: [symbol(name), caption, control, spacer])
    row.alignment = .centerY
    row.spacing = 10
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
    return row
  }

  private func separator() -> NSBox {
    let separator = NSBox()
    separator.boxType = .separator
    return separator
  }

  private func textScroll() -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    scroll.drawsBackground = false
    notesView.frame = NSRect(x: 0, y: 0, width: 318, height: 74)
    notesView.minSize = .zero
    notesView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    notesView.isVerticallyResizable = true
    notesView.isHorizontallyResizable = false
    notesView.isEditable = true
    notesView.isSelectable = true
    notesView.isRichText = true
    notesView.importsGraphics = false
    notesView.allowsUndo = true
    notesView.drawsBackground = false
    notesView.isAutomaticQuoteSubstitutionEnabled = false
    notesView.isAutomaticDashSubstitutionEnabled = false
    notesView.font = .systemFont(ofSize: 13)
    notesView.textContainerInset = NSSize(width: 0, height: 5)
    notesView.autoresizingMask = [.width]
    notesView.textContainer?.widthTracksTextView = true
    notesView.textContainer?.containerSize = NSSize(width: 318, height: CGFloat.greatestFiniteMagnitude)
    notesView.setAccessibilityLabel("Notes")
    scroll.documentView = notesView
    return scroll
  }

  private func updatePreferredSize() {
    contentViewController?.view.layoutSubtreeIfNeeded()
    var height: CGFloat = 260
    if compactNotes, let container = notesView.textContainer, let layout = notesView.layoutManager {
      layout.ensureLayout(for: container)
      height = min(260, max(74, ceil(layout.usedRect(for: container).height) + 16))
    }
    notesHeight.constant = height
    contentSize = NSSize(width: 380, height: 218 + height)
    notesView.needsDisplay = true
  }

  private func loadDraft() {
    guard let draft = store.draft else { return }
    titleField.stringValue = draft.title
    notesView.string = draft.notes
    markdownPreview?.render()
    datePicker.dateValue = draft.date
    completed.state = draft.isCompleted ? .on : .off
  }

  private func captureDraft() {
    // Commit the active title/date field editor before reading the controls.
    contentViewController?.view.window?.makeFirstResponder(nil)
    store.setDraft(title: titleField.stringValue, notes: notesView.string,
                   date: datePicker.dateValue, isCompleted: completed.state == .on)
  }

  @objc private func saveAction() {
    if saveChanges() { dismiss() }
  }

  @objc private func cancelAction() { dismiss() }

  private func saveChanges() -> Bool {
    guard !isSaving else { return false }
    isSaving = true
    defer { isSaving = false }
    captureDraft()
    return store.saveDraft()
  }

  func popoverShouldClose(_ popover: NSPopover) -> Bool {
    if hasFinishedEditing || store.draft == nil { return true }
    contentViewController?.view.window?.makeFirstResponder(nil)
    if titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      store.selectedTask == nil { return true }
    return saveChanges()
  }

  func popoverDidShow(_ notification: Notification) {
    contentViewController?.view.window?.makeFirstResponder(titleField)
  }

  func popoverDidClose(_ notification: Notification) { finishEditing() }

  private func finishEditing() {
    guard !hasFinishedEditing else { return }
    hasFinishedEditing = true
    store.closeEditor()
    onClose?()
  }
}

@MainActor
private final class EditorNotesView: NSTextView {
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard string.isEmpty else { return }
    let placeholder = NSAttributedString(string: "Add notes", attributes: [
      .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor,
    ])
    placeholder.draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height))
  }
}
