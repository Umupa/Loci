import Foundation
import LociModel
import SwiftUI

/// What the sidebar has selected.
enum Place: Codable, Hashable {
  case start
  case mentor(EntityID)
  /// `nil` is every kind.
  case library(ItemKind?)
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

  /// Leaves whatever the mentor list no longer has, so a deleted mentor does not leave a blank window.
  func keeping(mentors: Set<EntityID>) -> WindowState {
    guard case .mentor(let id) = place, !mentors.contains(id) else { return self }
    return WindowState()
  }
}

/// What the menu bar can ask of the frontmost window.
struct Navigator {
  let showStart: () -> Void
  let showLibrary: () -> Void
  let addFile: () -> Void
}

extension FocusedValues {
  @Entry var navigator: Navigator?
}
