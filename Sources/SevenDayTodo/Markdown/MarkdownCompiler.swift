import Foundation

/// Parses one source line into presentation instructions without changing the source text.
@MainActor
enum MarkdownCompiler {
  private static var compiledLines: [String: Line] = [:]
  private static var expressions: [String: NSRegularExpression] = [:]
  enum Block: Equatable {
    case heading(Int)
    case quote
    case unorderedList
    case orderedList(Int)
    case horizontalRule
  }

  enum Inline: Equatable {
    case bold
    case italic
    case boldItalic
    case code
    case strikethrough
    case link
    case image
  }

  struct Span: Equatable {
    let sourceRange: NSRange
    let range: NSRange
    let style: Inline
    let destination: String?
  }

  struct Line: Equatable {
    var block: Block?
    var spans: [Span] = []
    var hiddenRanges: [NSRange] = []
  }

  static func compile(_ source: String) -> Line {
    if let cached = compiledLines[source] { return cached }
    let line = parse(source)
    // Cursor movement revisits the same lines. Bound the cache for long-lived sessions.
    if compiledLines.count >= 512 { compiledLines.removeAll(keepingCapacity: true) }
    compiledLines[source] = line
    return line
  }

  struct Fence {
    let marker: Character
    let length: Int

    @MainActor
    func closes(_ line: String) -> Bool {
      guard let parsed = MarkdownCompiler.fenceParts(line) else { return false }
      return parsed.marker.first == marker && parsed.marker.count >= length
        && parsed.suffix.trimmingCharacters(in: .whitespaces).isEmpty
    }
  }

  static func openingFence(_ line: String) -> Fence? {
    guard let parsed = fenceParts(line), let marker = parsed.marker.first,
      marker != "`" || !parsed.suffix.contains("`")
    else { return nil }
    return Fence(marker: marker, length: parsed.marker.count)
  }

  private static func fenceParts(_ line: String) -> (marker: String, suffix: String)? {
    guard let match = first(#"^ {0,3}(`{3,}|~{3,})(.*)$"#, in: line) else { return nil }
    let source = line as NSString
    return (source.substring(with: match.range(at: 1)), source.substring(with: match.range(at: 2)))
  }

  private static func parse(_ source: String) -> Line {
    let length = (source as NSString).length
    var result = Line()

    if first(#"^ {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$"#, in: source) != nil {
      result.block = .horizontalRule
      return result
    } else if let match = first(#"^ {0,3}(#{1,6})[ \t]+"#, in: source) {
      let marker = match.range(at: 1)
      result.block = .heading(marker.length)
      result.hiddenRanges.append(match.range)
    } else if let match = first(#"^ {0,3}>[ \t]?"#, in: source) {
      result.block = .quote
      result.hiddenRanges.append(match.range)
    } else if let match = first(#"^ {0,3}([-*+]|[0-9]+\.)[ \t]+"#, in: source) {
      let marker = (source as NSString).substring(with: match.range(at: 1))
      if marker.hasSuffix("."), let number = Int(marker.dropLast()) {
        result.block = .orderedList(number)
      } else {
        result.block = .unorderedList
      }
      result.hiddenRanges.append(match.range)
    }

    var protected: [NSRange] = []
    addDelimited(
      #"(?<!\\)`([^`]+)`"#, style: .code, source: source,
      result: &result, protected: &protected, protectsContent: true)
    addDelimited(
      #"(?<!\\)!\[([^\]]*)\]\(([^)]+)\)"#, style: .image, source: source,
      result: &result, protected: &protected, protectsContent: true, destinationGroup: 2)
    addDelimited(
      #"(?<![!\\])\[([^\]]+)\]\(([^)]+)\)"#, style: .link, source: source,
      result: &result, protected: &protected, protectsContent: true, destinationGroup: 2)
    addDelimited(
      #"(?<!\\)\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*"#, style: .boldItalic,
      source: source, result: &result, protected: &protected, protectsContent: true)
    addDelimited(
      #"(?<!\\)___(?=\S)(.+?)(?<=\S)___"#, style: .boldItalic,
      source: source, result: &result, protected: &protected, protectsContent: true)
    addDelimited(
      #"(?<!\\)\*\*(?=\S)(.+?)(?<=\S)\*\*"#, style: .bold, source: source,
      result: &result, protected: &protected)
    addDelimited(
      #"(?<!\\)__(?=\S)(.+?)(?<=\S)__"#, style: .bold, source: source,
      result: &result, protected: &protected)
    addDelimited(
      #"(?<!\\)~~(?=\S)(.+?)(?<=\S)~~"#, style: .strikethrough,
      source: source, result: &result, protected: &protected)
    addDelimited(
      #"(?<![\*\\])\*(?!\*)(?=\S)(.+?)(?<=\S)\*(?!\*)"#, style: .italic,
      source: source, result: &result, protected: &protected)
    addDelimited(
      #"(?<![_\w\\])_(?!_)(?=\S)(.+?)(?<=\S)_(?!_)"#, style: .italic,
      source: source, result: &result, protected: &protected)

    // A backslash escapes punctuation in Markdown. Hide it outside the active line.
    for match in matches(#"\\([\\`*_~\[\]()>#+.!-])"#, in: source) {
      if !protected.contains(where: { intersects($0, match.range) }) {
        result.hiddenRanges.append(NSRange(location: match.range.location, length: 1))
      }
    }

    result.hiddenRanges = result.hiddenRanges.filter {
      $0.location != NSNotFound && $0.length > 0 && NSMaxRange($0) <= length
    }
    return result
  }

  private static func addDelimited(
    _ pattern: String, style: Inline, source: String,
    result: inout Line, protected: inout [NSRange], protectsContent: Bool = false,
    destinationGroup: Int? = nil
  ) {
    for match in matches(pattern, in: source) {
      let content = match.range(at: 1)
      guard content.location != NSNotFound,
        !protected.contains(where: { intersects($0, match.range) })
      else { continue }
      let destination = destinationGroup.map {
        (source as NSString).substring(with: match.range(at: $0))
      }
      result.spans.append(
        Span(
          sourceRange: match.range, range: content, style: style,
          destination: destination))
      let opening = NSRange(
        location: match.range.location,
        length: content.location - match.range.location)
      let closing = NSRange(
        location: NSMaxRange(content),
        length: NSMaxRange(match.range) - NSMaxRange(content))
      if opening.length > 0 { result.hiddenRanges.append(opening) }
      if closing.length > 0 { result.hiddenRanges.append(closing) }
      if protectsContent { protected.append(match.range) }
    }
  }

  private static func first(_ pattern: String, in source: String) -> NSTextCheckingResult? {
    matches(pattern, in: source).first
  }

  private static func matches(_ pattern: String, in source: String) -> [NSTextCheckingResult] {
    let expression: NSRegularExpression
    if let cached = expressions[pattern] {
      expression = cached
    } else {
      guard let compiled = try? NSRegularExpression(pattern: pattern) else { return [] }
      expressions[pattern] = compiled
      expression = compiled
    }
    return expression.matches(
      in: source, range: NSRange(location: 0, length: (source as NSString).length))
  }

  private static func intersects(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
    NSIntersectionRange(lhs, rhs).length > 0
  }
}
