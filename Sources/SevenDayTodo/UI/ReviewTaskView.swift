import AppKit

/// Reuses the standard task row and owns only the planning controls for one task.
@MainActor
final class ReviewTaskView: NSView {
  var onChange: ((ReviewPlan.Selection) -> Void)?
  private let choiceMenu = NSPopUpButton()
  private let picker = AppUI.datePicker()

  init(item: TodoItem, selection: ReviewPlan.Selection, today: Date, actions: TaskActions) {
    super.init(frame: .zero)
    let taskRow = TaskRowView(item: item)
    actions.configure(taskRow, for: item)
    choiceMenu.addItems(withTitles: ReviewPlan.Choice.allCases.map(\.title))
    choiceMenu.selectItem(at: selection.choice.rawValue)
    choiceMenu.target = self
    choiceMenu.action = #selector(changeSelection)
    choiceMenu.setAccessibilityLabel("Next step for \(item.title)")
    picker.minDate = Calendar.current.startOfDay(for: today)
    picker.dateValue = max(picker.minDate ?? today, selection.date)
    picker.isHidden = selection.choice != .date
    picker.target = self
    picker.action = #selector(changeSelection)
    picker.setAccessibilityLabel("New date for \(item.title)")
    let controls = AppUI.stack([choiceMenu, picker], spacing: 4)
    let planning = AppUI.stack(
      [
        AppUI.label("Next step", size: 11, color: .secondaryLabelColor), AppUI.spacer(), controls,
      ], axis: .horizontal, alignment: .top)
    let stack = AppUI.stack([taskRow, planning], spacing: 6)
    AppUI.pin(stack, in: self)
    NSLayoutConstraint.activate([
      taskRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
      planning.widthAnchor.constraint(equalTo: stack.widthAnchor),
      controls.widthAnchor.constraint(equalToConstant: 170),
      choiceMenu.widthAnchor.constraint(equalTo: controls.widthAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @objc private func changeSelection() {
    guard let choice = ReviewPlan.Choice(rawValue: choiceMenu.indexOfSelectedItem) else { return }
    picker.isHidden = choice != .date
    onChange?(ReviewPlan.Selection(choice: choice, date: picker.dateValue))
  }
}
