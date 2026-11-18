import Foundation
import LociModel
import SwiftUI

/// What the sidebar has selected.
enum Place: Codable, Hashable {
  case start
  /// A lesson of a course, read with the course's mentor beside it.
  case lesson(LessonRef)
  case mentor(EntityID)
  /// `nil` is every kind.
  case library(ItemKind?)
  /// The built-in browser, for finding things to add.
  case browser
  case settings(SettingsSection)
}

/// The sections of settings in the sidebar.
enum SettingsSection: String, Codable, Hashable, CaseIterable {
  case general, agents, media
}

/// A page opened on top of a place.
enum Page: Codable, Hashable {
  case lesson(LessonRef)
  case item(EntityID)
}

/// Where a window is, as text the system can keep across launches.
struct WindowState: Codable, Equatable {
  var place: Place = .start
  var pages: [Page] = []

  init(place: Place = .start, pages: [Page] = []) {
    self.place = place
    self.pages = pages
  }

  init(restoring text: String) {
    self = (try? JSONDecoder().decode(WindowState.self, from: Data(text.utf8))) ?? WindowState()
  }

  var text: String {
    (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? ""
  }

  /// Goes back to the start page when the window points at a mentor, lesson or item that no longer
  /// exists, so a remembered place never opens onto a blank page.
  func keeping(mentors: Set<EntityID>, items: Set<EntityID>) -> WindowState {
    let placeExists =
      switch place {
      case .mentor(let id): mentors.contains(id)
      case .lesson(let lesson): mentors.contains(lesson.mentor)
      case .start, .library, .browser, .settings: true
      }
    let pagesExist = pages.allSatisfy { page in
      switch page {
      case .lesson(let lesson): mentors.contains(lesson.mentor)
      case .item(let item): items.contains(item)
      }
    }
    return placeExists && pagesExist ? self : WindowState()
  }
}

/// What the menu bar can ask of the frontmost window.
struct Navigator {
  let showStart: () -> Void
  let showLibrary: () -> Void
  let showSettings: () -> Void
  let toggleSidebar: () -> Void
  let addFile: () -> Void
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
  /// the user's data. A folder never opened before has nothing remembered and opens at the start page.
  @MainActor static func preferences(_ defaults: UserDefaults, folder: URL) -> WindowMemory {
    let key = key(for: folder)
    return WindowMemory(
      recall: { WindowState(restoring: defaults.string(forKey: key) ?? "") },
      remember: { defaults.set($0.text, forKey: key) })
  }

  static func key(for folder: URL) -> String {
    "lastWindow " + folder.standardizedFileURL.path(percentEncoded: false)
  }
}
