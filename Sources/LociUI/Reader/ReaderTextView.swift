import AppKit
import LociModel

/// The reader's text: TextKit 2, read-only and selectable, set in one column centered in the window.
final class ReaderTextView: NSTextView {
  private let blockLayout = BlockLayout()
  /// Runs before each change of width, while the text is still laid out for the old one.
  var willResize: () -> Void = {}
  /// Runs after each change of width, once the column has its final size.
  var resized: () -> Void = {}
  /// Runs as the pointer moves over the text, with where it is; `nil` when it leaves.
  var hovered: (CGPoint?) -> Void = { _ in }
  /// Runs when a mouse selection is finished.
  var selectionEnded: () -> Void = {}
  /// Runs when the mouse is released, whether or not it selected anything.
  var dragEnded: () -> Void = {}
  /// Whether the mouse is down in the text, dragging out a selection.
  private(set) var selecting = false
  /// Runs when a highlight, or the dot after it, is clicked.
  var markClicked: (EntityID) -> Void = { _ in }
  /// How wide the column is; changing it keeps the paragraph at the top where it was.
  var readingWidth = ReadingWidth.comfortable {
    didSet {
      guard readingWidth != oldValue, frame.width > 0 else { return }
      willResize()
      setMargin(for: frame.width)
      resized()
    }
  }
  private var tracking: NSTrackingArea?
  private var noteDots: [EntityID: NoteDot] = [:]
  private var highlights: [(note: EntityID, range: NSRange, rects: [CGRect], bands: [CGRect])] = []
  private let underlines = Underlines()
  private static let noteDotSize: CGFloat = 5

  convenience init() {
    let layoutManager = NSTextLayoutManager()
    let container = NSTextContainer(size: CGSize(width: Typography.readingWidth, height: .greatestFiniteMagnitude))
    container.widthTracksTextView = true
    container.lineFragmentPadding = 0
    layoutManager.textContainer = container
    let storage = NSTextContentStorage()
    storage.addTextLayoutManager(layoutManager)
    self.init(frame: .zero, textContainer: container)
    layoutManager.delegate = blockLayout
    isEditable = false
    isSelectable = true
    isRichText = true
    drawsBackground = true
    backgroundColor = Tones.canvas
    isVerticallyResizable = true
    isHorizontallyResizable = false
    autoresizingMask = [.width]
    maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    selectedTextAttributes = [.backgroundColor: Tones.selection]
    linkTextAttributes = [.foregroundColor: Tones.accentInk, .cursor: NSCursor.pointingHand]
    textContainerInset = ReadingStyle.inset
    underlines.autoresizingMask = [.width, .height]
    addSubview(underlines)
  }

  var contentStorage: NSTextContentStorage? {
    textLayoutManager?.textContentManager as? NSTextContentStorage
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(
      rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    addTrackingArea(area)
    tracking = area
  }

  /// The text view follows the drag itself, so the selection is final when `mouseDown` returns. A click
  /// that selects nothing on a highlight chooses that highlight.
  override func mouseDown(with event: NSEvent) {
    selecting = true
    super.mouseDown(with: event)
    selecting = false
    dragEnded()
    let point = convert(event.locationInWindow, from: nil)
    if selectedRange().length == 0, let hit = highlights.first(where: { $0.rects.contains { $0.contains(point) } }) {
      markClicked(hit.note)
      return
    }
    selectionEnded()
  }

  /// Highlights are a band of amber under the lower part of the words, drawn behind the text.
  override func drawBackground(in rect: NSRect) {
    super.drawBackground(in: rect)
    Tones.mark.setFill()
    for band in highlights.flatMap(\.bands) where band.intersects(rect) {
      NSBezierPath(roundedRect: band, xRadius: 2, yRadius: 2).fill()
    }
  }

  /// The lower part of a line's letters, as a marker pen leaves it: from a little above the middle of the
  /// lowercase letters to just under the baseline. Measured from where TextKit puts the baseline, because a
  /// line's frame also holds the spacing around it.
  static func band(under line: CGRect, baseline: CGFloat, font: NSFont) -> CGRect {
    let top = baseline - font.xHeight * 0.6
    let bottom = baseline - font.descender * 0.3
    return CGRect(x: line.minX, y: top, width: line.width, height: bottom - top)
  }

  private func font(at location: Int) -> NSFont {
    guard let storage = textStorage, location < storage.length else { return ReadingStyle.body }
    return storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont ?? ReadingStyle.body
  }

  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    hovered(convert(event.locationInWindow, from: nil))
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    hovered(nil)
  }

  /// Draws marks over the text without changing it; earlier marks are cleared.
  func show(_ marks: [ReaderMark]) {
    guard let layoutManager = textLayoutManager else { return }
    let keys: [NSAttributedString.Key] = [.backgroundColor, .underlineStyle, .underlineColor]
    for key in keys { layoutManager.removeRenderingAttribute(key, for: layoutManager.documentRange) }
    for mark in marks {
      guard let range = textRange(mark.range) else { continue }
      switch mark.kind {
      case .revised:
        layoutManager.addRenderingAttribute(.backgroundColor, value: Tones.revised, for: range)
      case .term, .note:
        continue
      }
    }
    placeMarginMarks(marks)
  }

