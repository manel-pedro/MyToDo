import AppKit

@MainActor
final class BoardViewController: NSViewController {
  private let store: TaskStore
  private let board = NSStackView()
  private let rangeLabel = NSTextField(labelWithString: "")
  private let viewMode = NSSegmentedControl(
    labels: ["Default", "Month"], trackingMode: .selectOne, target: nil, action: nil)
  private let previous = NSButton(title: "‹", target: nil, action: nil)
  private let next = NSButton(title: "›", target: nil, action: nil)
  private let unfinishedButton = NSButton(title: "Unfinished tasks", target: nil, action: nil)
  private let popovers: TaskPopoverCoordinator
  private var showedStartupReview = false
  var editor: TaskEditorPopover? { popovers.editor }
  var unfinishedPopover: UnfinishedTasksPopover? { popovers.review }
  private var needsRenderAfterEditing = false
  private var shownError: String?

  init(store: TaskStore) {
    self.store = store
    popovers = TaskPopoverCoordinator(store: store)
    super.init(nibName: nil, bundle: nil)
    store.onChange = { [weak self] in self?.renderDays() }
    popovers.onEditorClosed = { [weak self] in
      guard let self else { return }
      if self.needsRenderAfterEditing { self.renderDays() }
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func loadView() {
    view = NSView()
    view.wantsLayer = true

    let title = NSTextField(labelWithString: "Seven Day Todo")
    title.font = .systemFont(ofSize: 28, weight: .bold)
    rangeLabel.textColor = .secondaryLabelColor
    rangeLabel.font = .systemFont(ofSize: 12)

    unfinishedButton.target = self
    unfinishedButton.action = #selector(toggleUnfinishedTasks)
    unfinishedButton.toolTip = "Review and reschedule unfinished tasks from earlier days"
    previous.target = self
    previous.action = #selector(previousDay)
    next.target = self
    next.action = #selector(nextDay)
    viewMode.target = self
    viewMode.action = #selector(changeViewMode)
    viewMode.selectedSegment = 0
    viewMode.setAccessibilityLabel("Calendar view")
    let today = NSButton(title: "Today", target: self, action: #selector(returnToToday))
    let spacer = AppUI.spacer()
    let header = AppUI.stack(
      [title, unfinishedButton, spacer, viewMode, rangeLabel, previous, today, next],
      axis: .horizontal, alignment: .centerY)

    board.orientation = .horizontal
    board.alignment = .top
    board.distribution = .fillEqually
    board.spacing = 12

    let root = AppUI.stack([header, board], spacing: 20)
    AppUI.pin(root, in: view, horizontal: 24, vertical: 24)
    NSLayoutConstraint.activate([
      header.widthAnchor.constraint(equalTo: root.widthAnchor),
      board.widthAnchor.constraint(equalTo: root.widthAnchor),
    ])
    renderDays()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    guard !showedStartupReview else { return }
    showedStartupReview = true
    DispatchQueue.main.async { [weak self] in
      guard let self, self.view.window != nil else { return }
      self.store.reload()
      if !self.store.unfinishedItems.isEmpty {
        self.popovers.showReview(near: self.unfinishedButton)
      }
    }
  }

  @objc private func toggleUnfinishedTasks() {
    popovers.toggleReview(near: unfinishedButton)
  }

  /// Window close and app termination must use the same validated save path.
  func prepareToClose() -> Bool { popovers.closeAll() }

  override func viewWillDisappear() {
    popovers.closeAll()
    super.viewWillDisappear()
  }

  private func renderDays() {
    guard isViewLoaded else { return }
    if let error = store.errorMessage {
      if error != shownError {
        shownError = error
        let alert = NSAlert()
        alert.messageText = "Seven Day Todo couldn't complete this action"
        alert.informativeText = error
        alert.runModal()
      }
      return
    }
    shownError = nil
    unfinishedButton.title = "Unfinished tasks (\(store.unfinishedItems.count))"
    popovers.refreshReview()
    // Saving from a close request must not remove the positioning view.
    guard editor == nil else {
      needsRenderAfterEditing = true
      return
    }
    needsRenderAfterEditing = false
    board.removeAllArrangedSubviews()
    let isMonth = store.viewMode == .month
    viewMode.selectedSegment = isMonth ? 1 : 0
    previous.toolTip = isMonth ? "Previous month" : "Previous day"
    next.toolTip = isMonth ? "Next month" : "Next day"
    board.orientation = isMonth ? .vertical : .horizontal
    board.distribution = isMonth ? .fill : .fillEqually
    board.alignment = isMonth ? .leading : .top
    board.spacing = isMonth ? 6 : 12
    if isMonth {
      rangeLabel.stringValue = store.focusedDate.formatted(.dateTime.month(.wide).year())
      let headings = NSStackView()
      headings.distribution = .fillEqually
      headings.spacing = 6
      for date in store.days.prefix(7) {
        let label = NSTextField(labelWithString: date.formatted(.dateTime.weekday(.abbreviated)))
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        headings.addArrangedSubview(label)
      }
      board.addArrangedSubview(headings)
      headings.widthAnchor.constraint(equalTo: board.widthAnchor).isActive = true
      headings.heightAnchor.constraint(equalToConstant: 18).isActive = true
      var firstWeek: NSStackView?
      for offset in stride(from: 0, to: store.days.count, by: 7) {
        let week = NSStackView()
        week.distribution = .fillEqually
        week.alignment = .top
        week.spacing = 6
        board.addArrangedSubview(week)
        week.widthAnchor.constraint(equalTo: board.widthAnchor).isActive = true
        week.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        if let firstWeek {
          week.heightAnchor.constraint(equalTo: firstWeek.heightAnchor).isActive = true
        } else {
          firstWeek = week
        }
        for date in store.days[offset..<(offset + 7)] {
          let card = makeCard(for: date, compact: true)
          week.addArrangedSubview(card)
          card.heightAnchor.constraint(equalTo: week.heightAnchor).isActive = true
        }
      }
    } else {
      if let first = store.days.first, let last = store.days.last {
        rangeLabel.stringValue =
          "\(first.formatted(.dateTime.day().month(.abbreviated).year())) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
      }
      for date in store.days {
        let card = makeCard(for: date, compact: false)
        board.addArrangedSubview(card)
        card.heightAnchor.constraint(equalTo: board.heightAnchor).isActive = true
      }
    }
  }

  private func makeCard(for date: Date, compact: Bool) -> DayCardView {
    let card = DayCardView(
      date: date, items: store.items(for: date), compact: compact, actions: popovers.actions)
    if compact && !Calendar.current.isDate(date, equalTo: store.focusedDate, toGranularity: .month)
    {
      card.alphaValue = 0.5
    }
    card.onAdd = { [weak self] anchor in
      self?.popovers.openEditor(item: nil, on: date, anchor: anchor)
    }
    card.onDrop = { [weak self] id, index in
      self?.store.move(itemID: id, to: date, at: index) ?? false
    }
    return card
  }

  @objc private func changeViewMode() {
    let requested: TaskStore.ViewMode = viewMode.selectedSegment == 1 ? .month : .days
    guard popovers.closeAll() else {
      viewMode.selectedSegment = store.viewMode == .month ? 1 : 0
      return
    }
    store.setViewMode(requested)
  }

  @objc private func previousDay() { if popovers.closeAll() { store.shiftDays(-1) } }
  @objc private func nextDay() { if popovers.closeAll() { store.shiftDays(1) } }
  @objc private func returnToToday() { if popovers.closeAll() { store.returnToToday() } }
}
