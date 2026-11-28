import LociModel
import SwiftUI

/// What floats over the whole window: the import card, or the follow card under the link field.
struct WindowFloating: View {
  @Binding var dialogs: Dialogs
  /// Opens an item the import card found already in the library.
  let open: (EntityID) -> Void

  var body: some View {
    if let pending = dialogs.intake {
      ImportSheet(pending: pending, close: { dialogs.intake = nil }, open: open)
        .id(pending)
        .transition(.opacity)
    } else if let link = dialogs.following {
      FollowCardLayer(link: link) { dialogs.following = nil }.id(link)
    }
  }
}

/// A page opened over a place: a follow page, or an item's.
struct PageScreen: View {
  let page: Page

  var body: some View {
    if case .follow(let follow) = page {
      FollowScreen(follow: follow)
    } else {
      ItemScreen(destination: page)
    }
  }
}
