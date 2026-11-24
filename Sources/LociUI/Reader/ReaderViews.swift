import AppKit

/// The amber dot at the end of a highlight that has questions.
final class NoteDot: NSView {
  static let size: CGFloat = 4
  var clicked: () -> Void = {}

  override func draw(_ dirtyRect: NSRect) {
    Tones.accent.setFill()
    NSBezierPath(ovalIn: bounds).fill()
  }

  override func mouseDown(with event: NSEvent) {
    clicked()
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .pointingHand)
  }
}

/// The scroll view's clip view, which says when the reader has scrolled.
final class ReaderClipView: NSClipView {
  var scrolled: () -> Void = {}

  override func setBoundsOrigin(_ newOrigin: NSPoint) {
    super.setBoundsOrigin(newOrigin)
    scrolled()
  }

  /// Not every scroll goes through `setBoundsOrigin`; hearing one twice does no harm.
  override func scroll(to newOrigin: NSPoint) {
    super.scroll(to: newOrigin)
    scrolled()
  }
}
