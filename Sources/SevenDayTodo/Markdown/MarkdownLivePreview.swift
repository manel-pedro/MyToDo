import AppKit

/// Keeps the text view's characters as Markdown source and changes only presentation attributes.
@MainActor
final class MarkdownLivePreview: NSObject, NSTextViewDelegate {
  var onChange: (() -> Void)?
  private weak var textView: NSTextView?
  private var editingNotes = false
  private var isRendering = false

  init(textView: NSTextView) {
    self.textView = textView
    super.init()
    textView.delegate = self
  }

  func textDidBeginEditing(_ notification: Notification) {
    editingNotes = true
    render(activeSelection: textView?.selectedRange())
  }

  func textDidEndEditing(_ notification: Notification) {
    editingNotes = false
    render(activeSelection: nil)
  }

  func textDidChange(_ notification: Notification) {
    render(activeSelection: editingNotes ? textView?.selectedRange() : nil)
    onChange?()
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    if let textView, textView.window?.firstResponder === textView {
      editingNotes = true
    }
    render(activeSelection: editingNotes ? textView?.selectedRange() : nil)
  }

  /// Passing `nil` compiles every line. The selected source line stays unformatted.
  func render(activeSelection: NSRange? = nil) {
    guard !isRendering, let textView, let storage = textView.textStorage else { return }
    isRendering = true
    defer { isRendering = false }

    storage.beginEditing()
    Self.style(storage, activeSelection: activeSelection)
    storage.endEditing()
    textView.typingAttributes = Self.baseAttributes
  }

  static func style(_ storage: NSMutableAttributedString, activeSelection: NSRange?) {

    let source = storage.string as NSString
    let whole = NSRange(location: 0, length: source.length)
    let selectedLines = activeSelection.map { selection in
      let safe = NSRange(
        location: min(selection.location, source.length),
        length: min(selection.length, source.length - min(selection.location, source.length)))
      return source.lineRange(for: safe)
    }
    if whole.length > 0 { storage.setAttributes(baseAttributes, range: whole) }

    var location = 0
    var insideFence = false
    while location < source.length {
      var start = 0
      var end = 0
      var contentsEnd = 0
      source.getLineStart(
        &start, end: &end, contentsEnd: &contentsEnd,
        for: NSRange(location: location, length: 0))
      let lineRange = NSRange(location: start, length: contentsEnd - start)
      let paragraphRange = NSRange(location: start, length: end - start)
      let line = source.substring(with: lineRange)
      let active = selectedLines.map { NSIntersectionRange(paragraphRange, $0).length > 0 } ?? false
      let fence = line.trimmingCharacters(in: .whitespaces).hasPrefix("```")

      if !active && lineRange.length > 0 {
        if fence {
          conceal(lineRange, in: storage)
        } else if insideFence {
          storage.addAttributes(
            [
              .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
              .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12),
            ], range: lineRange)
        } else {
          apply(MarkdownCompiler.compile(line), at: start, lineRange: lineRange, in: storage)
        }
      }
      if fence { insideFence.toggle() }
      location = end
    }
  }

  private static var baseAttributes: [NSAttributedString.Key: Any] {
    [
      .font: NSFont.systemFont(ofSize: 13),
      .foregroundColor: NSColor.textColor,
      .paragraphStyle: NSParagraphStyle.default,
    ]
  }

  private static func apply(
    _ compiled: MarkdownCompiler.Line, at offset: Int,
    lineRange: NSRange, in storage: NSMutableAttributedString
  ) {
    if let block = compiled.block {
      switch block {
      case .heading(let level):
        let size = max(15, 26 - CGFloat(level * 2))
        storage.addAttribute(
          .font, value: NSFont.systemFont(ofSize: size, weight: .bold),
          range: lineRange)
      case .quote:
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 18
        paragraph.firstLineHeadIndent = 18
        storage.addAttributes(
          [
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.secondaryLabelColor,
          ], range: lineRange)
      case .unorderedList, .orderedList:
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 24
        paragraph.firstLineHeadIndent = 24
        switch block {
        case .unorderedList:
          paragraph.textLists = [NSTextList(markerFormat: .disc, options: 0)]
        case .orderedList(let number):
          paragraph.textLists = [
            NSTextList(
              markerFormat: .decimal, options: [],
              startingItemNumber: number)
          ]
        default: break
        }
        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
      case .horizontalRule:
        storage.addAttributes(
          [
            .foregroundColor: NSColor.tertiaryLabelColor,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
          ], range: lineRange)
      }
    }

    for span in compiled.spans {
      let range = NSRange(location: offset + span.range.location, length: span.range.length)
      guard range.length > 0 else { continue }
      switch span.style {
      case .bold:
        applyTrait(.boldFontMask, to: range, in: storage)
      case .italic:
        applyTrait(.italicFontMask, to: range, in: storage)
      case .boldItalic:
        applyTrait(.boldFontMask, to: range, in: storage)
        applyTrait(.italicFontMask, to: range, in: storage)
      case .code:
        storage.addAttributes(
          [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12),
          ], range: range)
      case .strikethrough:
        storage.addAttribute(
          .strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
          range: range)
      case .link:
        storage.addAttributes(
          [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
          ], range: range)
        if let destination = span.destination,
          let url = URL(string: destination),
          ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
        {
          storage.addAttribute(.link, value: url, range: range)
        }
      case .image:
        storage.addAttributes(
          [
            .foregroundColor: NSColor.secondaryLabelColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
          ], range: range)
      }
    }

    for hidden in compiled.hiddenRanges {
      conceal(NSRange(location: offset + hidden.location, length: hidden.length), in: storage)
    }
  }

  private static func applyTrait(
    _ trait: NSFontTraitMask, to range: NSRange,
    in storage: NSMutableAttributedString
  ) {
    var runs: [(NSRange, NSFont)] = []
    storage.enumerateAttribute(.font, in: range) { value, run, _ in
      if let font = value as? NSFont { runs.append((run, font)) }
    }
    for (run, font) in runs {
      storage.addAttribute(
        .font, value: NSFontManager.shared.convert(font, toHaveTrait: trait),
        range: run)
    }
  }

  private static func conceal(_ range: NSRange, in storage: NSMutableAttributedString) {
    guard range.length > 0 else { return }
    storage.addAttributes(
      [
        .font: NSFont.systemFont(ofSize: 0.1),
        .foregroundColor: NSColor.clear,
      ], range: range)
  }
}
