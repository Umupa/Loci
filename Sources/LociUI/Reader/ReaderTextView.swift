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
  /// Runs when the margin mark of a note is clicked.
  var markClicked: (EntityID) -> Void = { _ in }
  private var tracking: NSTrackingArea?
  private var marginMarks: [EntityID: MarginMark] = [:]
  private let underlines = Underlines()
  private static let marginMarkSize: CGFloat = 6

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
    selectedTextAttributes = [.backgroundColor: Tones.selection, .foregroundColor: Tones.onSelection]
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

  /// The text view follows the drag itself, so the selection is final when `mouseDown` returns.
  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    selectionEnded()
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

  /// Puts a small mark in the left margin beside each note that has a thought or questions. Called again
  /// whenever the text may have moved.
  func placeMarginMarks(_ marks: [ReaderMark]) {
    underlines.frame = bounds
    underlines.lines = marks.flatMap { mark -> [Underlines.Line] in
      let style: Underlines.Style
      switch mark.kind {
      case .term: style = .dotted
      case .note: style = .highlight
      case .revised: return []
      }
      return rects(of: mark.range).map { Underlines.Line(rect: $0, style: style) }
    }
    var placed: [EntityID: MarginMark] = [:]
    for mark in marks {
      guard case .note(let note, marginMark: true) = mark.kind, let line = rects(of: mark.range).first else {
        continue
      }
      let size = Self.marginMarkSize
      let frame = CGRect(
        x: textContainerOrigin.x - Spacing.m - size, y: line.midY - size / 2, width: size, height: size)
      let view = marginMarks[note] ?? MarginMark(frame: frame)
      if view.superview == nil {
        view.clicked = { [weak self] in self?.markClicked(note) }
        addSubview(view)
      }
      view.frame = frame
      placed[note] = view
    }
    for (note, view) in marginMarks where placed[note] == nil { view.removeFromSuperview() }
    marginMarks = placed
  }

  /// Washes `range` in amber, so the eye finds a passage just jumped to. Showing the marks again ends it.
  func flash(_ range: NSRange) {
    guard let layoutManager = textLayoutManager, let textRange = textRange(range) else { return }
    layoutManager.addRenderingAttribute(.backgroundColor, value: Tones.selection, for: textRange)
  }

  /// Keeps the column at its reading width, centered, with a margin when the window is narrow.
  override func setFrameSize(_ newSize: NSSize) {
    let widthChanged = newSize.width != frame.width
    if widthChanged, frame.width > 0 { willResize() }
    let margin = max(Spacing.xxl, (newSize.width - Typography.readingWidth) / 2)
    if textContainerInset.width != margin {
      textContainerInset = CGSize(width: margin, height: ReadingStyle.inset.height)
    }
    super.setFrameSize(newSize)
    if widthChanged, newSize.width > 0 { resized() }
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
    guard let layoutManager = textLayoutManager, let textRange = textRange(range) else { return [] }
    var rects: [CGRect] = []
    layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
      rects.append(frame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y))
      return true
    }
    return rects
  }

  func textRange(_ range: NSRange) -> NSTextRange? {
    guard let storage = contentStorage,
      let start = storage.location(storage.documentRange.location, offsetBy: range.location),
      let end = storage.location(start, offsetBy: range.length)
    else { return nil }
    return NSTextRange(location: start, end: end)
  }
}

/// Lines under highlighted passages and glossary terms, drawn over the text. TextKit 2 draws background
/// colors given as rendering attributes but not underlines, so these are drawn here. Clicks pass through.
final class Underlines: NSView {
  enum Style {
    /// A note's highlight: a thick amber line.
    case highlight
    /// A glossary term: a dotted muted line.
    case dotted
  }

  struct Line: Equatable {
    let rect: CGRect
    let style: Style
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
      let y = line.rect.maxY + 2
      let path = NSBezierPath()
      path.move(to: CGPoint(x: line.rect.minX, y: y))
      path.line(to: CGPoint(x: line.rect.maxX, y: y))
      switch line.style {
      case .highlight:
        Tones.accent.setStroke()
        path.lineWidth = 2
      case .dotted:
        Tones.inkMuted.setStroke()
        path.lineWidth = 1
        path.setLineDash([1.5, 2.5], count: 2, phase: 0)
      }
      path.stroke()
    }
  }
}

/// The amber dot beside a note in the margin.
final class MarginMark: NSView {
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
