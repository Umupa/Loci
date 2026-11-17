import SwiftUI

/// The menu bar items Loci adds to the system's.
public struct LociCommands: Commands {
  @FocusedValue(\.navigator) private var navigator

  public init() {}

  public var body: some Commands {
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
        navigator?.showStart()
      } label: {
        Text(.loci("menu.newMentor"))
      }
      .keyboardShortcut("n")
      .disabled(navigator == nil)
      Button {
        navigator?.addFile()
      } label: {
        Text(.loci("menu.addFile"))
      }
      .keyboardShortcut("o")
      .disabled(navigator == nil)
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
        navigator?.showStart()
      } label: {
        Text(.loci("sidebar.start"))
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
