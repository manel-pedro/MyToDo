import Foundation

@MainActor
enum SelfTest {
    enum Failure: Error {
        case assertion(String)
    }

    static func run() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("tasks.json")
        let day = "2026-09-23"

        let repository = try JSONTaskRepository(fileURL: file)
        try repository.add(title: "Test task", dayKey: day)
        var tasks = try repository.tasks(dayKeys: [day])
        try require(tasks.count == 1, "add should create one task")
        try require(tasks[0].title == "Test task", "title should round-trip")
        try require(tasks[0].syncState == "pending", "new task should await sync")

        try repository.toggle(id: tasks[0].id)
        tasks = try repository.tasks(dayKeys: [day])
        try require(tasks[0].isCompleted, "toggle should complete task")

        let reloaded = try JSONTaskRepository(fileURL: file)
        let persisted = try reloaded.tasks(dayKeys: [day])
        try require(persisted.first?.isCompleted == true, "completion should persist")

        try reloaded.delete(id: tasks[0].id)
        try require(try reloaded.tasks(dayKeys: [day]).isEmpty, "deleted task should be hidden")
        try require(DayKey.value(for: date(2026, 1, 2)) == "2026-01-02", "day key should be stable")
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure.assertion(message) }
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
