import LociModel
import SwiftUI

/// The two faces of the companion: the chat, and its home page in front of it. The chat stays made while the
/// home page shows, so going back finds it as it was. Opening the home page, the face and the name in the
/// chat's corner fly to where they sit on the page while the chat sinks away; going back plays it in reverse.
struct CompanionSpace: View {
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.openPlace) private var openPlace
  @Namespace private var flight
  let face: Face
  let chatRequest: Int
  let focusRequest: Int
  let attach: () -> Void
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  @Binding var columnPreferred: Bool
  let memory: WindowMemory
  let visits: ConversationVisits
  let chatShown: () -> Void
  /// Asks the chat's input field for the keyboard after the home page's message button.
  @State private var messaging = 0

  /// Which of the two is in front.
  enum Face: Hashable {
    case chat
    case home(LociScreen.Opening)
  }

  private var home: LociScreen.Opening? {
    if case .home(let opening) = face { opening } else { nil }
  }

  var body: some View {
    let homeShown = home != nil
    ZStack {
      CompanionPage(
        chatRequest: chatRequest, focusRequest: focusRequest + messaging, attach: attach, opened: opened,
        failed: failed, columnPreferred: $columnPreferred, memory: memory, visits: visits
      )
      .opacity(homeShown ? 0 : 1)
      .offset(y: homeShown && !reduceMotion ? Self.sink : 0)
      .allowsHitTesting(!homeShown)
      .accessibilityHidden(homeShown)
      if let home {
        LociScreen(home, back: { openPlace(.talk) }, message: message)
          .id(home)
          .transition(.opacity)
      }
    }
    .environment(\.companionHomeShown, homeShown)
    .environment(\.companionFlight, reduceMotion ? nil : flight)
    .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.companionFlight, value: homeShown)
    .onChange(of: homeShown, initial: true) { if !homeShown { chatShown() } }
  }

  private func message() {
    messaging += 1
    openPlace(.talk)
  }

  /// How far the chat sinks as the home page comes up.
  private static let sink: CGFloat = 14
}

/// What flies between the chat's corner and the companion's home page.
enum CompanionFlight: Hashable {
  case face, name
}

extension EnvironmentValues {
  /// Where the companion's face and name fly between the chat and its home page; `nil` with less motion.
  @Entry var companionFlight: Namespace.ID?
  /// Whether the companion's home page is in front of the chat.
  @Entry var companionHomeShown = false
  /// Whether pages are open over the place, so ⌘[ goes back from them and not from the place.
  @Entry var pagesOver = false
}

extension View {
  /// Flies with its namesake on the other face of the companion, when there is somewhere to fly.
  @ViewBuilder func flying(_ part: CompanionFlight, in flight: Namespace.ID?) -> some View {
    if let flight {
      matchedGeometryEffect(id: part, in: flight, anchor: .topLeading)
    } else {
      self
    }
  }
}

extension Place {
  /// Which face of the companion the place shows; `nil` for the rest of the app.
  var companion: CompanionSpace.Face? {
    switch self {
    case .talk: .chat
    case .loci: .home(LociScreen.Opening())
    case .connector(let id): .home(LociScreen.Opening(tab: .connectors, connector: id))
    case .watch(let home): .home(LociScreen.Opening(tab: .watch, watch: home))
    case .library, .browser, .courses, .settings: nil
    }
  }
}
