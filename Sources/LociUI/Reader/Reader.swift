import AppKit
import LociModel
import SwiftUI

/// Text to read in one column: opens at a quote, and says where the reader is as they scroll.
///
/// When the text changes while it is shown, the reader stays where it was.
struct Reader: NSViewRepresentable {
  let text: ReadingText
  /// Where to open the first time this text is shown.
  let start: TextQuote?
  var width = ReadingWidth.comfortable
  var marks: [ReaderMark] = []
  /// A passage to bring into view and flash; a new serial brings it again.
  var reveal: Reveal?
  /// Words to select as soon as they are shown, as if the reader had just chosen them; for a snapshot.
  var selected: String?
  let events: ReaderEvents
  let passageBar: PassagePopover

  func makeCoordinator() -> ReaderCoordinator {
    ReaderCoordinator(events: events, passageBar: passageBar)
  }

  func makeNSView(context: Context) -> NSScrollView {
    context.coordinator.makeScrollView()
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.events = events
    context.coordinator.locale = context.environment.locale
    context.coordinator.measure(width)
    context.coordinator.show(text, from: start)
    context.coordinator.mark(marks)
    if let reveal { context.coordinator.reveal(reveal) }
    if let selected { context.coordinator.select(selected) }
  }
}

/// A request to show a passage of the reading text, in UTF-16 units.
struct Reveal: Equatable {
  let range: NSRange
  let serial: Int
  var original: NSRange?
}

/// What the reader tells the page around it.
struct ReaderEvents {
  /// The reader settled with this quote at the top of the window.
  var moved: (TextQuote) -> Void = { _ in }
  /// The end of the text has been on screen.
  var reachedEnd: () -> Void = {}
  /// How far down the text the reader has scrolled, from 0 at the top to 1 at the end.
  var scrolledThrough: (Double) -> Void = { _ in }
  var openLink: (URL) -> Void = { _ in }
  /// What a selected passage offers; `nil` offers nothing.
  var passage: PassageActions?
  var tablePassage: PassageActions?
  /// A highlight was chosen in the text, by clicking it or by highlighting a picture.
  var noteClicked: (EntityID) -> Void = { _ in }
  /// A picture was just highlighted from its tools, which leave no bar to write its thought in.
  var pictureHighlighted: (EntityID) -> Void = { _ in }
}

@MainActor
final class ReaderCoordinator: NSObject, NSTextViewDelegate {
  var events: ReaderEvents
  var locale = Locale.current
  private weak var textView: ReaderTextView?
  private weak var scrollView: NSScrollView?
  private var current: ReadingText?
  /// The place the reader was opened at, or put back at, and keeps until the person moves it: each new
  /// version of the text, as pictures arrive, and each new width, is set to show it again. While a place
  /// is held, where the window happens to be is not remembered, so it cannot overwrite the place.
  private var held: TextQuote?
  /// Where the window's top was left when the held place was last shown; moving away from it is the person
  /// moving.
  private var heldTop: CGFloat?
  private var aligning = false
  /// The column is changing width; the text moving meanwhile is the reader's doing, not the person's.
  private var resizing = false
  /// How far the window may drift from where it was put before that counts as the person moving it.
  private static let drift: CGFloat = 24
  private var reporting: Task<Void, Never>?
  private var endReported = false
  private var marks: [ReaderMark] = []
  private var marksStale = false
  private let passageBar: PassagePopover
  private let pictureTools = PictureToolsHost()
  private var revealed: Int?
  private var selecting: String?
  private var selected: String?
  private var flashing: Task<Void, Never>?
  /// How long the reader stays still before its place is remembered.
  private let settle: Duration
  private static let quoteLength = 40

  init(events: ReaderEvents, settle: Duration = .milliseconds(500), passageBar: PassagePopover = PassagePopover()) {
    self.events = events
    self.settle = settle
    self.passageBar = passageBar
  }

  /// The scroll view holding the text, which this coordinator then looks after.
  func makeScrollView() -> NSScrollView {
    let scrollView = NSScrollView()
    let clip = ReaderClipView()
    scrollView.contentView = clip
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.drawsBackground = true
    scrollView.backgroundColor = Tones.canvas
    let textView = ReaderTextView()
    textView.delegate = self
    scrollView.documentView = textView
    self.textView = textView
    self.scrollView = scrollView
    textView.willResize = { [weak self] in
      self?.resizing = true
      self?.holdPlace()
    }
    textView.resized = { [weak self] in
      self?.resizing = false
      self?.showHeld()
    }
    clip.scrolled = { [weak self] in self?.scrolled() }
    textView.selectionEnded = { [weak self] in self?.selectionEnded() }
    textView.tableSelectionEnded = { [weak self] table in self?.offerTablePassage(table) }
    textView.tableLinkOpened = { [weak self] url in self?.events.openLink(url) }
    textView.windowChanged = { [weak self] window in
      if window == nil {
        self?.passageBar.close()
      } else {
        Task { self?.selectWanted() }
      }
    }
    textView.dragEnded = { [weak self] in self?.dragEnded() }
    textView.markClicked = { [weak self] in self?.chose($0) }
    textView.pictureHovered = { [weak self] in self?.hovered($0) }
    return scrollView
  }

