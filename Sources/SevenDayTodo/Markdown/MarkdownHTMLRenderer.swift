import Foundation

/// A read-only rendering of the Basic Syntax elements. The editable Notes text stays untouched.
@MainActor
enum MarkdownHTMLRenderer {
  static func render(_ source: String) -> String {
    var body = ""
    var paragraph: [String] = []
    var list: MarkdownCompiler.Block?
    var insideFence = false
    var insideIndentedCode = false

    func closeParagraph() {
      guard !paragraph.isEmpty else { return }
      body += "<p>"
      for (index, part) in paragraph.enumerated() {
        if index > 0 && !paragraph[index - 1].hasSuffix("<br>") { body += " " }
        body += part
      }
      body += "</p>"
      paragraph.removeAll()
    }

    func closeList() {
      guard let list else { return }
      body += list == .unorderedList ? "</ul>" : "</ol>"
    }

    let lines = source.components(separatedBy: .newlines)
    var index = 0
    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      defer { index += 1 }
      if trimmed.hasPrefix("```") {
        closeParagraph()
        closeList()
        list = nil
        if insideIndentedCode { body += "</code></pre>"; insideIndentedCode = false }
        body += insideFence ? "</code></pre>" : "<pre><code>"
        insideFence.toggle()
        continue
      }
      if insideFence {
        body += escape(line) + "\n"
        continue
      }
      if line.hasPrefix("    ") || line.hasPrefix("\t") {
        closeParagraph()
        closeList()
        list = nil
        if !insideIndentedCode { body += "<pre><code>"; insideIndentedCode = true }
        body += escape(String(line.dropFirst(line.hasPrefix("\t") ? 1 : 4))) + "\n"
        continue
      }
      if insideIndentedCode { body += "</code></pre>"; insideIndentedCode = false }
      if index + 1 < lines.count,
        let level = setextLevel(lines[index + 1]),
        !trimmed.isEmpty,
        MarkdownCompiler.compile(line).block == nil
      {
        closeParagraph()
        closeList()
        list = nil
        body += "<h\(level)>\(inline(line, compiled: MarkdownCompiler.compile(line)))</h\(level)>"
        index += 1
        continue
      }
      let compiled = MarkdownCompiler.compile(line)
      let content = inline(line, compiled: compiled)
      if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        closeParagraph()
        closeList()
        list = nil
        continue
      }
      switch compiled.block {
      case .heading(let level):
        closeParagraph()
        closeList()
        list = nil
        body += "<h\(level)>\(content)</h\(level)>"
      case .quote:
        closeParagraph()
        closeList()
        list = nil
        body += "<blockquote>\(content)</blockquote>"
      case .unorderedList:
        closeParagraph()
        if list != .unorderedList {
          closeList()
          body += "<ul>"
          list = .unorderedList
        }
        body += "<li>\(content)</li>"
      case .orderedList(let number):
        closeParagraph()
        if case .orderedList = list {
          // Continue the list even when source numbers are repeated or out of sequence.
        } else {
          closeList()
          body += "<ol start=\"\(number)\">"
          list = .orderedList(number)
        }
        body += "<li>\(content)</li>"
      case .horizontalRule:
        closeParagraph()
        closeList()
        list = nil
        body += "<hr>"
      case nil:
        closeList()
        list = nil
        let hardBreak = line.hasSuffix("  ")
        paragraph.append(content.trimmingCharacters(in: .whitespaces) + (hardBreak ? "<br>" : ""))
      }
    }
    closeParagraph()
    closeList()
    if insideFence || insideIndentedCode { body += "</code></pre>" }

    return """
      <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: http: file: data:; style-src 'unsafe-inline'">
      <style>
      :root { color-scheme: light dark; font: 13px -apple-system, BlinkMacSystemFont, sans-serif; }
      body { margin: 12px; overflow-wrap: anywhere; line-height: 1.45; }
      h1,h2,h3,h4,h5,h6 { margin: .7em 0 .3em; line-height: 1.2; }
      p { margin: .5em 0; } blockquote { margin: .5em 0; padding-left: 12px; border-left: 3px solid #999; color: #888; }
      ul,ol { padding-left: 24px; margin: .5em 0; } li { margin: .2em 0; }
      code { font-family: ui-monospace, Menlo, monospace; background: #8883; border-radius: 3px; padding: 1px 3px; }
      pre { overflow-x: auto; padding: 8px; background: #8882; border-radius: 4px; }
      pre code { background: none; padding: 0; }
      hr { border: 0; border-top: 1px solid #999; margin: 12px 0; }
      img { display: block; max-width: 100%; max-height: 240px; object-fit: contain; margin: 8px 0; }
      a { color: #438cff; }
      </style></head><body>\(body)</body></html>
      """
  }

  private static func setextLevel(_ line: String) -> Int? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty && trimmed.allSatisfy({ $0 == "=" }) { return 1 }
    if trimmed.count >= 2 && trimmed.allSatisfy({ $0 == "-" }) { return 2 }
    return nil
  }

  private static func inline(_ source: String, compiled: MarkdownCompiler.Line) -> String {
    let ns = source as NSString
    let protected = compiled.spans
      .filter { [.code, .link, .image].contains($0.style) }
      .sorted { $0.sourceRange.location < $1.sourceRange.location }
    var output = ""
    var active: [MarkdownCompiler.Inline] = []
    var offset = 0

    func closeStyles() {
      for style in active.reversed() { output += closeTag(style) }
      active.removeAll()
    }

    while offset < ns.length {
      if let token = protected.first(where: { $0.sourceRange.location == offset }) {
        closeStyles()
        let content = escape(ns.substring(with: token.range))
        switch token.style {
        case .code:
          output += "<code>\(content)</code>"
        case .link:
          if let url = safeURL(token.destination) {
            output += "<a href=\"\(escape(url))\">\(content)</a>"
          } else { output += content }
        case .image:
          if let url = safeURL(token.destination) {
            output += "<img src=\"\(escape(url))\" alt=\"\(content)\">"
          } else { output += content }
        default: break
        }
        offset = NSMaxRange(token.sourceRange)
        continue
      }
      let characterRange = ns.rangeOfComposedCharacterSequence(at: offset)
      if compiled.hiddenRanges.contains(where: { NSIntersectionRange($0, characterRange).length > 0 }) {
        offset = NSMaxRange(characterRange)
        continue
      }
      let styles: [MarkdownCompiler.Inline] = [.bold, .italic, .boldItalic, .strikethrough]
        .filter { style in
          compiled.spans.contains {
            $0.style == style && NSIntersectionRange($0.range, characterRange).length > 0
          }
        }
      if styles != active {
        closeStyles()
        for style in styles { output += openTag(style) }
        active = styles
      }
      output += escape(ns.substring(with: characterRange))
      offset = NSMaxRange(characterRange)
    }
    closeStyles()
    return output
  }

  private static func openTag(_ style: MarkdownCompiler.Inline) -> String {
    switch style {
    case .bold: return "<strong>"
    case .italic: return "<em>"
    case .boldItalic: return "<strong><em>"
    case .strikethrough: return "<s>"
    default: return ""
    }
  }

  private static func closeTag(_ style: MarkdownCompiler.Inline) -> String {
    switch style {
    case .bold: return "</strong>"
    case .italic: return "</em>"
    case .boldItalic: return "</em></strong>"
    case .strikethrough: return "</s>"
    default: return ""
    }
  }

  private static func safeURL(_ destination: String?) -> String? {
    guard let destination = destination?.trimmingCharacters(in: .whitespacesAndNewlines),
      !destination.isEmpty,
      !destination.contains(where: { $0.isWhitespace || $0.isNewline })
    else { return nil }
    if !destination.contains(":") && !destination.hasPrefix("//") { return destination }
    guard let scheme = URL(string: destination)?.scheme?.lowercased(),
      ["http", "https", "mailto"].contains(scheme)
    else { return nil }
    return destination
  }

  private static func escape(_ string: String) -> String {
    string.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
}
