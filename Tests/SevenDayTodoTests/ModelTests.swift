import AppKit

@MainActor
struct ModelTests {
  func testShortMonthNavigation() throws {
    let calendar = calendar()
    let january = date(2027, 1, 31, calendar: calendar)
    var range = BoardCalendar(calendar: calendar, today: january)
    range.setViewMode(.month)
    range.shift(1)
    try Checks.require(DayKey.value(for: range.focusedDate, calendar: calendar) == "2027-02-28")
    range.shift(1)
    try Checks.require(DayKey.value(for: range.focusedDate, calendar: calendar) == "2027-03-31")
    range.shift(-2)
    try Checks.require(range.focusedDate == january)
  }

  func testGridAndDST() throws {
    var calendar = calendar()
    calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
    calendar.firstWeekday = 2
    var range = BoardCalendar(calendar: calendar, today: date(2028, 2, 15, calendar: calendar))
    range.setViewMode(.month)
    try Checks.require(range.days.count.isMultiple(of: 7))
    try Checks.require(calendar.component(.weekday, from: range.days[0]) == 2)
    try Checks.require(range.days.filter { calendar.component(.month, from: $0) == 2 }.count == 29)
    range.returnToToday(date(2027, 3, 28, calendar: calendar))
    range.setViewMode(.days)
    try Checks.require(
      range.days.map { DayKey.value(for: $0, calendar: calendar) } == [
        "2027-03-27", "2027-03-28", "2027-03-29", "2027-03-30",
      ])
  }

  func testReviewSelections() throws {
    let calendar = calendar()
    let today = date(2026, 11, 1, calendar: calendar)
    let item = TodoItem(title: "Review", dayKey: "2026-10-31")
    var plan = ReviewPlan()
    try Checks.require(plan.updates(for: [item], today: today, calendar: calendar).isEmpty)
    plan.set(.init(choice: .date, date: today.addingTimeInterval(-86400)), for: item.id)
    let moved = plan.updates(for: [item], today: today, calendar: calendar)
    try Checks.require(moved.first?.id == item.id && moved.first?.dayKey == "2026-11-01")
    plan.set(.init(choice: .completed, date: today), for: item.id)
    let completed = plan.updates(for: [item], today: today, calendar: calendar)
    try Checks.require(
      completed.first?.isCompleted == true && completed.first?.dayKey == item.dayKey)
    plan.retainTasks([])
    try Checks.require(!plan.hasUpdates)
  }

  func testFailedDraftSave() throws {
    let storage = MemoryStorage()
    let repository = try LocalTaskRepository(storage: storage)
    let store = TaskStore(repository: repository)
    store.beginNewTask(on: .now)
    store.setDraft(title: "Keep me", notes: "**raw**", date: .now, isCompleted: false)
    storage.shouldFail = true
    try Checks.require(!store.saveDraft())
    try Checks.require(store.draft?.title == "Keep me" && store.draft?.notes == "**raw**")
    try Checks.require(storage.items.isEmpty)
    storage.shouldFail = false
    try Checks.require(store.saveDraft())
    try Checks.require(store.draft == nil && storage.items.count == 1)
  }

  func testNoOpWrites() throws {
    let storage = MemoryStorage()
    let repository = try LocalTaskRepository(storage: storage)
    let item = try repository.create(
      title: "Task", notes: "Note", dayKey: "2026-11-01", isCompleted: false)
    let writes = storage.writes
    try repository.update(
      id: item.id, title: "Task", notes: "Note", dayKey: item.dayKey, isCompleted: false)
    try repository.updateNotes(id: item.id, notes: item.notes)
    try repository.move(id: item.id, to: item.dayKey, at: 0)
    try Checks.require(storage.writes == writes)
    try Checks.require(storage.items == [item])
  }

  func testInvalidBatch() throws {
    let storage = MemoryStorage()
    let repository = try LocalTaskRepository(storage: storage)
    let item = try repository.create(
      title: "Task", notes: "", dayKey: "2026-11-01", isCompleted: false)
    try expectTaskError {
      try repository.move(id: item.id, to: "2026-02-31", at: 0)
    }
    try expectTaskError {
      try repository.applyPlan([
        .init(id: item.id, dayKey: "2026-11-02", isCompleted: false),
        .init(id: item.id, dayKey: "2026-11-03", isCompleted: true),
      ])
    }
    try Checks.require(storage.items == [item] && storage.writes == 1)
  }