  /// Puts the picture tools over the picture the mouse is on, or away when it is on none.
  private func hovered(_ spot: ReaderPictureSpot?) {
    guard let spot, let textView, let actions = events.passage else { return pictureTools.hide() }
    pictureTools.show(
      spot, marked: textView.markedPictures.first { $0.frame == spot.frame }?.note, in: textView, actions: actions,
      locale: locale, chose: { [weak self] in self?.chose($0) },
      highlighted: { [weak self] in self?.events.pictureHighlighted($0) })
  }

  /// A highlight clicked in the text: its card is chosen, and the bar for its thought floats over it.
  private func chose(_ note: EntityID) {
    events.noteClicked(note)
    guard let textView, let actions = events.passage,
      let lines = textView.highlights.first(where: { $0.note == note })?.rects, !lines.isEmpty
    else { return }
    let thought = marks.first { $0.note == note }?.thought
    passageBar.show(actions, note: note, thought: thought, over: lines, in: textView, locale: locale)
  }

  func show(_ text: ReadingText, from start: TextQuote?) {
    guard let textView, current?.string !== text.string else { return }
    passageBar.close()
    pictureTools.hide()
    let keep = current == nil ? start : held ?? topQuote()
    aligning = true
    current = text
    textView.setText(text.string)
    textView.placeMarginMarks(marks)
    textView.layOutViewport()
    aligning = false
    held = keep
    showHeld()
  }

  func measure(_ width: ReadingWidth) {
    textView?.readingWidth = width
  }

  func mark(_ marks: [ReaderMark]) {
    guard marks != self.marks else { return }
    self.marks = marks
    textView?.placeMarginMarks(marks)
    if let spot = pictureTools.spot { hovered(spot) }
  }

