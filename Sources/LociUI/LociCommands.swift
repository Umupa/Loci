import SwiftUI

/// The menu bar items Loci adds to the system's.
public struct LociCommands: Commands {
  @FocusedValue(\.navigator) private var navigator

  public init() {}

  public var body: some Commands {
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
    SidebarCommands()
  }
}
