import Foundation
import LociModel
import SwiftUI

/// What the sidebar has selected.
enum Place: Codable, Hashable {
  /// The main conversation with Loci.
  case talk
  /// Loci's own page: its face, Soul, memory and diary.
  case loci
  /// Loci's own page open at its connectors, with this one lit, as a reply asked.
  case connector(ConnectorID)
  /// `nil` is every kind.
  case library(LibraryCategory?)
  /// The built-in browser, for finding things to add.
  case browser
  /// The courses Loci writes: the gallery, or the course being read.
  case courses(EntityID?)
  case settings(SettingsSection)
}

enum LibraryCategory: String, Codable, CaseIterable, Hashable {
  case video, audio, article, book

  init?(_ kind: Item.Kind) {
    switch kind {
    case .video: self = .video
    case .audio: self = .audio
    case .article, .paper: self = .article
    case .book: self = .book
    case .repository: return nil
    }
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let saved = try container.decode(String.self)
    guard let category = saved == "paper" ? Self.article : Self(rawValue: saved) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown library category: \(saved)")
    }
    self = category
  }
}

/// The sections of settings in the sidebar.
enum SettingsSection: String, Codable, Hashable, CaseIterable {
  case general, agents, models, media, remote
}

/// A page opened on top of a place.
enum Page: Codable, Hashable {
  case item(EntityID)
  case passage(Locator)

  var itemID: EntityID? {
    switch self {
    case .item(let item): item
    case .passage(let locator): locator.item
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
    let remembered = WindowState(place: place, pages: pages.compactMap { $0.itemID.map(Page.item) })
    return (try? String(decoding: JSONEncoder().encode(remembered), as: UTF8.self)) ?? ""
  }

  /// Drops the pages of items that no longer exist, so the window goes back to the place they were opened
  /// from, such as the library an item was deleted from, and a remembered place never opens onto a blank page.
  func keeping(items: Set<EntityID>) -> WindowState {
    let kept = pages.filter { $0.itemID.map(items.contains) == true }
    return kept == pages ? self : WindowState(place: place, pages: kept)
  }

  /// Brings `item` to the front: back to its page if it is open, or on top of where the window is.
  func opening(_ item: EntityID) -> WindowState {
    guard let open = pages.lastIndex(where: { $0.itemID == item }) else {
      return opening(.item(item))
    }
    return WindowState(place: place, pages: Array(pages[...open]))
  }

  /// `page` opened over where the window is, so going back returns there.
  func opening(_ page: Page) -> WindowState {
    WindowState(place: place, pages: pages + [page])
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
  /// The project the companion's page had open last; `nil` for the chat. It stays while the window goes
  /// elsewhere, so the page opens on it again.
  var recallProject: @MainActor () -> Project.ID? = { nil }
  var rememberProject: @MainActor (Project.ID?) -> Void = { _ in }

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
      remember: { defaults.set($0.text, forKey: key) },
      recallProject: { defaults.string(forKey: key + " project").flatMap(EntityID.init(canonical:)) },
      rememberProject: { defaults.set($0?.description, forKey: key + " project") })
  }

  static func key(for folder: URL) -> String {
    "lastWindow " + folder.standardizedFileURL.path(percentEncoded: false)
  }
}
