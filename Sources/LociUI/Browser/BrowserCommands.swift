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

extension EnvironmentValues {
  /// This Mac's other browsers, whichever Mac the window shows.
  @Entry var signIns: (any BrowserSignIns)?
}
