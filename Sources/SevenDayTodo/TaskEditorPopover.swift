import AppKit

@MainActor
final class TaskEditorPopover: AppPopover {
  private let store: TaskStore
  private var isSaving = false
  private let titleField = NSTextField()
  private let notes = MarkdownNotesView()
  private lazy var notesHeight = notes.heightAnchor.constraint(equalToConstant: 74)
  private let datePicker = AppUI.datePicker()
  private let completed = NSButton(checkboxWithTitle: "Completed", target: nil, action: nil)

  init(store: TaskStore) {
    self.store = store
    super.init(size: NSSize(width: 380, height: 300))
    buildView()
    loadDraft()
    updatePreferredSize()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func buildView() {
    guard let content = contentViewController?.view else { return }
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

    datePicker.isBordered = false
    datePicker.isBezeled = false
    datePicker.drawsBackground = false
    datePicker.font = .systemFont(ofSize: 13)
    datePicker.setAccessibilityLabel("Scheduled date")
    completed.font = .systemFont(ofSize: 13)
    let dateRow = AppUI.propertyRow(symbol: "calendar", label: "Date", control: datePicker)
    let statusRow = AppUI.propertyRow(
      symbol: "checkmark.circle", label: "Status", control: completed)

    let notesScroll = notes
    let notesIcon = AppUI.symbol("note.text")
    let notesRow = NSStackView(views: [notesIcon, notesScroll])
    notesRow.alignment = .top
    notesRow.spacing = 10
    notesHeight.isActive = true
    notes.onChange = { [weak self] in self?.updatePreferredSize() }

    let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let actions = NSStackView(views: [spacer, cancel])
    actions.spacing = 8

    let stack = NSStackView(views: [
      titleRow, AppUI.separator(), dateRow, statusRow, AppUI.separator(), notesRow, actions,
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)
    for divider in stack.arrangedSubviews.compactMap({ $0 as? NSBox }) {
      divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
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

  private func updatePreferredSize() {
    contentViewController?.view.layoutSubtreeIfNeeded()
    let height = notes.preferredHeight(minimum: 74, maximum: 260)
    notesHeight.constant = height
    contentSize = NSSize(width: 380, height: 218 + height)
  }

  private func loadDraft() {
    guard let draft = store.draft else { return }
    titleField.stringValue = draft.title
    notes.source = draft.notes
    datePicker.dateValue = draft.date
    completed.state = draft.isCompleted ? .on : .off
  }

  private func captureDraft() {
    // Commit the active title/date field editor before reading the controls.
    store.setDraft(
      title: titleField.stringValue, notes: notes.source,
      date: datePicker.dateValue, isCompleted: completed.state == .on)
  }

  @objc private func cancelAction() { close() }

  private func saveChanges() -> Bool {
    guard !isSaving else { return false }
    isSaving = true
    defer { isSaving = false }
    guard contentViewController?.view.window?.makeFirstResponder(nil) != false else { return false }
    captureDraft()
    return store.saveDraft()
  }

  override func popoverShouldClose(_ popover: NSPopover) -> Bool {
    if store.draft == nil { return true }
    let title = titleField.currentEditor()?.string ?? titleField.stringValue
    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      store.selectedTask == nil
    {
      return true
    }
    return saveChanges()
  }

  override func didShow() {
    contentViewController?.view.window?.makeFirstResponder(titleField)
  }

  override func didClose() { store.closeEditor() }
}
