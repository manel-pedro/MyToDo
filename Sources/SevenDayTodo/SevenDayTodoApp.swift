import SwiftUI

@main
struct SevenDayTodoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1_260, height: 680)
        .windowResizability(.contentMinSize)
    }
}