  func testDuplicateStoredIDs() throws {
    let storage = MemoryStorage()
    let item = TodoItem(title: "Duplicate", dayKey: "2026-11-01")
    storage.items = [item, item]
    try expectTaskError { _ = try LocalTaskRepository(storage: storage) }
    try Checks.require(storage.writes == 0)
  }

  func testFractionalReviewUndo() throws {
    let storage = MemoryStorage()
    let first = TodoItem(title: "First", dayKey: "2026-10-30", sortOrder: 0.5)
    let second = TodoItem(title: "Second", dayKey: "2026-10-30", sortOrder: 1e100)
    storage.items = [first, second]
    let store = TaskStore(
      repository: try LocalTaskRepository(storage: storage),
      now: { self.date(2026, 11, 1, calendar: self.calendar()) })
    try Checks.require(
      store.applyReviewPlan([.init(id: second.id, dayKey: "2026-11-02", isCompleted: false)]))
    store.undoReviewPlan()
    try Checks.require(store.unfinishedItems.map(\.id) == [first.id, second.id])
  }

  func testMalformedStorageIsPreserved() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("tasks.json")
    let malformed = Data("[{\"title\":\"Missing required fields\"}]".utf8)
    try malformed.write(to: file)
    let storage = try JSONFileTaskStorage(fileURL: file)
    do {
      _ = try storage.load()
      throw Checks.Failure(description: "Malformed task array should fail")
    } catch DecodingError.keyNotFound(let key, _) {
      try Checks.require(
        key.stringValue == "id", "Original field-level decoding error should survive")
    }
    let after = try Data(contentsOf: file)
    try Checks.require(after == malformed, "Bad data must not be rewritten")
  }

  func testReviewUndoCanRetryAfterWriteFailure() throws {
    let storage = MemoryStorage()
    let item = TodoItem(title: "Review", dayKey: "2026-10-31")
    storage.items = [item]
    let store = TaskStore(
      repository: try LocalTaskRepository(storage: storage),
      now: { self.date(2026, 11, 1, calendar: self.calendar()) })
    try Checks.require(
      store.applyReviewPlan([.init(id: item.id, dayKey: "2026-11-02", isCompleted: false)]))
    storage.shouldFail = true
    store.undoReviewPlan()
    try Checks.require(store.canUndoReview && storage.items[0].dayKey == "2026-11-02")
    storage.shouldFail = false
    store.undoReviewPlan()
    try Checks.require(!store.canUndoReview && storage.items[0].dayKey == item.dayKey)
  }

  func testMarkdownFenceDelimiters() throws {
    let source = "````swift\n```\n**literal**\n````\n**bold**"
    let styled = NSMutableAttributedString(string: source)
    MarkdownLivePreview.style(styled, activeSelection: nil)
    let literal = (source as NSString).range(of: "**literal**").location
    let font = styled.attribute(.font, at: literal, effectiveRange: nil) as? NSFont
    try Checks.require(
      (font?.pointSize ?? 0) > 10, "Short backtick runs must not close a longer fence")
    let bold = (source as NSString).range(of: "**bold**").location
    let marker = styled.attribute(.font, at: bold, effectiveRange: nil) as? NSFont
    try Checks.require((marker?.pointSize ?? 13) < 1, "Formatting resumes after the matching fence")
    let tildes = NSMutableAttributedString(string: "~~~\n**literal**\n~~~")
    MarkdownLivePreview.style(tildes, activeSelection: nil)
    let tildeFont = tildes.attribute(.font, at: 4, effectiveRange: nil) as? NSFont
    try Checks.require(
      (tildeFont?.pointSize ?? 0) > 10, "Tilde fences should also preserve literal code")
    try Checks.require(styled.string == source, "Fence rendering must preserve saved Markdown")
  }

  private func expectTaskError(_ body: () throws -> Void) throws {
    do {
      try body()
      throw Checks.Failure(description: "Expected TaskError")
    } catch is TaskError {}
  }

  private func calendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
  }
}

@MainActor
final class MemoryStorage: TaskPersistence {
  enum Failure: Error { case write }
  var items: [TodoItem] = []
  var shouldFail = false
  private(set) var writes = 0
  func load() throws -> [TodoItem] { items }
  func save(_ tasks: [TodoItem]) throws {
    if shouldFail { throw Failure.write }
    writes += 1
    items = tasks
  }
}
