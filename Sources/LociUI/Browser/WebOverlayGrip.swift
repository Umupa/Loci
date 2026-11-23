import AppKit
import SwiftUI

struct WebOverlayGrip: NSViewRepresentable {
  enum Change {
    case dragging(CGSize)
    case finished(CGSize)
    case reset
  }

  let resize: (Change) -> Void

  func makeNSView(context: Context) -> GripView { GripView() }

  func updateNSView(_ view: GripView, context: Context) { view.resize = resize }

  final class GripView: NSView {
    var resize: ((Change) -> Void)?
    private var start: CGPoint?
    private var dragged = false

    override func resetCursorRects() {
      super.resetCursorRects()
      addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
      dragged = false
      if event.clickCount == 2 {
        start = nil
        resize?(.reset)
      } else {
        start = event.locationInWindow
      }
    }

    override func mouseDragged(with event: NSEvent) {
      guard let translation = translation(to: event) else { return }
      dragged = true
      resize?(.dragging(translation))
    }

    override func mouseUp(with event: NSEvent) {
      defer { start = nil }
      if dragged, let translation = translation(to: event) { resize?(.finished(translation)) }
    }

    private func translation(to event: NSEvent) -> CGSize? {
      guard let start else { return nil }
      let point = event.locationInWindow
      return CGSize(width: point.x - start.x, height: start.y - point.y)
    }
  }
}
