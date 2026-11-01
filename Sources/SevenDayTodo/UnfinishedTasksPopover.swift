import AppKit

@MainActor
final class UnfinishedTasksPopover: NSPopover, NSPopoverDelegate {
  private enum Choice: Int { case later, today, tomorrow, date, completed }
  private let store: TaskStore
  private let rows = NSStackView()
  private let subtitle = NSTextField(labelWithString: "")
  private let applyButton = NSButton(title: "Update plan", target: nil, action: nil)
  private let undoButton = NSButton(title: "Undo", target: nil, action: nil)
  private var choices: [UUID: Choice] = [:]
  private var dates: [UUID: Date] = [:]
  var onClose: (() -> Void)?
  var onOpenTask: ((TodoItem) -> Void)?
  var onBeginTaskDrag: ((TaskRowView) -> Void)?

  init(store: TaskStore) {
    self.store = store
    super.init()
    behavior = .transient
    // Avoid AppKit window-transform animation teardown during dismissal.
    animates = false
    delegate = self
    contentViewController = NSViewController()
    buildView()
    contentSize = NSSize(width: 440, height: 500)
    refresh()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func buildView() {
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 500))
    contentViewController?.view = content
    let heading = NSTextField(labelWithString: "Carry forward")
    heading.font = .systemFont(ofSize: 20, weight: .semibold)
    subtitle.font = .systemFont(ofSize: 12)
    subtitle.textColor = .secondaryLabelColor

    rows.orientation = .vertical
    rows.alignment = .leading
    rows.spacing = 10
    rows.translatesAutoresizingMaskIntoConstraints = false
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    let document = ReviewDocumentView()
    document.translatesAutoresizingMaskIntoConstraints = false
    document.addSubview(rows)
    scroll.documentView = document
    NSLayoutConstraint.activate([
      document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
      rows.leadingAnchor.constraint(equalTo: document.leadingAnchor),
      rows.trailingAnchor.constraint(equalTo: document.trailingAnchor),
      rows.topAnchor.constraint(equalTo: document.topAnchor),
      rows.bottomAnchor.constraint(equalTo: document.bottomAnchor),
    ])

    undoButton.target = self
    undoButton.action = #selector(undoPlan)
    applyButton.target = self
    applyButton.action = #selector(applyPlan)
    let later = NSButton(title: "Review later", target: self, action: #selector(reviewLater))
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let actions = NSStackView(views: [undoButton, spacer, later, applyButton])
    actions.spacing = 8
    let stack = NSStackView(views: [heading, subtitle, scroll, actions])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
      scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
      scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
      actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
  }

