import AppKit
import Darwin

@MainActor
enum Checks {
  struct Failure: Error, CustomStringConvertible { let description: String }

  static func require(
    _ condition: @autoclosure () -> Bool, _ message: String = "Condition failed",
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    if !condition() { throw Failure(description: "\(file):\(line): \(message)") }
  }
}

@main
@MainActor
enum AppChecks {
  static func main() {
    let model = ModelTests()
    var checks: [(String, () throws -> Void)] = [
      ("Existing storage, review, calendar and Markdown regressions", { try SelfTest.run() }),
      ("ShortMonthNavigation", { try model.testShortMonthNavigation() }),
      ("GridAndDST", { try model.testGridAndDST() }),
      ("ReviewSelections", { try model.testReviewSelections() }),
      ("FailedDraftSave", { try model.testFailedDraftSave() }),
      ("NoOpWrites", { try model.testNoOpWrites() }),
      ("InvalidBatch", { try model.testInvalidBatch() }),
      ("DuplicateStoredIDs", { try model.testDuplicateStoredIDs() }),
      ("FractionalReviewUndo", { try model.testFractionalReviewUndo() }),
      ("MalformedStorageIsPreserved", { try model.testMalformedStorageIsPreserved() }),
      (
        "ReviewUndoCanRetryAfterWriteFailure",
        { try model.testReviewUndoCanRetryAfterWriteFailure() }
      ),
      ("MarkdownFenceDelimiters", { try model.testMarkdownFenceDelimiters() }),

    ]
    if CommandLine.arguments.contains("--ui") {
      checks.append(("Popover lifecycle and nested editing", { try PopoverSelfTest.run() }))
    }
    var failures = 0
    for (name, check) in checks {
      do {
        try check()
        print("PASS \(name)")
      } catch {
        failures += 1
        fputs("FAIL \(name): \(error)\n", stderr)
      }
    }
    print("\(checks.count - failures)/\(checks.count) checks passed")
    exit(failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
  }
}
