import AppKit
import LociModel
import SwiftUI

/// ⌘V on a page that takes links, wherever the keyboard is in the window: the sidebar, the list, or nowhere.
/// The menu's Paste goes to whatever has the keyboard, and on these pages that is rarely anything that pastes.
/// A text field that is being typed into keeps ⌘V for itself.
enum LinkPasteKey {
  static func isPaste(_ event: NSEvent) -> Bool {
    KeyMonitor.modifiers(of: event) == .command && event.charactersIgnoringModifiers?.lowercased() == "v"
  }
}

/// Keys pressed in the window while no text is being typed; see `KeyMonitor`.
struct WindowKeys: NSViewRepresentable {
  /// Whether it handled the key; `nil` hears nothing.
  let handle: (@MainActor (NSEvent) -> Bool)?

  func makeNSView(context: Context) -> KeyMonitor {
    KeyMonitor()
  }

  func updateNSView(_ view: KeyMonitor, context: Context) {
    view.handle = handle
  }
}

/// Hears the keys pressed in its window while no text is being typed, wherever the keyboard is: the sidebar,
/// a list, or nowhere. A key it handles goes no further.
final class KeyMonitor: NSView {
  /// Whether it handled the key; `nil` hears nothing.
  var handle: (@MainActor (NSEvent) -> Bool)?
  private var monitor: Any?

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    stop()
    guard window != nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let window = self.window, event.window === window, let handle = self.handle,
        !Self.isTyping(into: window.firstResponder), handle(event)
      else { return event }
      return nil
    }
  }

  private func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }

  /// A field being typed into has the window's shared text view.
  nonisolated static func isTyping(into responder: NSResponder?) -> Bool {
    responder is NSText
  }

  nonisolated static func modifiers(of event: NSEvent) -> NSEvent.ModifierFlags {
    event.modifierFlags.intersection([.command, .shift, .option, .control])
  }
}

/// The link on a pasteboard: copied as a link, or as text that is nothing but one.
enum PastedLink {
  static func on(_ pasteboard: NSPasteboard) -> URL? {
    if let url = pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL, url.isWebLink { return url }
    return pasteboard.string(forType: .string).flatMap(URL.init(webLinkText:))
  }
}
