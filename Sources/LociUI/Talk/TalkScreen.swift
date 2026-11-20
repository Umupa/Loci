import LociModel
import SwiftUI

/// The main conversation with Loci, where the window opens. A link or a file dropped anywhere on it is
/// taken into the library.
struct TalkScreen: View {
  let focusRequest: Int
  let attach: () -> Void
  @State private var draft: PassageDraft?

  var body: some View {
    ConversationScreen(
      ref: .main, draft: $draft, attach: attach, focusRequest: focusRequest
    )
    .acceptingDrops()
  }
}
