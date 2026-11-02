import AppKit
import Darwin

@MainActor
enum Checks {
  struct Failure: Error, CustomStringConvertible { let description: String }

  static func require(
    _ condition: @autoclosure () throws -> Bool, _ message: String = "Condition failed",
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    if try !condition() { throw Failure(description: "\(file):\(line): \(message)") }
  }

  static func unwrap<T>(
    _ value: @autoclosure () throws -> T?, _ message: String = "Expected a value",
    file: StaticString = #filePath, line: UInt = #line
  ) throws -> T {
    guard let value = try value() else { throw Failure(description: "\(file):\(line): \(message)") }
    return value
  }

  static func expectError<E: Error, T>(
    _ type: E.Type, _ message: String = "Expected an error",
    file: StaticString = #filePath, line: UInt = #line, body: () throws -> T
  ) throws {
    do {
      _ = try body()
    } catch is E { return }
    catch { throw Failure(description: "\(file):\(line): Unexpected error: \(error). \(message)") }
    throw Failure(description: "\(file):\(line): \(message)")
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
    checks += RepositoryTests.checks + TaskStoreTests.checks + PersistenceTests.checks
      + CalendarAndRegressionTests.checks
    if CommandLine.arguments.contains("--ui") {
      checks.append(("Popover lifecycle and nested editing", { try PopoverSelfTest.run() }))
    }
    if let index = CommandLine.arguments.firstIndex(of: "--filter"),
      CommandLine.arguments.indices.contains(index + 1) {
      let pattern = CommandLine.arguments[index + 1]
      checks = checks.filter { $0.0.localizedCaseInsensitiveContains(pattern) }
      guard !checks.isEmpty else {
        fputs("No checks match '\(pattern)'\n", stderr)
        exit(2)
      }
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
