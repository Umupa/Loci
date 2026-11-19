import AppKit
import LociModel
import SwiftUI

/// What the menu bar can do to the browser in front: a `nil` action is not available now.
struct BrowserCommands {
  let newTab: () -> Void
  /// `nil` with a single tab, so ⌘W closes the window.
  let closeTab: (() -> Void)?
  let openLocation: () -> Void
  let reload: (() -> Void)?
}

extension FocusedValues {
  @Entry var browserCommands: BrowserCommands?
}

extension BrowserSession {
  func handle(_ event: NSEvent, closeWindow: () -> Void) -> Bool {
    guard KeyMonitor.modifiers(of: event) == .command else { return false }
    switch event.charactersIgnoringModifiers?.lowercased() {
    case "w":
      if tabs.count > 1 {
        close(current)
      } else {
        closeWindow()
      }
    case "r" where !current.atStart:
      current.reload()
    default:
      return false
    }
    return true
  }
}

extension EnvironmentValues {
  /// This Mac's other browsers, whichever Mac the window shows.
  @Entry var signIns: (any BrowserSignIns)?
}
