import Foundation
import LociModel
import SwiftUI

/// What the sidebar has selected.
enum Place: Codable, Hashable {
  /// The main conversation with Loci.
  case talk
  /// Loci's own page: its face, Soul, memory and diary.
  case loci
  /// `nil` is every kind.
  case library(ItemKind?)
  /// The built-in browser, for finding things to add.
  case browser
  case settings(SettingsSection)
}

/// The sections of settings in the sidebar.
enum SettingsSection: String, Codable, Hashable, CaseIterable {
  case general, agents, media, remote
}

/// A page opened on top of a place.
enum Page: Codable, Hashable {
  case item(EntityID)
  case passage(Locator)

  var itemID: EntityID {
    switch self {
    case .item(let item), .passage(.item(let item, _)): item
    }
  }

  var locator: Locator? {
    if case .passage(let locator) = self { return locator }
    return nil
  }
}

/// Where a window is, as text the system can keep across launches.
struct WindowState: Codable, Equatable {
  var place: Place = .talk
  var pages: [Page] = []

  init(place: Place = .talk, pages: [Page] = []) {
    self.place = place
    self.pages = pages
  }

  init(restoring text: String) {
    self = (try? JSONDecoder().decode(WindowState.self, from: Data(text.utf8))) ?? WindowState()
  }

  var text: String {
    let remembered = WindowState(place: place, pages: pages.map { .item($0.itemID) })
    return (try? String(decoding: JSONEncoder().encode(remembered), as: UTF8.self)) ?? ""
  }

  /// Goes back to the main conversation when the window points at an item that no longer exists, so a
  /// remembered place never opens onto a blank page.
  func keeping(items: Set<EntityID>) -> WindowState {
    let pagesExist = pages.allSatisfy { items.contains($0.itemID) }
    return pagesExist ? self : WindowState()
  }

  /// Where choosing Loci at the top of the sidebar goes: from the main conversation to Loci's page, and
  /// from anywhere else back to the main conversation.
  func choosingLoci() -> WindowState {
    WindowState(place: place == .talk && pages.isEmpty ? .loci : .talk)
  }
}

/// What the menu bar can ask of the frontmost window.
struct Navigator {
  let showTalk: () -> Void
  let showLibrary: () -> Void
  let showSettings: () -> Void
  let toggleSidebar: () -> Void
  /// Picks a file to add; `nil` while the Mac behind the window cannot take changes.
  let addFile: (() -> Void)?
  /// Adds the link on the pasteboard; `nil` on a page that does not take links.
  let pasteLink: (() -> Void)?
}

extension FocusedValues {
  @Entry var navigator: Navigator?
}

/// Where the window was last, kept by Loci itself.
///
/// The system restores window state only when windows are kept on quit, which is off by default
/// ("Close windows when quitting an application"), so `@SceneStorage` loses the place after ⌘Q.
struct WindowMemory {
  let recall: @MainActor () -> WindowState
  let remember: @MainActor (WindowState) -> Void

  /// Kept in the app's preferences, one place per data folder: a convenience of the interface, not part of
  /// the user's data. A folder never opened before has nothing remembered and opens at the main conversation.
  @MainActor static func preferences(_ defaults: UserDefaults, folder: URL) -> WindowMemory {
    stored(defaults, key: key(for: folder))
  }

  /// Kept for another Mac, by its identity, so switching back to it returns to where it was.
  @MainActor static func preferences(_ defaults: UserDefaults, remote machine: some CustomStringConvertible)
    -> WindowMemory
  {
    stored(defaults, key: "lastWindow remote " + machine.description)
  }

  @MainActor private static func stored(_ defaults: UserDefaults, key: String) -> WindowMemory {
    WindowMemory(
      recall: { WindowState(restoring: defaults.string(forKey: key) ?? "") },
      remember: { defaults.set($0.text, forKey: key) })
  }

  static func key(for folder: URL) -> String {
    "lastWindow " + folder.standardizedFileURL.path(percentEncoded: false)
  }
}
