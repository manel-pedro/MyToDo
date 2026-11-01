import AppKit
import Darwin

@main
@MainActor
struct SevenDayTodoApp {
  static func main() {
    if CommandLine.arguments.contains("--ui-self-test") {
      do {
        try PopoverSelfTest.run()
        print("Popover UI self-test passed")
        exit(EXIT_SUCCESS)
      } catch {
        fputs("Popover UI self-test failed: \(error)\n", stderr)
        exit(EXIT_FAILURE)
      }
    }
    if CommandLine.arguments.contains("--self-test") {
      do {
        try SelfTest.run()
        print("Self-test passed")
        exit(EXIT_SUCCESS)
      } catch {
        fputs("Self-test failed: \(error)\n", stderr)
        exit(EXIT_FAILURE)
      }
    }

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

  func applicationWillFinishLaunching(_ notification: Notification) {
    let mainMenu = NSMenu()

    func addMenu(_ title: String) -> NSMenu {
      let item = NSMenuItem()
      let menu = NSMenu(title: title)
      item.submenu = menu
      mainMenu.addItem(item)
      return menu
    }

    let appMenu = addMenu("Seven Day Todo")
    appMenu.addItem(withTitle: "About Seven Day Todo", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    let servicesMenu = NSMenu(title: "Services")
    let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
    servicesItem.submenu = servicesMenu
    appMenu.addItem(servicesItem)
    NSApp.servicesMenu = servicesMenu
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide Seven Day Todo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit Seven Day Todo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    let fileMenu = addMenu("File")
    fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

    let editMenu = addMenu("Edit")
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    let windowMenu = addMenu("Window")
    windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    let fullScreen = windowMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
    fullScreen.keyEquivalentModifierMask = [.command, .control]
    windowMenu.addItem(.separator())
    windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
    NSApp.windowsMenu = windowMenu
    NSApp.mainMenu = mainMenu
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let store = TaskStore(repository: try LocalTaskRepository())
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
