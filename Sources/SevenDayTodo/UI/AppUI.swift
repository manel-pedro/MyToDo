import AppKit

/// Small, shared AppKit building blocks used by the board and both popovers.
@MainActor
enum AppUI {
  static func stack(
    _ views: [NSView] = [], axis: NSUserInterfaceLayoutOrientation = .vertical,
    spacing: CGFloat = 8, alignment: NSLayoutConstraint.Attribute = .leading
  ) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = axis
    stack.spacing = spacing
    stack.alignment = alignment
    return stack
  }

  static func spacer() -> NSView {
    let view = NSView()
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return view
  }

  static func label(
    _ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular,
    color: NSColor = .labelColor
  ) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    return label
  }

  static func separator() -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    return box
  }

  static func symbol(_ name: String) -> NSImageView {
    let image = NSImageView()
    image.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    image.contentTintColor = .secondaryLabelColor
    image.imageScaling = .scaleProportionallyDown
    image.widthAnchor.constraint(equalToConstant: 16).isActive = true
    image.heightAnchor.constraint(equalToConstant: 20).isActive = true
    return image
  }

  static func propertyRow(symbol name: String, label text: String, control: NSView) -> NSStackView {
    let caption = label(text, color: .secondaryLabelColor)
    caption.widthAnchor.constraint(equalToConstant: 54).isActive = true
    let row = stack(
      [symbol(name), caption, control, spacer()], axis: .horizontal,
      spacing: 10, alignment: .centerY)
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
    return row
  }

  static func datePicker() -> NSDatePicker {
    let picker = NSDatePicker()
    picker.datePickerStyle = .textFieldAndStepper
    picker.datePickerElements = [.yearMonthDay]
    return picker
  }

  static func pin(
    _ child: NSView, in parent: NSView, horizontal: CGFloat = 0, vertical: CGFloat = 0
  ) {
    child.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(child)
    NSLayoutConstraint.activate([
      child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: horizontal),
      child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -horizontal),
      child.topAnchor.constraint(equalTo: parent.topAnchor, constant: vertical),
      child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -vertical),
    ])
  }
}

extension NSStackView {
  func removeAllArrangedSubviews() {
    for view in arrangedSubviews {
      removeArrangedSubview(view)
      view.removeFromSuperview()
    }
  }
}

/// A top-aligned, width-tracking list. The same scrolling/layout rules apply everywhere.
@MainActor
final class StackScrollView: NSScrollView {
  let stack: NSStackView

  init(spacing: CGFloat = 8, fillsAvailableHeight: Bool = false) {
    stack = AppUI.stack(spacing: spacing)
    super.init(frame: .zero)
    drawsBackground = false
    hasVerticalScroller = true
    autohidesScrollers = true
    let document = FlippedView()
    document.translatesAutoresizingMaskIntoConstraints = false
    documentView = document
    AppUI.pin(stack, in: document)
    document.widthAnchor.constraint(equalTo: contentView.widthAnchor).isActive = true
    if fillsAvailableHeight {
      document.heightAnchor.constraint(greaterThanOrEqualTo: contentView.heightAnchor).isActive = true
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
private final class FlippedView: NSView {
  override var isFlipped: Bool { true }
}
