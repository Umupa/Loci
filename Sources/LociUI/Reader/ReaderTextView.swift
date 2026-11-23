import AppKit
import LociModel

/// The reader's text: TextKit 2, read-only and selectable, set in one column centered in the window.
final class ReaderTextView: NSTextView {
  private let blockLayout = BlockLayout()
  /// Runs before each change of width, while the text is still laid out for the old one.
  var willResize: () -> Void = {}
  /// Runs after each change of width, once the column has its final size.
  var resized: () -> Void = {}
  /// Runs when a mouse selection is finished.
  var selectionEnded: () -> Void = {}
  var windowChanged: (NSWindow?) -> Void = { _ in }
  /// Runs when the mouse is released, whether or not it selected anything.
  var dragEnded: () -> Void = {}
  /// Whether the mouse is down in the text, dragging out a selection.
  private(set) var selecting = false
  /// Runs when a highlight or its note dot is clicked.
  var markClicked: (EntityID) -> Void = { _ in }
  var tableSelectionEnded: (ReaderTableView) -> Void = { _ in }
  var tableLinkOpened: (URL) -> Void = { _ in }
  private(set) var tables = NSHashTable<ReaderTableView>.weakObjects()
  private var marks: [ReaderMark] = []
  /// How wide the column is; changing it keeps the paragraph at the top where it was.
  var readingWidth = ReadingWidth.comfortable {
    didSet {
      guard readingWidth != oldValue, frame.width > 0 else { return }
      willResize()
      setMargin(for: frame.width)
      resized()
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    windowChanged(window)
  }
  private var noteDots: [EntityID: NoteDot] = [:]
  /// The width the whole text was last laid out at; `nil` since the text was set.
  private var wholeLaidOutAt: CGFloat?

  /// Shows a new text in place of the old one.
  func setText(_ text: NSAttributedString) {
    tables.removeAllObjects()
    textStorage?.setAttributedString(text)
    wholeLaidOutAt = nil
  }
  private var highlights: [(note: EntityID, rects: [CGRect], bands: [CGRect])] = []

  convenience init() {
    ReaderTableAttachment.registerViewProvider()
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
  }

  func remember(_ table: ReaderTableView) {
    tables.add(table)
    table.placeMarks(marks)
  }

  override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
    selectionWithSource == nil ? super.writablePasteboardTypes : [.string]
  }

