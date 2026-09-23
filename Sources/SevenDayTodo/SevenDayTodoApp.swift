import AppKit

@main
@MainActor
struct SevenDayTodoApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var store: TaskStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let store = TaskStore(repository: try JSONTaskRepository())
            self.store = store

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_260, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Seven Day Todo"
            window.minSize = NSSize(width: 1_080, height: 560)
            window.center()
            window.contentViewController = BoardViewController(store: store)
            window.makeKeyAndOrderFront(nil)
            self.window = window
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Seven Day Todo couldn’t open its local data"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
