import AppKit

@MainActor
enum SelfTest {
  enum Failure: Error { case assertion(String) }

  static func run() throws {
    try verifyMarkdownCompiler()
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("tasks.json")
    let firstDay = "2026-09-23"
    let secondDay = "2026-09-24"

    // A task-only array from the first version may have no notes field.
    let legacy = TodoItem(title: "Legacy", dayKey: firstDay)
    var legacyJSON =
      try JSONSerialization.jsonObject(with: JSONEncoder.storage.encode([legacy]))
      as! [[String: Any]]
    legacyJSON[0].removeValue(forKey: "notes")
    try JSONSerialization.data(withJSONObject: legacyJSON).write(to: file)
    let repository = try LocalTaskRepository(fileURL: file)
    var tasks = try repository.tasks(dayKeys: [firstDay])
    try require(tasks.count == 1 && tasks[0].notes.isEmpty, "old task array should load")

    // The intermediate object format must return to a task-only array on load.
    let priorObject: [String: Any] = [
      "version": 1,
      "tasks": legacyJSON,
      "obsolete": [["body": "discarded prior entry"]],
    ]
    try JSONSerialization.data(withJSONObject: priorObject).write(to: file)
    let migrated = try LocalTaskRepository(fileURL: file)
    tasks = try migrated.tasks(dayKeys: [firstDay])
    try require(tasks.count == 1 && tasks[0].id == legacy.id, "object format should preserve tasks")
    let currentJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
    try require(currentJSON is [[String: Any]], "storage should now contain only a task array")

    let created = try migrated.create(
      title: "First", notes: "Long note\nSecond paragraph",
      dayKey: firstDay, isCompleted: false)
    try migrated.updateNotes(id: created.id, notes: "Updated note")
    try migrated.toggle(id: created.id)
    let reopened = try LocalTaskRepository(fileURL: file)
    tasks = try reopened.tasks(dayKeys: [firstDay])
    try require(
      tasks.first(where: { $0.id == created.id })?.notes == "Updated note", "notes should persist")
    try require(
      tasks.first(where: { $0.id == created.id })?.isCompleted == true,
      "completion should persist")

    let a = try reopened.create(title: "A", notes: "", dayKey: secondDay, isCompleted: false)
    let b = try reopened.create(title: "B", notes: "", dayKey: secondDay, isCompleted: false)
    try reopened.move(id: created.id, to: secondDay, at: 1)
    try require(
      try reopened.tasks(dayKeys: [secondDay]).map(\.id) == [a.id, created.id, b.id],
      "cross-day drop should insert at destination index")
    try reopened.move(id: b.id, to: secondDay, at: 0)
    try require(
      try reopened.tasks(dayKeys: [secondDay]).map(\.id) == [b.id, a.id, created.id],
      "same-day reorder should be exact")
    try require(
      try reopened.tasks(dayKeys: [secondDay]).map(\.sortOrder) == [0, 1, 2],
      "sort values should normalize after moves")
    try reopened.delete(id: created.id)
    try require(
      try reopened.tasks(dayKeys: [secondDay]).allSatisfy { $0.id != created.id },
      "soft-deleted task should be hidden")

    let today = date(2026, 9, 24)
    let store = TaskStore(repository: reopened)
    store.returnToToday(now: today)
    let original = store.days.map { DayKey.value(for: $0) }
    try require(
      original.count == 7 && original[0] == "2026-09-21" && original[6] == "2026-09-27",
      "default range should center on today")
    store.shiftDays(-1)
    try require(DayKey.value(for: store.days[0]) == "2026-09-20", "previous should shift one day")
    store.shiftDays(1)
    try require(store.days.map { DayKey.value(for: $0) } == original, "next should shift one day")
    store.shiftDays(5)
    store.returnToToday(now: today)
    try require(
      store.days.map { DayKey.value(for: $0) } == original,
      "today should restore default range")

    let distant = "2027-02-12"
    _ = try reopened.create(title: "Outside range", notes: "", dayKey: distant, isCompleted: false)
    try require(
      try reopened.tasks(dayKeys: [distant]).count == 1,
      "arbitrary date should remain stored")
    try require(DayKey.value(for: date(2026, 1, 2)) == "2026-01-02", "day key needs zero padding")
    try require(DayKey.date(for: "2026-02-31") == nil, "invalid day key should not parse")

    let failingStorage = FailingTaskPersistence()
    let isolated = try LocalTaskRepository(storage: failingStorage)
    let stable = try isolated.create(
      title: "Stable", notes: "Original", dayKey: firstDay, isCompleted: false)
    failingStorage.shouldFail = true
    do {
      try isolated.updateNotes(id: stable.id, notes: "Should not persist")
      throw Failure.assertion("failed storage write should throw")
    } catch is FailingTaskPersistence.WriteError {}
    try require(
      try isolated.tasks(dayKeys: [firstDay]).first?.notes == "Original",
      "failed save should leave repository state unchanged")
  }

