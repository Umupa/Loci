import AppKit
import SwiftUI

/// Watches the window's clicks while a stack is spread, and gathers it on any click that does not land on
/// one of its cards: between them, beside them, on a bubble, on the input field, anywhere in the conversation.
@MainActor
final class StackSpread {
  private var monitor: Any?
  /// Where the cards are, in the window's top-left coordinates.
  var cards: [Int: CGRect] = [:]

  /// Whether a click at `click` misses every card. Where something floats over the conversation, such as
  /// the input field, the cards scrolled under it are not there to click.
  nonisolated static func gathers(click: CGPoint, cards: [CGRect], covered: CGRect = .null) -> Bool {
    covered.contains(click) || !cards.contains { $0.contains(click) }
  }

  func watch(covered: ConversationCover?, gather: @escaping @MainActor () -> Void) {
    stop()
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      guard let self, let height = event.window?.contentView?.bounds.height else { return event }
      let click = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
      if Self.gathers(click: click, cards: Array(cards.values), covered: covered?.area ?? .null) { gather() }
      return event
    }
  }

  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }
}

/// What floats over a conversation's foot, the input field and the fade above it, in the window's top-left
/// coordinates; the conversation keeps it current.
@MainActor
final class ConversationCover {
  var area = CGRect.null
}

extension EnvironmentValues {
  @Entry var conversationCover: ConversationCover?
}
