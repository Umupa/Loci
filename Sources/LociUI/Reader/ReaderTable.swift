import AppKit
import LociModel

final class ReaderTableAttachment: NSTextAttachment {
  private static let fileTypeName = "ai.superduck.loci.reading-table"
  let table: ReaderTableContent
  let source: String

  @MainActor init(rows: [[NSAttributedString]], source: String, original: NSRange, font: NSFont) {
    self.source = source
    table = ReaderTableContent(rows: rows, original: original, font: font)
    super.init(data: nil, ofType: Self.fileTypeName)
    allowsTextAttachmentView = true
  }

  required init?(coder: NSCoder) { nil }

  override func image(
    for bounds: CGRect, attributes: [NSAttributedString.Key: Any], location: any NSTextLocation,
    textContainer: NSTextContainer?
  ) -> NSImage? { nil }

  @MainActor static func registerViewProvider() {
    NSTextAttachment.registerViewProviderClass(ReaderTableProvider.self, forFileType: fileTypeName)
  }

  override func viewProvider(
    for parentView: NSView?, location: any NSTextLocation, textContainer: NSTextContainer?
  ) -> NSTextAttachmentViewProvider? {
    let provider = ReaderTableProvider(
      textAttachment: self, parentView: parentView, textLayoutManager: textContainer?.textLayoutManager,
      location: location)
    provider.tracksTextAttachmentViewBounds = true
    return provider
  }
}

@MainActor
final class ReaderTableContent {
  let original: NSRange
  let content: NSAttributedString
  let columns: Int
  let rowStarts: [Int]

  init(rows: [[NSAttributedString]], original: NSRange, font: NSFont) {
    self.original = original
    columns = rows.map(\.count).max() ?? 1
    var position = 0
    rowStarts = rows.map { row in
      defer { position += row.reduce(0) { $0 + $1.length + 1 } }
      return position
    }
    content = Self.makeTable(rows: rows, columns: columns, font: font)
  }

  private static func makeTable(rows: [[NSAttributedString]], columns: Int, font: NSFont) -> NSAttributedString {
    let table = NSTextTable()
    table.numberOfColumns = columns
    table.layoutAlgorithm = .fixedLayoutAlgorithm
    let content = NSMutableAttributedString()
    let weights = (0..<columns).map { index in
      let width = rows.compactMap { $0.indices.contains(index) ? $0[index].size().width : nil }.max() ?? 0
      return min(max(width, 52), 148)
    }
    let total = weights.reduce(0, +)
    for (row, cells) in rows.enumerated() {
      for (column, cell) in cells.enumerated() {
        let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
        block.setContentWidth(weights[column] / total * 100, type: .percentageValueType)
        if column + 1 < columns { block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .maxX) }
        block.setWidth(4, type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth(4, type: .absoluteValueType, for: .padding, edge: .maxY)
        if row == 0 {
          block.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
          block.setBorderColor(Tones.line, for: .maxY)
        }
        let style = NSMutableParagraphStyle()
        style.textBlocks = [block]
        style.lineSpacing = 4
        let paragraph = NSMutableAttributedString(attributedString: cell)
        paragraph.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: Tones.ink]))
        paragraph.addAttribute(.paragraphStyle, value: style, range: paragraph.fullRange)
        content.append(paragraph)
      }
    }
    Serif.setCJKFonts(in: content)
    return content
  }
}

private final class ReaderTableProvider: NSTextAttachmentViewProvider {
  private let layout: ReaderTableLayout?

  override init(
    textAttachment: NSTextAttachment, parentView: NSView?, textLayoutManager: NSTextLayoutManager?,
    location: any NSTextLocation
  ) {
    layout = (textAttachment as? ReaderTableAttachment).map {
      ReaderTableLayout(content: $0.table, reader: parentView as? ReaderTextView)
    }
    super.init(
      textAttachment: textAttachment, parentView: parentView, textLayoutManager: textLayoutManager, location: location)
  }

  override func loadView() {
    let layout = layout
    view = MainActor.assumeIsolated { layout?.scroll }
  }

  override func attachmentBounds(
    for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?,
    proposedLineFragment: CGRect, position: CGPoint
  ) -> CGRect {
    guard let layout else { return .zero }
    return MainActor.assumeIsolated { layout.bounds(width: proposedLineFragment.width) }
  }
}

@MainActor
private final class ReaderTableLayout {
  private let content: ReaderTableContent
  private weak var reader: ReaderTextView?
  private lazy var table: ReaderTableView = {
    let table = ReaderTableView(usingTextLayoutManager: false)
    table.configure(content)
    table.reader = reader
    reader?.remember(table)
    return table
  }()
  private(set) lazy var scroll: NSScrollView = {
    let scroll = ReaderTableScrollView()
    scroll.drawsBackground = false
    scroll.scrollerStyle = .overlay
    scroll.autohidesScrollers = true
    scroll.documentView = table
    return scroll
  }()

  nonisolated init(content: ReaderTableContent, reader: ReaderTextView?) {
    self.content = content
    self.reader = reader
  }

