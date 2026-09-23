import AppKit

@MainActor
final class BoardViewController: NSViewController {
    private let store: TaskStore
    private let board = NSStackView()

    init(store: TaskStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
        store.onChange = { [weak self] in self?.renderDays() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        let title = NSTextField(labelWithString: "Seven Day Todo")
        title.font = .systemFont(ofSize: 28, weight: .bold)
        let subtitle = NSTextField(labelWithString: "A clear view of the days around today")
        subtitle.textColor = .secondaryLabelColor

        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 3

        board.orientation = .horizontal
        board.alignment = .top
        board.distribution = .fillEqually
        board.spacing = 12

        let root = NSStackView(views: [heading, board])
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            board.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
        renderDays()
    }

    private func renderDays() {
        guard isViewLoaded else { return }
        board.arrangedSubviews.forEach { view in
            board.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for date in store.days {
            let card = DayCardView(date: date, items: store.items(for: date))
            card.onAdd = { [weak self] title in self?.store.add(title: title, to: date) }
            card.onToggle = { [weak self] item in self?.store.toggle(item) }
            card.onDelete = { [weak self] item in self?.store.delete(item) }
            board.addArrangedSubview(card)
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 470).isActive = true
        }
    }
}

@MainActor
private final class DayCardView: NSView, NSTextFieldDelegate {
    var onAdd: ((String) -> Void)?
    var onToggle: ((TodoItem) -> Void)?
    var onDelete: ((TodoItem) -> Void)?

    private let input = NSTextField()
    private let date: Date
    private let items: [TodoItem]
    private var itemByTag: [Int: TodoItem] = [:]

    init(date: Date, items: [TodoItem]) {
        self.date = date
        self.items = items
        super.init(frame: .zero)
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildView() {
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = Calendar.current.isDateInToday(date) ? 2 : 1
        layer?.borderColor = Calendar.current.isDateInToday(date)
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let dayName = NSTextField(labelWithString: Calendar.current.isDateInToday(date)
            ? "TODAY"
            : date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
        dayName.font = .systemFont(ofSize: 11, weight: .bold)
        dayName.textColor = Calendar.current.isDateInToday(date) ? .controlAccentColor : .secondaryLabelColor

        let dayNumber = NSTextField(labelWithString: date.formatted(.dateTime.day().month(.abbreviated)))
        dayNumber.font = .systemFont(ofSize: 20, weight: .bold)

        let tasks = NSStackView()
        tasks.orientation = .vertical
        tasks.alignment = .leading
        tasks.spacing = 7
        if items.isEmpty {
            let empty = NSTextField(labelWithString: "Nothing planned")
            empty.textColor = .tertiaryLabelColor
            empty.font = .systemFont(ofSize: 11)
            tasks.addArrangedSubview(empty)
        } else {
            items.enumerated().forEach { index, item in
                itemByTag[index + 1] = item
                tasks.addArrangedSubview(taskRow(for: item, tag: index + 1))
            }
        }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = tasks
        tasks.translatesAutoresizingMaskIntoConstraints = false
        tasks.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        input.placeholderString = "Add a task"
        input.delegate = self
        input.target = self
        input.action = #selector(submitTask)

        let stack = NSStackView(views: [dayName, dayNumber, separator(), scroll, input])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            input.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func taskRow(for item: TodoItem, tag: Int) -> NSView {
        let check = NSButton(checkboxWithTitle: item.title, target: nil, action: nil)
        check.state = item.isCompleted ? .on : .off
        check.font = .systemFont(ofSize: 12)
        check.target = self
        check.action = #selector(toggleTask(_:))
        check.tag = tag

        let delete = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")!, target: self, action: #selector(deleteTask(_:)))
        delete.isBordered = false
        delete.contentTintColor = .tertiaryLabelColor
        delete.tag = tag

        let row = NSStackView(views: [check, delete])
        row.orientation = .horizontal
        row.distribution = .fill
        row.spacing = 4
        row.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        return row
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    @objc private func submitTask() {
        let title = input.stringValue
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        input.stringValue = ""
        onAdd?(title)
    }

    @objc private func toggleTask(_ sender: NSButton) {
        guard let item = itemByTag[sender.tag] else { return }
        onToggle?(item)
    }

    @objc private func deleteTask(_ sender: NSButton) {
        guard let item = itemByTag[sender.tag] else { return }
        onDelete?(item)
    }
}
