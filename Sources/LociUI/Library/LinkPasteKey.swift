import AppKit
import LociModel
import SwiftUI

/// ⌘V on a page that takes links, wherever the keyboard is in the window: the sidebar, the list, or nowhere.
/// The menu's Paste goes to whatever has the keyboard, and on these pages that is rarely anything that pastes.
/// A text field that is being typed into keeps ⌘V for itself.
struct LinkPasteKey: NSViewRepresentable {
  /// `nil` while the window shows a page that does not take links. Whether the pasteboard held a link.
  let paste: (@MainActor () -> Bool)?

  func makeNSView(context: Context) -> LinkPasteMonitor {
    LinkPasteMonitor()
  }

  func updateNSView(_ view: LinkPasteMonitor, context: Context) {
    view.paste = paste
  }
}

final class LinkPasteMonitor: NSView {
  var paste: (@MainActor () -> Bool)?
  private var monitor: Any?

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    stop()
    guard window != nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let window = self.window, event.window === window, let paste = self.paste,
        Self.takes(event, typingInto: window.firstResponder), paste()
      else { return event }
      return nil
    }
  }

  private func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }

  /// ⌘V, while no text is being typed: a field being typed into has the window's shared text view.
  static func takes(_ event: NSEvent, typingInto responder: NSResponder?) -> Bool {
    let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
    return modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "v" && !(responder is NSText)
  }
}

/// The link on a pasteboard: copied as a link, or as text that is nothing but one.
enum PastedLink {
  static func on(_ pasteboard: NSPasteboard) -> URL? {
    if let url = pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL, url.isWebLink { return url }
    return pasteboard.string(forType: .string).flatMap(URL.init(webLinkText:))
  }
}
