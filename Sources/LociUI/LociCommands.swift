import SwiftUI

/// The menu bar items Loci adds to the system's.
public struct LociCommands: Commands {
  @Environment(\.openWindow) private var openWindow
  @FocusedValue(\.navigator) private var navigator
  @FocusedValue(\.browserCommands) private var browser

  public init() {}

  public var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button {
        openWindow(id: AppUpdateWindow.id)
      } label: {
        Text(.loci("update.menu"))
      }
    }
    CommandGroup(replacing: .appSettings) {
      Button {
        navigator?.showSettings()
      } label: {
        Text(.loci("menu.settings"))
      }
      .keyboardShortcut(",")
      .disabled(navigator == nil)
    }
    CommandGroup(replacing: .newItem) {
      Button {
        navigator?.addFile?()
      } label: {
        Text(.loci("menu.addFile"))
      }
      .keyboardShortcut("o")
      .disabled(navigator?.addFile == nil)
      if let browser {
        Button(action: browser.newTab) { Text(.loci("browser.newTab")) }
          .keyboardShortcut("t")
        Button(action: browser.openLocation) { Text(.loci("menu.openLocation")) }
          .keyboardShortcut("l")
        if let closeTab = browser.closeTab {
          Button(action: closeTab) { Text(.loci("browser.closeTab")) }
            .keyboardShortcut("w")
        }
      }
    }
    CommandGroup(after: .pasteboard) {
      Button {
        navigator?.pasteLink?()
      } label: {
        Text(.loci("menu.pasteLink"))
      }
      .disabled(navigator?.pasteLink == nil)
    }
    CommandGroup(before: .sidebar) {
      if let reload = browser?.reload {
        Button(action: reload) { Text(.loci("browser.reload")) }
          .keyboardShortcut("r")
      }
    }
    CommandGroup(replacing: .sidebar) {
      Button {
        navigator?.toggleSidebar()
      } label: {
        Text(.loci("menu.toggleSidebar"))
      }
      .keyboardShortcut("s", modifiers: [.control, .command])
      .disabled(navigator == nil)
    }
    CommandMenu(Text(.loci("menu.go"))) {
      Button {
        navigator?.showTalk()
      } label: {
        Text(.loci("companion.title"))
      }
      .keyboardShortcut("1")
      .disabled(navigator == nil)
      Button {
        navigator?.showLibrary()
      } label: {
        Text(.loci("sidebar.library"))
      }
      .keyboardShortcut("2")
      .disabled(navigator == nil)
    }
  }
}
