import LociModel
import SwiftUI

extension ContentRef {
  /// The item this is, when it is one.
  var item: EntityID? {
    if case .item(let item) = self { return item }
    return nil
  }

  /// The lesson this is, when it is one.
  var lesson: Lesson.ID? {
    if case .lesson(_, let lesson) = self { return lesson }
    return nil
  }

  /// The conversation about it: an item's own, or its course's.
  var conversation: ConversationRef {
    switch self {
    case .item(let item): .item(item)
    case .lesson(let course, _): .course(course)
    }
  }
}

extension Page {
  init?(_ content: ContentRef) {
    guard case .item(let item) = content else { return nil }
    self = .item(item)
  }
}

/// Opens a page on top of the current place, as following a link does.
struct OpenPage {
  let action: (Page) -> Void

  func callAsFunction(_ page: Page) {
    action(page)
  }

  @MainActor func follow(_ locator: Locator, in conversation: ConversationRef, reveal: @MainActor (Locator) -> Void) {
    switch locator.content {
    case .item(let item):
      if conversation == .item(item) {
        reveal(locator)
      } else {
        action(.passage(locator))
      }
    case .lesson(let course, _) where conversation == .course(course):
      reveal(locator)
    case .lesson:
      break
    }
  }

  @MainActor func follow(_ url: URL, in conversation: ConversationRef, reveal: @MainActor (Locator) -> Void)
    -> OpenURLAction.Result
  {
    guard url.scheme?.lowercased() == "loci" else { return .systemAction }
    guard let locator = Locator(url.absoluteString) else { return .discarded }
    follow(locator, in: conversation, reveal: reveal)
    return .handled
  }
}

/// Goes to a place in the sidebar, as a fix for stopped work does.
struct OpenPlace {
  let action: (Place) -> Void

  func callAsFunction(_ place: Place) {
    action(place)
  }
}

extension EnvironmentValues {
  @Entry var openPage = OpenPage { _ in }
  @Entry var openPlace = OpenPlace { _ in }
}