  /// Scrolls the passage a third of the way down the window and flashes it.
  func reveal(_ request: Reveal) {
    guard request.serial != revealed, let textView, let scrollView, current != nil, textView.frame.width > 0,
      let top = textView.top(of: request.range.location, original: request.original?.location)
    else { return }
    revealed = request.serial
    release()
    textView.layOutViewport()
    let y = max(0, top - scrollView.contentSize.height / 3)
    scrollView.contentView.scroll(to: CGPoint(x: 0, y: y))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    textView.layOutViewport()
    textView.placeMarginMarks(marks)
    flashing?.cancel()
    textView.flash(request.range, strength: 1)
    flashing = Task { [weak self] in
      try? await Task.sleep(for: Motion.flashHold)
      for step in stride(from: Self.fadeSteps - 1, through: 0, by: -1) {
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: Motion.flashFadeStep)
        self?.textView?.flash(request.range, strength: CGFloat(step) / CGFloat(Self.fadeSteps))
      }
      guard !Task.isCancelled, let self else { return }
      self.textView?.placeMarginMarks(self.marks)
    }
  }

  private static let fadeSteps = 20

  /// Marks are not moved while a selection is dragged past the window's edge, only once it is let go.
  private func dragEnded() {
    guard marksStale else { return }
    marksStale = false
    textView?.placeMarginMarks(marks)
  }

  /// Selects the first place `words` appear and offers what can be done with them, once the text is in a
  /// window to float the bar over.
  func select(_ words: String) {
    guard words != selected else { return }
    selected = words
    selecting = words
    selectWanted()
  }

  /// Tries again until the words are laid out and the bar is over them; scrolling the text closes the bar, so
  /// a scroll while the words are wanted brings them back.
  private func selectWanted() {
    guard let words = selecting, let textView, textView.window != nil else { return }
    let range = (textView.string as NSString).range(of: words)
    guard range.location != NSNotFound else { return }
    textView.setSelectedRange(range)
    if offerPassage() {
      selecting = nil
    } else {
      Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(50))
        self?.selectWanted()
      }
    }
  }

  private func selectionEnded() {
    offerPassage()
  }

  private func offerTablePassage(_ table: ReaderTableView) {
    guard let actions = events.tablePassage else { return }
    let local = table.selectedRange()
    let lines = table.rects(of: local)
    guard !lines.isEmpty, NSMaxRange(local) <= table.original.length else { return }
    let original = NSRange(location: table.original.location + local.location, length: local.length)
    passageBar.show(actions, for: original, over: lines, in: table, locale: locale)
  }

  /// Floats the bar over the selected passage. Whether it is shown.
  @discardableResult private func offerPassage() -> Bool {
    guard let textView, let actions = events.passage else { return false }
    let range = textView.selectedRange()
    let lines = textView.rects(of: range)
    guard range.length > 0, !lines.isEmpty else { return false }
    passageBar.show(actions, for: range, over: lines, in: textView, locale: locale)
    return true
  }

  /// A new width lays the text out again from estimates, which would leave the reader somewhere else; the
  /// paragraph at the top is held there instead.
  private func holdPlace() {
    guard current != nil, held == nil else { return }
    held = topQuote()
    heldTop = scrollView?.documentVisibleRect.minY
  }

  /// Shows the held place, once the column has a width to lay the text out in. A picture not yet in the text
  /// is stood in for by the words after it until it arrives.
  private func showHeld() {
    guard let textView, let scrollView, textView.frame.width > 0 else { return }
    defer {
      checkEnd()
      textView.placeMarginMarks(marks)
      selectWanted()
    }
    guard let held, let current else { return }
    aligning = true
    defer {
      aligning = false
      heldTop = scrollView.documentVisibleRect.minY
    }
    guard
      let original = current.originalRange(of: held) ?? Self.after(picture: held).flatMap(current.originalRange(of:)),
      let top = textView.top(of: current.map.shown(original).location, original: original.location)
    else { return }
    textView.layOutViewport()
    scrollView.contentView.scroll(to: CGPoint(x: 0, y: max(0, top - ReadingStyle.inset.height)))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    textView.layOutViewport()
  }

  /// The words after a picture, standing in for it while the text shows its description instead.
  private static func after(picture quote: TextQuote) -> TextQuote? {
    guard quote.text == "\u{FFFC}", let after = quote.after?.trimmingCharacters(in: .whitespacesAndNewlines) else {
      return nil
    }
    return try? TextQuote(after)
  }

  /// The person moved the reader: from now on its place is wherever they leave it.
  private func release() {
    held = nil
    heldTop = nil
  }

  /// What the reader does to its own text, setting a new version, a new width or a held place, neither
  /// releases the place nor cancels remembering where the person left it.
  private func scrolled() {
    let adjusting = aligning || resizing
    if !adjusting, held != nil, let heldTop, let scrollView,
      abs(scrollView.documentVisibleRect.minY - heldTop) > Self.drift
    {
      release()
    }
    passageBar.close()
    if let scrollView, let textView {
      let room = textView.frame.height - scrollView.documentVisibleRect.height
      events.scrolledThrough(room > 0 ? min(max(scrollView.documentVisibleRect.minY / room, 0), 1) : 1)
    }
    if let selected, selecting == nil {
      selecting = selected
      Task { selectWanted() }
    }
    checkEnd()
    if textView?.selecting == true {
      marksStale = true
    } else {
      textView?.placeMarginMarks(marks)
    }
    guard !adjusting, held == nil else { return }
    reporting?.cancel()
    reporting = Task { [weak self, settle] in
      try? await Task.sleep(for: settle)
      guard !Task.isCancelled, let self, let quote = self.topQuote() else { return }
      self.events.moved(quote)
    }
  }

  private func checkEnd() {
    guard !endReported, let textView, let scrollView, !textView.string.isEmpty, textView.frame.width > 0 else {
      return
    }
    let visible = scrollView.documentVisibleRect
    guard visible.maxY >= textView.frame.height - 1, textView.showsEnd(within: visible) else { return }
    endReported = true
    events.reachedEnd()
  }

  /// A few words at the start of the paragraph that starts nearest the top of the window, quoted with their
  /// context: reopening there puts the reader back within half a paragraph of where they were.
  ///
  /// The top is taken a margin below the window's edge, where opening at a quote puts its paragraph.
  func topQuote() -> TextQuote? {
    guard let textView, let scrollView else { return nil }
    textView.layOutViewport()
    let visible = scrollView.documentVisibleRect
    guard let current else { return nil }
    let point = CGPoint(x: 0, y: visible.minY + ReadingStyle.inset.height + 1)
    guard
      let offset =
        textView.originalTableOffset(at: point)
        ?? textView.nearestParagraph(at: point).map({ current.map.original(NSRange(location: $0, length: 0)).location })
    else { return nil }
    let plain = current.original
    let utf16 = plain as NSString
    let location = min(offset, utf16.length)
    let paragraph = utf16.paragraphRange(for: NSRange(location: location, length: 0))
    let words = utf16.substring(with: paragraph).trimmingCharacters(in: .newlines).prefix(Self.quoteLength)
    guard let start = Range(NSRange(location: location, length: 0), in: plain)?.lowerBound,
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