  override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
    if type == .string, let selectionWithSource { return pboard.setString(selectionWithSource, forType: type) }
    return super.writeSelection(to: pboard, type: type)
  }

  private var selectionWithSource: String? {
    let range = selectedRange()
    guard let textStorage, range.length > 0, NSMaxRange(range) <= textStorage.length else { return nil }
    var copied: NSMutableString?
    textStorage.enumerateAttribute(.attachment, in: range, options: .reverse) { value, attachment, _ in
      let source: String
      switch value {
      case let table as ReaderTableAttachment: source = table.source
      case let diagram as MermaidAttachment: source = diagram.source
      default: return
      }
      if copied == nil { copied = NSMutableString(string: (textStorage.string as NSString).substring(with: range)) }
      copied?.replaceCharacters(
        in: NSRange(location: attachment.location - range.location, length: attachment.length), with: source)
    }
    return copied.map { $0 as String }
  }

  var contentStorage: NSTextContentStorage? {
    textLayoutManager?.textContentManager as? NSTextContentStorage
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

  /// Draws the saved highlights behind the text.
  override func drawBackground(in rect: NSRect) {
    super.drawBackground(in: rect)
    Tones.readerMark.setFill()
    for band in highlights.flatMap(\.bands) where band.intersects(rect) {
      NSBezierPath(roundedRect: band, xRadius: 3, yRadius: 3).fill()
    }
  }

  /// The line's ink area with a little padding, leaving the spacing between lines clear.
  static func band(behind line: CGRect, baseline: CGFloat, font: NSFont) -> CGRect {
    let top = max(line.minY, baseline - font.ascender)
    let bottom = min(line.maxY, baseline - font.descender + 1)
    return CGRect(x: line.minX - 2, y: top, width: line.width + 4, height: bottom - top)
  }

  private func font(at location: Int) -> NSFont {
    guard let storage = textStorage, location < storage.length else { return ReadingStyle.body }
    return storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont ?? ReadingStyle.body
  }

  /// Lays the highlights and note dots over the text where it is now. Called again whenever the text may
  /// have moved.
  func placeMarginMarks(_ marks: [ReaderMark]) {
    if self.marks != marks {
      self.marks = marks
      for table in tables.allObjects { table.placeMarks(marks) }
    }
    let laidOut = marks.map { mark -> (note: EntityID, rects: [CGRect], bands: [CGRect]) in
      let lines = segments(of: mark.range).filter { line in
        line.rect.width > 0
          && !(textStorage?.attribute(.attachment, at: line.location, effectiveRange: nil)
            is ReaderTableAttachment)
      }
      let bands = lines.map { Self.band(behind: $0.rect, baseline: $0.baseline, font: font(at: $0.location)) }
      return (mark.note, zip(lines, bands).map { $0.rect.union($1) }, bands)
    }
    if laidOut.map(\.bands) != highlights.map(\.bands) {
      for band in (laidOut + highlights).flatMap(\.bands) { setNeedsDisplay(band.insetBy(dx: -1, dy: -1)) }
    }
    highlights = laidOut
    var placed: [EntityID: NoteDot] = [:]
    for (mark, layout) in zip(marks, laidOut) {
      let note = mark.note
      guard mark.marginMark, let band = layout.bands.last else { continue }
      let size = NoteDot.size
      let frame = CGRect(x: band.maxX - size, y: band.maxY + 2, width: size, height: size)
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

  /// The UTF-16 offset of the paragraph whose start is nearest a point's height: the paragraph there, or the
  /// next one when more of it is above the point than below.
  func nearestParagraph(at point: CGPoint) -> Int? {
    guard let layoutManager = textLayoutManager, let storage = contentStorage else { return nil }
    let inContainer = CGPoint(x: point.x - textContainerOrigin.x, y: max(0, point.y - textContainerOrigin.y))
    guard var fragment = layoutManager.textLayoutFragment(for: inContainer) else { return nil }
    let frame = fragment.layoutFragmentFrame
    if inContainer.y - frame.minY > frame.maxY - inContainer.y,
      let next = layoutManager.textLayoutFragment(for: CGPoint(x: inContainer.x, y: frame.maxY + 1))
    {
      fragment = next
    }
    return storage.offset(from: storage.documentRange.location, to: fragment.rangeInElement.location)
  }

  /// Where the paragraph holding `offset` starts, in this view's coordinates, laying out the text before it.
  func top(of offset: Int, original: Int? = nil) -> CGFloat? {
    guard let layoutManager = textLayoutManager, let storage = contentStorage,
      let location = storage.location(storage.documentRange.location, offsetBy: offset),
      let before = NSTextRange(location: storage.documentRange.location, end: location)
    else { return nil }
    layoutManager.ensureLayout(for: before)
    guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
    let top = fragment.layoutFragmentFrame.minY + textContainerOrigin.y
    guard let original else { return top }
    let tableFrame = fragment.frameForTextAttachment(at: location)
    guard !tableFrame.isEmpty,
      let inside = tables.allObjects.lazy.compactMap({ $0.top(of: original) }).first
    else { return top }
    return top + tableFrame.minY + inside
  }

  func originalTableOffset(at point: CGPoint) -> Int? {
    for table in tables.allObjects where table.window != nil {
      let y = table.convert(point, from: self).y
      if y >= 0, y < table.bounds.height { return table.originalOffset(near: y) }
    }
    return nil
  }

  /// Whether the last line of the text lies within `rect`, laying out the whole text to be sure: while
  /// the text is laid out from estimates, as after a jump or a new width, the view can end above the text.
  /// The whole text is laid out once for each text and width, not again for every scroll near the end.
  func showsEnd(within rect: CGRect) -> Bool {
    guard let layoutManager = textLayoutManager, let storage = contentStorage, !string.isEmpty,
      let last = storage.location(storage.documentRange.endLocation, offsetBy: -1)
    else { return false }
    if wholeLaidOutAt != frame.width {
      layoutManager.ensureLayout(for: storage.documentRange)
      wholeLaidOutAt = frame.width
    }
    guard let fragment = layoutManager.textLayoutFragment(for: last) else { return false }
    return fragment.layoutFragmentFrame.maxY + textContainerOrigin.y <= rect.maxY + 1
  }

  /// The rectangles that `range` covers, in this view's coordinates.
  func rects(of range: NSRange) -> [CGRect] {
    segments(of: range).map(\.rect)
  }

  /// Each line's part of `range`, with its baseline and starting text offset.
  func segments(of range: NSRange) -> [(rect: CGRect, baseline: CGFloat, location: Int)] {
    guard let layoutManager = textLayoutManager, let storage = contentStorage, let textRange = textRange(range) else {
      return []
    }
    var segments: [(rect: CGRect, baseline: CGFloat, location: Int)] = []
    layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { segment, frame, baseline, _ in
      let rect = frame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
      let location = segment.map { storage.offset(from: storage.documentRange.location, to: $0.location) }
      segments.append((rect, rect.minY + baseline, location ?? range.location))
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

/// The amber dot at the end of a highlight that has a thought or questions.
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