  func refresh() {
    let items = store.unfinishedItems
    let groupCount = Set(items.map(\.dayKey)).count
    contentSize = NSSize(width: 440, height: min(500, max(200, 150 + items.count * 80 + groupCount * 28)))
    let ids = Set(items.map(\.id))
    choices = choices.filter { ids.contains($0.key) }
    dates = dates.filter { ids.contains($0.key) }
    subtitle.stringValue = items.isEmpty
      ? "All caught up — no unfinished tasks from earlier days."
      : "\(items.count) unfinished \(items.count == 1 ? "task" : "tasks") · most recent day first"
    undoButton.isHidden = !store.canUndoReview
    updateApplyButton()
    rows.arrangedSubviews.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
    var previousDay: String?
    for item in items {
      if item.dayKey != previousDay {
        let date = DayKey.date(for: item.dayKey)
        let title = date.map { date in
          Calendar.current.isDateInYesterday(date)
            ? "Yesterday · \(date.formatted(.dateTime.day().month(.abbreviated).year()))"
            : date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year())
        } ?? item.dayKey
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        rows.addArrangedSubview(label)
        previousDay = item.dayKey
      }
      let taskRow = TaskRowView(item: item)
      taskRow.onDragBegan = { [weak self] row in self?.onBeginTaskDrag?(row) }
      taskRow.onOpen = { [weak self] in self?.onOpenTask?(item) }
      taskRow.onToggle = { [weak self] in self?.store.toggle(item) }
      taskRow.onDelete = { [weak self] in self?.store.delete(item) }
      let menu = PlanChoiceButton()
      menu.taskID = item.id
      menu.addItems(withTitles: ["Decide later", "Today", "Tomorrow", "Choose a date…", "Already completed"])
      menu.selectItem(at: (choices[item.id] ?? .later).rawValue)
      menu.target = self
      menu.action = #selector(changeChoice(_:))
      menu.setAccessibilityLabel("Next step for \(item.title)")
      let picker = PlanDatePicker()
      picker.taskID = item.id
      picker.datePickerStyle = .textFieldAndStepper
      picker.datePickerElements = [.yearMonthDay]
      picker.minDate = Calendar.current.startOfDay(for: .now)
      picker.dateValue = dates[item.id] ?? Calendar.current.date(byAdding: .day, value: 2, to: .now)!
      picker.isHidden = choices[item.id] != .date
      picker.target = self
      picker.action = #selector(changeDate(_:))
      picker.setAccessibilityLabel("New date for \(item.title)")
      let controls = NSStackView(views: [menu, picker])
      controls.orientation = .vertical
      controls.alignment = .leading
      controls.spacing = 4
      let nextStep = NSTextField(labelWithString: "Next step")
      nextStep.font = .systemFont(ofSize: 11)
      nextStep.textColor = .secondaryLabelColor
      let spacer = NSView()
      spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
      let planning = NSStackView(views: [nextStep, spacer, controls])
      planning.alignment = .top
      planning.spacing = 8
      let row = NSStackView(views: [taskRow, planning])
      row.orientation = .vertical
      row.alignment = .leading
      row.spacing = 6
      rows.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
      taskRow.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
      planning.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
      controls.widthAnchor.constraint(equalToConstant: 170).isActive = true
      menu.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
      let divider = NSBox()
      divider.boxType = .separator
      rows.addArrangedSubview(divider)
      divider.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
    }
  }

  private func updateApplyButton() {
    applyButton.isEnabled = choices.values.contains { $0 != .later }
  }

  @objc private func changeChoice(_ sender: PlanChoiceButton) {
    guard let id = sender.taskID, let choice = Choice(rawValue: sender.indexOfSelectedItem) else { return }
    choices[id] = choice
    if choice == .date && dates[id] == nil {
      dates[id] = Calendar.current.date(byAdding: .day, value: 2, to: .now)
    }
    refresh()
  }

  @objc private func changeDate(_ sender: PlanDatePicker) {
    guard let id = sender.taskID else { return }
    dates[id] = sender.dateValue
    updateApplyButton()
  }

  @objc private func applyPlan() {
    let today = Calendar.current.startOfDay(for: .now)
    let updates = store.unfinishedItems.compactMap { item -> TaskPlanUpdate? in
      guard let choice = choices[item.id], choice != .later else { return nil }
      let day: Date
      switch choice {
      case .today: day = today
      case .tomorrow: day = Calendar.current.date(byAdding: .day, value: 1, to: today)!
      case .date: day = dates[item.id] ?? today
      case .completed:
        return TaskPlanUpdate(id: item.id, dayKey: item.dayKey, isCompleted: true)
      case .later: return nil
      }
      return TaskPlanUpdate(id: item.id, dayKey: DayKey.value(for: day), isCompleted: false)
    }
    if store.applyReviewPlan(updates) {
      choices.removeAll()
      dates.removeAll()
      refresh()
    }
  }

  @objc private func undoPlan() { store.undoReviewPlan() }
  @objc private func reviewLater() { performClose(nil) }
  func popoverDidClose(_ notification: Notification) { onClose?() }
}

@MainActor
private final class PlanChoiceButton: NSPopUpButton {
  var taskID: UUID?
}

@MainActor
private final class PlanDatePicker: NSDatePicker {
  var taskID: UUID?
}

@MainActor
private final class ReviewDocumentView: NSView {
  override var isFlipped: Bool { true }
}
