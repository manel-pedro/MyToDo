import Foundation
import Observation

@MainActor
@Observable
final class TaskStore {
    private let repository: any TaskRepository
    private(set) var items: [TodoItem] = []
    private(set) var days: [Date] = []
    var errorMessage: String?

    init(repository: any TaskRepository) {
        self.repository = repository
        refreshDays()
        reload()
    }

    func refreshDays(now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        days = (-3...3).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    func items(for date: Date) -> [TodoItem] {
        let key = DayKey.value(for: date)
        return items.filter { $0.dayKey == key }
    }

    func add(title: String, to date: Date) {
        perform { try repository.add(title: title, dayKey: DayKey.value(for: date)) }
    }

    func toggle(_ item: TodoItem) { perform { try repository.toggle(item) } }
    func delete(_ item: TodoItem) { perform { try repository.delete(item) } }

    func move(itemID: UUID, to date: Date) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        perform { try repository.move(item, to: DayKey.value(for: date)) }
    }

    func reload() {
        do {
            items = try repository.tasks(dayKeys: days.map { DayKey.value(for: $0) })
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
