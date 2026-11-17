import AppKit
import LociModel
import SwiftUI

/// Text to read in one column: opens at a quote, and says where the reader is as they scroll.
///
/// When the text changes while it is shown, such as a lesson the mentor revised, the reader stays where it was.
struct Reader: NSViewRepresentable {
  let text: ReadingText
  /// Where to open the first time this text is shown.
  let start: TextQuote?
  let events: ReaderEvents

  func makeCoordinator() -> ReaderCoordinator {
    ReaderCoordinator(events: events)
  }

  func makeNSView(context: Context) -> NSScrollView {
    context.coordinator.makeScrollView()
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.events = events
    context.coordinator.show(text, from: start)
  }
}

/// What the reader tells the page around it.
struct ReaderEvents {
  /// The reader settled with this quote at the top of the window.
  var moved: (TextQuote) -> Void = { _ in }
  /// The end of the text has been on screen.
  var reachedEnd: () -> Void = {}
  var openLink: (URL) -> Void = { _ in }
}

@MainActor
final class ReaderCoordinator: NSObject, NSTextViewDelegate {
  var events: ReaderEvents
  private weak var textView: ReaderTextView?
  private weak var scrollView: NSScrollView?
  private var shown: String?
  private var pendingStart: TextQuote?
  private var reporting: Task<Void, Never>?
  private var endReported = false
  /// How long the reader stays still before its place is remembered.
  private let settle: Duration
  private static let quoteLength = 40

  init(events: ReaderEvents, settle: Duration = .milliseconds(500)) {
    self.events = events
    self.settle = settle
  }

  /// The scroll view holding the text, which this coordinator then looks after.
  func makeScrollView() -> NSScrollView {
    let scrollView = NSScrollView()
    let clip = ReaderClipView()
    scrollView.contentView = clip
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = true
    scrollView.backgroundColor = Tones.canvas
    let textView = ReaderTextView()
    textView.delegate = self
    scrollView.documentView = textView
    self.textView = textView
    self.scrollView = scrollView
    textView.willResize = { [weak self] in self?.holdPlace() }
    textView.resized = { [weak self] in self?.applyPendingStart() }
    clip.scrolled = { [weak self] in self?.scrolled() }
    return scrollView
  }

  func show(_ text: ReadingText, from start: TextQuote?) {
    guard let textView, shown != text.plain else { return }
    let keep = shown == nil ? start : topQuote()
    shown = text.plain
    textView.textStorage?.setAttributedString(text.string)
    textView.layOutViewport()
    pendingStart = keep
    applyPendingStart()
  }

  /// A new width lays the text out again from estimates, which would leave the reader somewhere else; the
  /// paragraph at the top is kept there instead.
  private func holdPlace() {
    guard shown != nil, pendingStart == nil else { return }
    pendingStart = topQuote()
  }

  /// Scrolls to where the reader should open, once the column has a width to lay the text out in.
  private func applyPendingStart() {
    guard let textView, let scrollView, textView.frame.width > 0 else { return }
    defer { checkEnd() }
    guard let start = pendingStart else { return }
    pendingStart = nil
    let plain = textView.string
    guard let range = start.range(in: plain), let top = textView.top(of: NSRange(range, in: plain).location) else {
      return
    }
    textView.layOutViewport()
    scrollView.contentView.scroll(to: CGPoint(x: 0, y: max(0, top - ReadingStyle.inset.height)))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    textView.layOutViewport()
  }

  private func scrolled() {
    checkEnd()
    reporting?.cancel()
    reporting = Task { [weak self, settle] in
      try? await Task.sleep(for: settle)
      guard !Task.isCancelled, let self, let quote = self.topQuote() else { return }
      self.events.moved(quote)
    }
  }

  private func checkEnd() {
    guard !endReported, let textView, let scrollView, !textView.string.isEmpty else { return }
    let visible = scrollView.documentVisibleRect
    guard visible.maxY >= textView.frame.height - 1 else { return }
    endReported = true
    events.reachedEnd()
  }

  /// A few words at the start of the paragraph at the top of the window, quoted with their context.
  ///
  /// The top is taken a margin below the window's edge, where opening at a quote puts its paragraph.
  func topQuote() -> TextQuote? {
    guard let textView, let scrollView else { return nil }
    textView.layOutViewport()
    let visible = scrollView.documentVisibleRect
    guard let offset = textView.offset(at: CGPoint(x: 0, y: visible.minY + ReadingStyle.inset.height + 1)) else {
      return nil
    }
    let plain = textView.string
    let utf16 = plain as NSString
    let paragraph = utf16.paragraphRange(for: NSRange(location: offset, length: 0))
    let words = utf16.substring(with: paragraph).trimmingCharacters(in: .newlines).prefix(Self.quoteLength)
    guard let start = Range(NSRange(location: offset, length: 0), in: plain)?.lowerBound,
      let end = plain.index(start, offsetBy: words.count, limitedBy: plain.endIndex)
    else { return nil }
    return try? TextQuote(quoting: start..<end, in: plain)
  }

  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    guard let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return false }
    events.openLink(url)
    return true
  }
}
