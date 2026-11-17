import AppKit
import SwiftUI

/// Moves the window's close, minimize and zoom buttons so they sit inside the floating sidebar, `inset`
/// from the window's top-left corner, keeping the system's spacing between them. AppKit puts them back
/// whenever it lays out the title bar, so they are moved again after every layout and resize.
struct WindowButtons: NSViewRepresentable {
  let inset: CGPoint

  func makeNSView(context: Context) -> WindowButtonsAnchor {
    WindowButtonsAnchor(inset: inset)
  }

  func updateNSView(_ view: WindowButtonsAnchor, context: Context) {
    view.inset = inset
    view.place()
  }
}

final class WindowButtonsAnchor: NSView {
  var inset: CGPoint
  private var observers: [NSObjectProtocol] = []
  private static let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

  init(inset: CGPoint) {
    self.inset = inset
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers = []
    guard let window else { return }
    let names: [Notification.Name] = [
      NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification,
      NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
    ]
    observers = names.map { name in
      NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.place() }
      }
    }
    place()
  }

  override func layout() {
    super.layout()
    place()
  }

  /// Puts the buttons in place, measuring the system's spacing from where it put them.
  func place() {
    guard let window, !window.styleMask.contains(.fullScreen) else { return }
    let buttons = Self.kinds.compactMap { window.standardWindowButton($0) }
    guard buttons.count == Self.kinds.count, let bar = buttons[0].superview else { return }
    let spacing = buttons[1].frame.minX - buttons[0].frame.minX
    guard spacing > 0 else { return }
    for (index, button) in buttons.enumerated() {
      let y = bar.isFlipped ? inset.y : bar.bounds.height - inset.y - button.frame.height
      let origin = CGPoint(x: inset.x + CGFloat(index) * spacing, y: y)
      if button.frame.origin != origin { button.setFrameOrigin(origin) }
    }
  }
}
