import SwiftUI
import SwiftData

@main
struct SevenDayTodoApp: App {
    private let container: ModelContainer
    @State private var store: TaskStore

    init() {
        do {
            let container = try ModelContainer(for: TodoItem.self)
            self.container = container
            let repository = SwiftDataTaskRepository(context: container.mainContext)
            _store = State(initialValue: TaskStore(repository: repository))
        } catch {
            fatalError("Unable to create task database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .modelContainer(container)
        }
        .defaultSize(width: 1_260, height: 680)
        .windowResizability(.contentMinSize)
    }
}
