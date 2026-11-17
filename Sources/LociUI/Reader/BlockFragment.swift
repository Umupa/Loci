import AppKit

/// Lays out a paragraph that carries a `BlockDecoration` and draws the decoration behind its text: the
/// background of a code block, the bar beside a quote, the hairline of a rule or under a table's header.
final class BlockFragment: NSTextLayoutFragment {
  private let decoration: BlockDecoration
  private let indent: CGFloat
  private static let radius: CGFloat = 8
  private static let barWidth: CGFloat = 3

  init(textElement: NSTextElement, range: NSTextRange?, decoration: BlockDecoration, indent: CGFloat) {
    self.decoration = decoration
    self.indent = indent
    super.init(textElement: textElement, range: range)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  /// The decoration reaches the column's edges, beyond the text.
  override var renderingSurfaceBounds: CGRect {
    super.renderingSurfaceBounds.union(
      CGRect(x: -layoutFragmentFrame.minX, y: 0, width: columnWidth, height: layoutFragmentFrame.height))
  }

  override func draw(at point: CGPoint, in context: CGContext) {
    context.saveGState()
    drawDecoration(at: point, in: context)
    context.restoreGState()
    super.draw(at: point, in: context)
  }

  private var columnWidth: CGFloat {
    textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
  }

  private func drawDecoration(at point: CGPoint, in context: CGContext) {
    guard let first = textLineFragments.first?.typographicBounds, let last = textLineFragments.last?.typographicBounds
    else { return }
    let left = point.x - layoutFragmentFrame.minX
    let height = layoutFragmentFrame.height
    switch decoration {
    case .codeOnly, .codeFirst, .codeMiddle, .codeLast:
      let opensBlock = decoration == .codeOnly || decoration == .codeFirst
      let closesBlock = decoration == .codeOnly || decoration == .codeLast
      let top = opensBlock ? first.minY - ReadingStyle.codePadding : 0
      let bottom = closesBlock ? last.maxY + ReadingStyle.codePadding * 0.6 : height
      let x = left + indent - ReadingStyle.codePadding
      let rect = CGRect(x: x, y: point.y + top, width: left + columnWidth - x, height: bottom - top)
      context.setFillColor(Tones.well.cgColor)
      context.addPath(
        Self.path(rect, top: opensBlock ? Self.radius : 0, bottom: closesBlock ? Self.radius : 0))
      context.fillPath()
    case .quote:
      context.setFillColor(Tones.line.cgColor)
      context.fill(
        CGRect(
          x: left + indent - ReadingStyle.quoteIndent, y: point.y + first.minY, width: Self.barWidth,
          height: last.maxY - first.minY))
    case .rule:
      context.setFillColor(Tones.line.cgColor)
      context.fill(CGRect(x: left + indent, y: point.y + height / 2, width: columnWidth - indent, height: 1))
    case .tableHeader:
      context.setFillColor(Tones.line.cgColor)
      context.fill(CGRect(x: left + indent, y: point.y + last.maxY + 3, width: columnWidth - indent, height: 1))
    }
  }

  private static func path(_ rect: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: top)
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
      radius: bottom)
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY),
      radius: bottom)
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: top)
    path.closeSubpath()
    return path
  }
}

/// Gives decorated paragraphs a `BlockFragment`; every other paragraph is laid out as usual.
final class BlockLayout: NSObject, NSTextLayoutManagerDelegate {
  func textLayoutManager(
    _ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
    in textElement: NSTextElement
  ) -> NSTextLayoutFragment {
    guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0,
      let raw = paragraph.attributedString.attribute(BlockDecoration.key, at: 0, effectiveRange: nil) as? String,
      let decoration = BlockDecoration(rawValue: raw)
    else { return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange) }
    let style = paragraph.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    return BlockFragment(
      textElement: textElement, range: textElement.elementRange, decoration: decoration,
      indent: style?.headIndent ?? 0)
  }
}
