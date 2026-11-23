import AppKit
import SwiftUI

extension View {
  /// While `active`, calls `callOff` the moment Escape is down. A key pressed while the mouse is held may never
  /// reach the window as an event, so the keyboard itself is asked every `Board.listening`.
  func callsOffOnEscape(while active: Bool, _ callOff: @escaping @MainActor () -> Void) -> some View {
    task(id: active) {
      while active, !Task.isCancelled {
        if CGEventSource.keyState(.combinedSessionState, key: Board.escape) {
          callOff()
          return
        }
        try? await Task.sleep(for: Board.listening)
      }
    }
  }
}

/// Escape pressed while it lasts, as the window hears it. A drag also asks the keyboard itself, for a press
/// that never reaches the window while the mouse is held; this one hears a press too short to be seen that way.
@MainActor
final class EscapeKey {
  private var monitor: Any?

  init(_ pressed: @escaping @MainActor () -> Void) {
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard event.keyCode == Board.escape else { return event }
      MainActor.assumeIsolated { pressed() }
      return nil
    }
  }

  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }
}
