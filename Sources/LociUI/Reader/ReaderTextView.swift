import AppKit

/// The reader's text: TextKit 2, read-only and selectable, set in one column centered in the window.
final class ReaderTextView: NSTextView {
  private let blockLayout = BlockLayout()
  /// Runs before each change of width, while the text is still laid out for the old one.
  var willResize: () -> Void = {}
  /// Runs after each change of width, once the column has its final size.
  var resized: () -> Void = {}

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
  }

  var contentStorage: NSTextContentStorage? {
    textLayoutManager?.textContentManager as? NSTextContentStorage
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