  private static func verifyMarkdownCompiler() throws {
    let compiled = MarkdownCompiler.compile("# **Title** and [site](https://example.com)")
    try require(compiled.block == .heading(1), "heading syntax should compile")
    try require(compiled.spans.contains { $0.style == .bold }, "bold syntax should compile")
    try require(compiled.spans.contains { $0.style == .link }, "link syntax should compile")
    try require(compiled.hiddenRanges.count >= 5, "compiled delimiters should be hidden")
    let code = MarkdownCompiler.compile("`**literal**` and *italic*")
    try require(
      code.spans.filter { $0.style == .code }.count == 1,
      "inline code should compile")
    try require(
      !code.spans.contains { $0.style == .bold },
      "Markdown inside code should remain literal")
    try require(code.spans.contains { $0.style == .italic }, "italic syntax should compile")
    let list = MarkdownCompiler.compile("3. Item")
    try require(list.block == .orderedList(3), "ordered list should compile")
    let escaped = MarkdownCompiler.compile(#"\*literal*"#)
    try require(
      !escaped.spans.contains { $0.style == .italic },
      "escaped punctuation should stay literal")
    for level in 1...6 {
      let heading = MarkdownCompiler.compile(String(repeating: "#", count: level) + " Heading")
      try require(heading.block == .heading(level), "all six heading levels should compile")
    }
    try require(MarkdownCompiler.compile("> Quote").block == .quote, "blockquote should compile")
    for marker in ["-", "*", "+"] {
      try require(
        MarkdownCompiler.compile("\(marker) Item").block == .unorderedList,
        "all unordered list markers should compile")
    }
    for rule in ["---", "***", "___", "- - -"] {
      try require(
        MarkdownCompiler.compile(rule).block == .horizontalRule,
        "horizontal rule should not become a list")
    }
    let image = MarkdownCompiler.compile("![kitten](https://example.com/cat.png)")
    try require(image.spans.count == 1 && image.spans[0].style == .image,
      "image syntax should not be treated as a link")
    let combined = MarkdownCompiler.compile("***important***")
    try require(combined.spans.contains { $0.style == .boldItalic },
      "combined emphasis should compile")

    let sample = """
      # Heading

      **bold** and *italic* and `code`
      > Quote
      1. First
      2. Second
      - One
      - Two
      ---
      [site](https://example.com)
      ![cat](https://example.com/cat.png)
      """
    let html = MarkdownHTMLRenderer.render(sample)
    for fragment in [
      "<h1>Heading</h1>", "<strong>bold</strong>", "<em>italic</em>",
      "<code>code</code>", "<blockquote>Quote</blockquote>",
      "<ol start=\"1\"><li>First</li><li>Second</li></ol>",
      "<ul><li>One</li><li>Two</li></ul>", "<hr>",
      "<a href=\"https://example.com\">site</a>",
      "<img src=\"https://example.com/cat.png\" alt=\"cat\">",
    ] {
      try require(html.contains(fragment), "rendered preview missing \(fragment)")
    }
    try require(
      MarkdownHTMLRenderer.render("[bad](javascript:evil)").contains("bad</p>"),
      "unsafe link protocols should not become actionable")
    try require(
      MarkdownHTMLRenderer.render("<script>alert(1)</script>").contains("&lt;script&gt;"),
      "raw HTML should be escaped")
    try require(
      MarkdownHTMLRenderer.render("First line  \nSecond line").contains("First line<br>Second line"),
      "two trailing spaces should create a line break")
    try require(
      MarkdownHTMLRenderer.render("Alternate heading\n---").contains("<h2>Alternate heading</h2>"),
      "setext heading should render")
    try require(
      MarkdownHTMLRenderer.render("```\n**literal**\n```").contains("<pre><code>**literal**"),
      "fenced code should remain literal in the rendered preview")
    try require(
      MarkdownHTMLRenderer.render("![local](image.jpg)").contains("<img src=\"image.jpg\""),
      "relative image paths should render from the Notes directory")

    let source = "# Heading\n**strong**\nplain"
    let styled = NSMutableAttributedString(string: source)
    MarkdownLivePreview.style(styled, activeSelection: nil)
    let headingMarker = styled.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    let headingContent = styled.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
    try require((headingMarker?.pointSize ?? 13) < 1, "inactive syntax should be hidden")
    try require((headingContent?.pointSize ?? 0) > 13, "heading should be formatted")

    let strongLine = (source as NSString).range(of: "**strong**").location
    MarkdownLivePreview.style(styled, activeSelection: NSRange(location: strongLine + 3, length: 0))
    let activeMarker = styled.attribute(.font, at: strongLine, effectiveRange: nil) as? NSFont
    let inactiveMarker = styled.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    try require((activeMarker?.pointSize ?? 0) > 10, "cursor line should reveal source syntax")
    try require((inactiveMarker?.pointSize ?? 13) < 1, "other lines should stay compiled")
    try require(styled.string == source, "formatting must preserve saved Markdown text")

    let fencedSource = "```swift\n**literal**\n```"
    let fenced = NSMutableAttributedString(string: fencedSource)
    MarkdownLivePreview.style(fenced, activeSelection: nil)
    let contentLocation = (fencedSource as NSString).range(of: "**literal**").location
    let contentFont = fenced.attribute(.font, at: contentLocation, effectiveRange: nil) as? NSFont
    try require(
      (contentFont?.pointSize ?? 0) > 10,
      "code contents should remain visible and monospaced")
  }

  private static func require(
    _ condition: @autoclosure () throws -> Bool,
    _ description: String
  ) throws {
    guard try condition() else { throw Failure.assertion(description) }
  }

  private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
  }
}

@MainActor
private final class FailingTaskPersistence: TaskPersistence {
  enum WriteError: Error { case rejected }
  var shouldFail = false
  private var items: [TodoItem] = []

  func load() throws -> [TodoItem] { items }
  func save(_ tasks: [TodoItem]) throws {
    if shouldFail { throw WriteError.rejected }
    items = tasks
  }
}

extension JSONEncoder {
  fileprivate static var storage: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}