  /// Lays the highlights, glossary underlines and note dots over the text where it is now. Called again
  /// whenever the text may have moved.
  func placeMarginMarks(_ marks: [ReaderMark]) {
    underlines.frame = bounds
    underlines.lines = marks.flatMap { mark -> [Underlines.Line] in
      guard case .term = mark.kind else { return [] }
      return rects(of: mark.range).map { Underlines.Line(rect: $0) }
    }
    let bands = marks.compactMap { mark -> (note: EntityID, range: NSRange, rects: [CGRect], bands: [CGRect])? in
      guard case .note(let note, _) = mark.kind else { return nil }
      let lines = segments(of: mark.range)
      let font = font(at: mark.range.location)
      return (
        note, mark.range, lines.map(\.rect), lines.map { Self.band(under: $0.rect, baseline: $0.baseline, font: font) }
      )
    }
    if bands.map(\.bands) != highlights.map(\.bands) {
      for band in (bands + highlights).flatMap(\.bands) { setNeedsDisplay(band.insetBy(dx: -1, dy: -1)) }
    }
    highlights = bands
    var placed: [EntityID: NoteDot] = [:]
    for mark in marks {
      guard case .note(let note, marginMark: true) = mark.kind, let line = rects(of: mark.range).last else {
        continue
      }
      let size = Self.noteDotSize
      let frame = CGRect(x: line.maxX + 3, y: line.minY + line.height * 0.25 - size / 2, width: size, height: size)
      let view = noteDots[note] ?? NoteDot(frame: frame)
      if view.superview == nil {
        view.clicked = { [weak self] in self?.markClicked(note) }
        addSubview(view)
      }
      view.frame = frame
      placed[note] = view
    }
    for (note, view) in noteDots where placed[note] == nil { view.removeFromSuperview() }
    noteDots = placed
  }

  /// Washes `range` in amber at `strength` from 0 to 1, so the eye finds a passage just jumped to.
  func flash(_ range: NSRange, strength: CGFloat) {
    guard let layoutManager = textLayoutManager, let textRange = textRange(range) else { return }
    layoutManager.removeRenderingAttribute(.backgroundColor, for: textRange)
    guard strength > 0 else { return }
    let color = Tones.flash.withAlphaComponent(Tones.flash.alphaComponent * strength)
    layoutManager.addRenderingAttribute(.backgroundColor, value: color, for: textRange)
  }

  /// Keeps the column at its reading width, centered, with a margin when the window is narrow.
  override func setFrameSize(_ newSize: NSSize) {
    let widthChanged = newSize.width != frame.width
    if widthChanged, frame.width > 0 { willResize() }
    setMargin(for: newSize.width)
    super.setFrameSize(newSize)
    if widthChanged, newSize.width > 0 { resized() }
  }

  private func setMargin(for width: CGFloat) {
    let margin = readingWidth.margin(in: width)
    if textContainerInset.width != margin {
      textContainerInset = CGSize(width: margin, height: ReadingStyle.inset.height)
    }
  }

  /// Lays out what is on screen now and sizes the view to the text, instead of waiting for the next display.
  func layOutViewport() {
    textLayoutManager?.textViewportLayoutController.layoutViewport()
  }

  /// The UTF-16 offset of the text at a point in this view, or the nearest one.
  func offset(at point: CGPoint) -> Int? {
    guard let layoutManager = textLayoutManager, let storage = contentStorage else { return nil }
    let inContainer = CGPoint(x: point.x - textContainerOrigin.x, y: max(0, point.y - textContainerOrigin.y))
    guard let fragment = layoutManager.textLayoutFragment(for: inContainer) else { return nil }
    return storage.offset(from: storage.documentRange.location, to: fragment.rangeInElement.location)
  }

  /// Where the paragraph holding `offset` starts, in this view's coordinates, laying out the text before it.
  func top(of offset: Int) -> CGFloat? {
    guard let layoutManager = textLayoutManager, let storage = contentStorage,
      let location = storage.location(storage.documentRange.location, offsetBy: offset),
      let before = NSTextRange(location: storage.documentRange.location, end: location)
    else { return nil }
    layoutManager.ensureLayout(for: before)
    guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
    return fragment.layoutFragmentFrame.minY + textContainerOrigin.y
  }

  /// The rectangles that `range` covers, in this view's coordinates.
  func rects(of range: NSRange) -> [CGRect] {
    segments(of: range).map(\.rect)
  }

  /// Each line's part of `range` and where its baseline is, in this view's coordinates.
  func segments(of range: NSRange) -> [(rect: CGRect, baseline: CGFloat)] {
    guard let layoutManager = textLayoutManager, let textRange = textRange(range) else { return [] }
    var segments: [(rect: CGRect, baseline: CGFloat)] = []
    layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, baseline, _ in
      let rect = frame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
      segments.append((rect, rect.minY + baseline))
      return true
    }
    return segments
  }

  func textRange(_ range: NSRange) -> NSTextRange? {
    guard let storage = contentStorage,
      let start = storage.location(storage.documentRange.location, offsetBy: range.location),
      let end = storage.location(start, offsetBy: range.length)
    else { return nil }
    return NSTextRange(location: start, end: end)
  }
}

/// Lines under glossary terms, drawn over the text. TextKit 2 draws background colors given as rendering
/// attributes but not underlines, so these are drawn here. Clicks pass through.
final class Underlines: NSView {
  /// Under a glossary term: a dotted muted line.
  struct Line: Equatable {
    let rect: CGRect
  }

  var lines: [Line] = [] {
    didSet { if lines != oldValue { needsDisplay = true } }
  }

  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    for line in lines where line.rect.intersects(dirtyRect.insetBy(dx: 0, dy: -4)) {
      let y = line.rect.maxY + 1
      let path = NSBezierPath()
      path.move(to: CGPoint(x: line.rect.minX, y: y))
      path.line(to: CGPoint(x: line.rect.maxX, y: y))
      Tones.inkFaint.setStroke()
      path.lineWidth = 1
      path.setLineDash([1.5, 2.5], count: 2, phase: 0)
      path.stroke()
    }
  }
}

/// The amber dot after a highlight that has a thought or questions.
final class NoteDot: NSView {
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