  func bounds(width: CGFloat) -> CGRect {
    let scroll = scroll
    table.measure(width)
    scroll.hasHorizontalScroller = table.frame.width > width
    return CGRect(origin: .zero, size: CGSize(width: width, height: table.frame.height))
  }
}

private final class ReaderTableScrollView: NSScrollView {
  override func scrollWheel(with event: NSEvent) {
    if hasHorizontalScroller, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
      super.scrollWheel(with: event)
    } else {
      nextResponder?.scrollWheel(with: event)
    }
  }
}

final class ReaderTableView: NSTextView, NSTextViewDelegate {
  weak var reader: ReaderTextView?
  private(set) var original = NSRange()
  private var rowStarts: [Int] = []
  private var minimumWidth: CGFloat = 0
  private var measuredWidth: CGFloat = 0
  private var marked: [(note: EntityID, range: NSRange, dot: Bool)] = []
  private var noteDots: [EntityID: NoteDot] = [:]

  func configure(_ table: ReaderTableContent) {
    original = table.original
    rowStarts = table.rowStarts
    minimumWidth = CGFloat(table.columns) * 75
    isEditable = false
    isSelectable = true
    isRichText = true
    drawsBackground = false
    isVerticallyResizable = false
    isHorizontallyResizable = false
    autoresizingMask = []
    textContainer?.widthTracksTextView = false
    textContainer?.heightTracksTextView = false
    textContainer?.lineFragmentPadding = 0
    linkTextAttributes = [.foregroundColor: Tones.accentInk, .cursor: NSCursor.pointingHand]
    selectedTextAttributes = [.backgroundColor: Tones.selection]
    textStorage?.setAttributedString(table.content)
    delegate = self
  }

  func measure(_ viewportWidth: CGFloat) {
    guard let container = textContainer, let layoutManager else { return }
    let width = max(viewportWidth, minimumWidth)
    guard width != measuredWidth || frame.width != width else { return }
    measuredWidth = width
    container.size = CGSize(width: width, height: .greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: container)
    let used = layoutManager.usedRect(for: container)
    let bottom =
      layoutManager.extraLineFragmentTextContainer === container
      ? min(used.maxY, layoutManager.extraLineFragmentRect.minY) : used.maxY
    setFrameSize(CGSize(width: width, height: ceil(bottom)))
    placeDots()
  }

  func rects(of range: NSRange) -> [CGRect] {
    guard let container = textContainer, let layoutManager, range.length > 0 else { return [] }
    let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    var rects: [CGRect] = []
    layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, line, _ in
      let part = NSIntersectionRange(line, glyphs)
      rects.append(layoutManager.boundingRect(forGlyphRange: part, in: container))
    }
    return rects
  }

  func top(of originalOffset: Int) -> CGFloat? {
    guard NSLocationInRange(originalOffset, original) else { return nil }
    return rects(of: NSRange(location: originalOffset - original.location, length: 1)).first?.minY
  }

  func originalOffset(near y: CGFloat) -> Int {
    let row = rowStarts.last { (rects(of: NSRange(location: $0, length: 1)).first?.minY ?? .infinity) <= y + 1 }
    return original.location + (row ?? 0)
  }

  func placeMarks(_ marks: [ReaderMark]) {
    guard let layoutManager, let textStorage else { return }
    let local = marks.compactMap { mark -> (EntityID, NSRange, Bool)? in
      guard let source = mark.original else { return nil }
      let part = NSIntersectionRange(source, original)
      guard part.length > 0 else { return nil }
      return (mark.note, NSRange(location: part.location - original.location, length: part.length), mark.marginMark)
    }
    layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: textStorage.fullRange)
    for (_, range, _) in local {
      layoutManager.addTemporaryAttribute(.backgroundColor, value: Tones.readerMark, forCharacterRange: range)
    }
    marked = local
    if measuredWidth > 0 { placeDots() }
  }

  private func placeDots() {
    var placed: [EntityID: NoteDot] = [:]
    for mark in marked where mark.dot {
      guard let last = rects(of: mark.range).last else { continue }
      let dot = noteDots[mark.note] ?? NoteDot()
      dot.frame = CGRect(x: last.maxX, y: last.maxY + 1, width: NoteDot.size, height: NoteDot.size)
      if dot.superview == nil {
        dot.clicked = { [weak self] in self?.reader?.markClicked(mark.note) }
        addSubview(dot)
      }
      placed[mark.note] = dot
    }
    for (id, dot) in noteDots where placed[id] == nil { dot.removeFromSuperview() }
    noteDots = placed
  }

  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    if selectedRange().length == 0 {
      let point = convert(event.locationInWindow, from: nil)
      if let mark = marked.first(where: { rects(of: $0.range).contains { $0.contains(point) } }) {
        reader?.markClicked(mark.note)
        return
      }
    }
    reader?.tableSelectionEnded(self)
  }

  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    guard let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return false }
    reader?.tableLinkOpened(url)
    return true
  }
}
