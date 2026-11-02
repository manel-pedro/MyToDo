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
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var window: NSWindow?
  private var store: TaskStore?
  private var dayObserver: NSObjectProtocol?

  func applicationWillFinishLaunching(_ notification: Notification) {
    AppMenu.install()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
      let icon = NSImage(contentsOf: iconURL)
    {
      NSApp.applicationIconImage = icon
    }
    do {
      let store = TaskStore(repository: try LocalTaskRepository())
      self.store = store
      dayObserver = NotificationCenter.default.addObserver(
        forName: .NSCalendarDayChanged, object: nil, queue: .main
      ) { [weak store] _ in
        Task { @MainActor [weak store] in store?.reload() }
      }

      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1_260, height: 680),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.title = "Seven Day Todo"
      window.delegate = self
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

  func applicationDidBecomeActive(_ notification: Notification) { store?.reload() }

  func applicationWillTerminate(_ notification: Notification) {
    if let dayObserver { NotificationCenter.default.removeObserver(dayObserver) }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    (sender.contentViewController as? BoardViewController)?.prepareToClose() ?? true
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let canClose = (window?.contentViewController as? BoardViewController)?.prepareToClose() ?? true
    return canClose ? .terminateNow : .terminateCancel
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
