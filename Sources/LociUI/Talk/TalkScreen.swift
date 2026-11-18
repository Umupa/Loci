import LociModel
import SwiftUI

/// The main conversation with Loci, where the window opens. A link or a file dropped anywhere on it goes
/// into the library.
struct TalkScreen: View {
  @Environment(\.openPage) private var openPage
  let focusRequest: Int
  let attach: () -> Void
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  @State private var draft: PassageDraft?

  var body: some View {
    ConversationScreen(
      ref: .main, draft: $draft, revealPassage: { openPage(Page($0.content)) }, attach: attach,
      focusRequest: focusRequest
    )
    .acceptingDrops(opened: opened, failed: failed)
  }
}
