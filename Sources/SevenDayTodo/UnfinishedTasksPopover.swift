import AppKit

@MainActor
final class UnfinishedTasksPopover: AppPopover {
  private let store: TaskStore
  private let actions: TaskActions
  private let list = StackScrollView(spacing: 10)
  private let subtitle = AppUI.label("", color: .secondaryLabelColor)
  private let applyButton = NSButton(title: "Update plan", target: nil, action: nil)
  private let undoButton = NSButton(title: "Undo", target: nil, action: nil)
  private var plan = ReviewPlan()
  private var renderedItems: [TodoItem]?

  init(store: TaskStore, actions: TaskActions) {
    self.store = store
    self.actions = actions
    super.init(size: NSSize(width: 440, height: 500), behavior: .applicationDefined)
    buildView()
    refresh()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func buildView() {
    guard let content = contentViewController?.view else { return }
    undoButton.target = self
    undoButton.action = #selector(undoPlan)
    applyButton.target = self
    applyButton.action = #selector(applyPlan)
    let later = NSButton(title: "Review later", target: self, action: #selector(reviewLater))
    let actions = AppUI.stack(
      [undoButton, AppUI.spacer(), later, applyButton], axis: .horizontal,
      alignment: .centerY)
    let stack = AppUI.stack(
      [
        AppUI.label("Carry forward", size: 20, weight: .semibold), subtitle, list, actions,
      ], spacing: 12)
    AppUI.pin(stack, in: content, horizontal: 18, vertical: 18)
    NSLayoutConstraint.activate([
      subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
      list.widthAnchor.constraint(equalTo: stack.widthAnchor),
      list.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
      actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
  }

  func refresh() {
    let items = store.unfinishedItems
    undoButton.isHidden = !store.canUndoReview
    // Preserve focus, scroll position and date edits when unrelated store data changes.
    guard renderedItems != items else { return }
    renderedItems = items
    plan.retainTasks(Set(items.map(\.id)))
    updateApplyButton()
    let groups = Set(items.map(\.dayKey)).count
    contentSize = NSSize(
      width: 440, height: min(500, max(260, 150 + items.count * 80 + groups * 28)))
    subtitle.stringValue =
      items.isEmpty
      ? "All caught up — no unfinished tasks from earlier days."
      : "\(items.count) unfinished \(items.count == 1 ? "task" : "tasks") · most recent day first"
    list.stack.removeAllArrangedSubviews()
    let today = Date.now
    var previousDay: String?
    for item in items {
      if item.dayKey != previousDay {
        let date = DayKey.date(for: item.dayKey)
        let title =
          date.map { date in
            Calendar.current.isDateInYesterday(date)
              ? "Yesterday · \(date.formatted(.dateTime.day().month(.abbreviated).year()))"
              : date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year())
          } ?? item.dayKey
        list.stack.addArrangedSubview(
          AppUI.label(title, weight: .semibold, color: .secondaryLabelColor))
        previousDay = item.dayKey
      }
      let row = ReviewTaskView(
        item: item,
        selection: plan.selection(for: item.id, today: today), today: today, actions: actions)
      row.onChange = { [weak self] selection in
        self?.plan.set(selection, for: item.id)
        self?.updateApplyButton()
      }
      list.stack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: list.stack.widthAnchor).isActive = true
      let divider = AppUI.separator()
      list.stack.addArrangedSubview(divider)
      divider.widthAnchor.constraint(equalTo: list.stack.widthAnchor).isActive = true
    }
  }

  private func updateApplyButton() { applyButton.isEnabled = plan.hasUpdates }

  @objc private func applyPlan() {
    if store.applyReviewPlan(plan.updates(for: store.unfinishedItems, today: .now)) {
      plan.reset()
      // Reset choices even if a batch didn't change the displayed task identities.
      renderedItems = nil
      refresh()
    }
  }

  @objc private func undoPlan() { store.undoReviewPlan() }
  @objc private func reviewLater() { requestClose() }
}
