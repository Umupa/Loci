import AppKit
import HighlightSwift
import Markdown

/// An item's Markdown, set for reading, with the headings it contains.
///
/// Mermaid diagrams keep their source in the original text so quotes still find it after rendering.
struct ReadingText {
  let string: NSAttributedString
  let headings: [Heading]
  let mermaidSources: Set<String>
  /// Where the shown text differs from the original: translations beside or in place of passages.
  let map: TranslationMap

  /// A heading, with where it starts in `string` in UTF-16 units.
  struct Heading: Hashable {
    let level: Int
    let title: String
    let offset: Int
  }

  /// `byline` goes under the title. Pictures named in `images` by their address in the Markdown stand on lines of
  /// their own; the rest show their description. An article reads in the serif. `translation` shows each
  /// translated passage beside its original or in its place. A link `cite` numbers is a citation: its words stay
  /// plain and a small numbered badge after them opens it.
  @MainActor init(
    markdown: String, byline: NSAttributedString? = nil, images: [String: NSImage] = [:], serif: Bool = false,
    translation: ShownTranslation? = nil, cite: ((URL) -> Int?)? = nil, diagrams: [String: NSImage] = [:]
  ) {
    var renderer = MarkdownRenderer(
      byline: byline, images: images, serif: serif, translation: translation, diagrams: diagrams, cite: cite)
    renderer.render(Document(parsing: markdown))
    string = renderer.finished()
    headings = renderer.headings
    mermaidSources = renderer.mermaidSources
    map = renderer.map
  }

  var plain: String { string.string }
}

/// Walks a Markdown document and appends each block as one or more paragraphs.
@MainActor
struct MarkdownRenderer {
  let byline: NSAttributedString?
  let images: [String: NSImage]
  let serif: Bool
  let translation: ShownTranslation?
  let diagrams: [String: NSImage]
  /// The number of the source a link cites, for a link that is a citation.
  var cite: ((URL) -> Int?)?
  var body: NSFont { serif ? NSFont.serif(ofSize: ReadingStyle.bodySize) : ReadingStyle.body }
  let output = NSMutableAttributedString()
  let tracker = TranslationMap.Builder()
  private(set) var headings: [ReadingText.Heading] = []
  private(set) var mermaidSources: Set<String> = []

  /// Where a block sits: how far it is indented, whether it is inside a quote, and the list marker its
  /// first paragraph starts with.
  struct Setting {
    var indent: CGFloat = 0
    var quoted = false
    var marker: String?
    var listed = false
  }

  mutating func render(_ document: Document) {
    for child in document.children { block(child, in: Setting()) }
  }

  func finished() -> NSAttributedString {
    if output.string.hasSuffix("\n") { output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1)) }
    Serif.setCJKFonts(in: output)
    return output
  }

  var map: TranslationMap { tracker.finished(shownLength: output.length) }

  /// Appends text that is part of the original.
  func put(_ text: NSAttributedString) {
    output.append(text)
    tracker.original.append(text.string)
  }

  private mutating func block(_ markup: any Markup, in setting: Setting) {
    switch markup {
    case let heading as Heading:
      let title = inline(
        heading.children,
        font: heading.level == 1 && serif
          ? NSFont.serif(ofSize: ReadingStyle.articleTitleSize, weight: .semibold) : ReadingStyle.heading(heading.level)
      )
      headings.append(ReadingText.Heading(level: heading.level, title: title.string, offset: output.length))
      let spacing = ReadingStyle.headingSpacing(heading.level)
      let first = output.length == 0
      let underTitle = first && heading.level == 1 ? byline : nil
      passage(
        title, of: heading, in: setting, before: first ? 0 : spacing.before,
        after: underTitle == nil ? spacing.after : 12)
      if let underTitle { self.paragraph(underTitle, in: setting, after: 30) }
    case let paragraph as Paragraph:
      if paragraph.childCount == 1, let picture = paragraph.child(at: 0) as? Markdown.Image,
        let source = picture.source, let image = images[source]
      {
        figure(image, in: setting)
        return
      }
      if let latex = Formula.display(in: paragraph.plainText), formulaBlock(latex, in: setting) { return }
      passage(inline(paragraph.children, font: body), of: paragraph, in: setting)
    case let code as CodeBlock:
      if let language = code.language?.lowercased() {
        if language == "mermaid" {
          mermaidSources.insert(code.code)
          if let image = diagrams[code.code] {
            diagram(image, source: code.code, in: setting)
            return
          }
        }
        if Formula.blockLanguages.contains(language), formulaBlock(code.code, in: setting) { return }
      }
      codeBlock(code.code, language: code.language, in: setting)
    case let html as HTMLBlock:
      codeBlock(html.rawHTML, language: "html", in: setting)
    case let list as UnorderedList:
      for item in list.listItems { listItem(item, marker: "•", in: setting) }
      if !setting.listed { endList() }
    case let list as OrderedList:
      for (index, item) in list.listItems.enumerated() {
        listItem(item, marker: "\(Int(list.startIndex) + index).", in: setting)
      }
      if !setting.listed { endList() }
    case let quote as BlockQuote:
      var inside = setting
      inside.indent += ReadingStyle.quoteIndent
      inside.quoted = true
      for child in quote.children { block(child, in: inside) }
    case is ThematicBreak:
      put(
        NSAttributedString(
          string: "\n",
          attributes: attributes(font: ReadingStyle.body, style: style(in: setting), decoration: .rule)))
    case let table as Markdown.Table:
      self.table(table, in: setting)
    default:
      for child in markup.children { block(child, in: setting) }
    }
  }

  private mutating func listItem(_ item: ListItem, marker: String, in setting: Setting) {
    var inside = setting
    inside.indent += ReadingStyle.listIndent
    inside.listed = true
    switch item.checkbox {
    case .checked: inside.marker = "☑"
    case .unchecked: inside.marker = "☐"
    case nil: inside.marker = marker
    }
    for child in item.children {
      block(child, in: inside)
      inside.marker = nil
    }
  }

  @discardableResult func paragraph(
    _ text: NSAttributedString, in setting: Setting, before: CGFloat = 0, after: CGFloat? = nil,
    as part: TranslationMap.Part = .original
  ) -> NSRange {
    let line = NSMutableAttributedString()
    let paragraphStyle = style(
      in: setting, spacing: after ?? (setting.listed ? ReadingStyle.itemSpacing : ReadingStyle.paragraphSpacing))
    paragraphStyle.paragraphSpacingBefore = before
    if let marker = setting.marker {
      paragraphStyle.firstLineHeadIndent = setting.indent - ReadingStyle.listIndent
      paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: setting.indent)]
      line.append(NSAttributedString(string: marker + "\t", attributes: attributes(font: body)))
    }
    line.append(text)
    line.append(NSAttributedString(string: "\n", attributes: attributes(font: body)))
    line.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: line.length))
    if setting.quoted {
      line.addAttribute(BlockDecoration.key, value: BlockDecoration.quote.rawValue, range: line.fullRange)
      line.addAttribute(.foregroundColor, value: Tones.inkMuted, range: line.fullRange)
    }
    return tracker.add(line, as: part, to: output)
  }

  /// Items sit close together; the list as a whole is spaced like a paragraph.
  private func endList() {
    guard output.length > 0,
      let last = output.attribute(.paragraphStyle, at: output.length - 1, effectiveRange: nil) as? NSParagraphStyle,
      let widened = last.mutableCopy() as? NSMutableParagraphStyle
    else { return }
    widened.paragraphSpacing = max(widened.paragraphSpacing, ReadingStyle.paragraphSpacing)
    let paragraph = (output.string as NSString).paragraphRange(for: NSRange(location: output.length - 1, length: 0))
    output.addAttribute(.paragraphStyle, value: widened, range: paragraph)
  }

  /// A picture on a line of its own, as wide as the column at most, with rounded corners.
  private func figure(_ image: NSImage, in setting: Setting) {
    let width = min(image.size.width, Typography.readingWidth - setting.indent)
    let size = CGSize(width: width, height: image.size.height * width / max(image.size.width, 1))
    let rounded = NSImage(size: size, flipped: false) { frame in
      NSBezierPath(roundedRect: frame, xRadius: Radius.group, yRadius: Radius.group).addClip()
      image.draw(in: frame)
      return true
    }
    let attachment = NSTextAttachment()
    attachment.image = rounded
    attachment.bounds = CGRect(origin: .zero, size: size)
    let line = NSMutableAttributedString(attachment: attachment)
    line.append(NSAttributedString(string: "\n", attributes: attributes(font: body)))
    let paragraphStyle = style(in: setting)
    paragraphStyle.paragraphSpacingBefore = 4
    paragraphStyle.paragraphSpacing = 24
    line.addAttribute(.paragraphStyle, value: paragraphStyle, range: line.fullRange)
    put(line)
  }

  /// A formula on a line of its own, centered. Returns `false` when it cannot be set, so it shows as code.
  private func formulaBlock(_ latex: String, in setting: Setting) -> Bool {
    guard let formula = Formula.attachment(latex, display: true, size: ReadingStyle.bodySize) else { return false }
    let line = NSMutableAttributedString(attributedString: formula)
    line.append(NSAttributedString(string: "\n", attributes: attributes(font: body)))
    let paragraphStyle = style(in: setting)
    paragraphStyle.alignment = .center
    paragraphStyle.paragraphSpacingBefore = ReadingStyle.paragraphSpacing / 2
    line.addAttribute(.paragraphStyle, value: paragraphStyle, range: line.fullRange)
    put(line)
    return true
  }

  private func diagram(_ image: NSImage, source: String, in setting: Setting) {
    let line = source.hasSuffix("\n") ? source : source + "\n"
    let original = tracker.add(NSAttributedString(string: line), as: .hidden, to: output)
    let attachment = MermaidAttachment(image: image, source: String(line.dropLast()))
    var setting = setting
    setting.marker = nil
    paragraph(NSAttributedString(attachment: attachment), in: setting, as: .instead(original))
  }

  private func codeBlock(_ code: String, language: String?, in setting: Setting) {
    let start = output.length
    var lines = code.split(separator: "\n", omittingEmptySubsequences: false)
    if lines.last?.isEmpty == true { lines.removeLast() }
    for (index, line) in lines.enumerated() {
      let decoration = BlockDecoration.code(line: index, of: lines.count)
      let paragraphStyle = style(in: setting, spacing: 0, lineSpacing: 3)
      paragraphStyle.firstLineHeadIndent = setting.indent + ReadingStyle.codePadding
      paragraphStyle.headIndent = setting.indent + ReadingStyle.codePadding
      paragraphStyle.tailIndent = -ReadingStyle.codePadding
      paragraphStyle.lineBreakMode = .byCharWrapping
      if decoration == .codeFirst || decoration == .codeOnly {
        paragraphStyle.paragraphSpacingBefore = ReadingStyle.codePadding
      }
      if decoration == .codeLast || decoration == .codeOnly {
        paragraphStyle.paragraphSpacing = ReadingStyle.paragraphSpacing + ReadingStyle.codePadding
      }
      put(
        NSAttributedString(
          string: line + "\n",
          attributes: attributes(font: ReadingStyle.code, style: paragraphStyle, decoration: decoration)))
    }
    for (range, color) in CodeColors.colors(of: code, language: language) {
      let shifted = NSRange(location: start + range.location, length: range.length)
      guard NSMaxRange(shifted) <= output.length else { continue }
      output.addAttribute(.foregroundColor, value: color, range: shifted)
    }
  }

  private func table(_ table: Markdown.Table, in setting: Setting) {
    let header = Array(table.head.cells.map { inline($0.children, font: ReadingStyle.bold(body)) })
    guard !header.isEmpty else { return }
    let rows = [header] + table.body.rows.map { row in row.cells.map { inline($0.children, font: body) } }
    let source = rows.map { $0.map(\.string).joined(separator: "\t") }.joined(separator: "\n") + "\n"
    let original = tracker.add(NSAttributedString(string: source), as: .hidden, to: output)
    let attachment = ReaderTableAttachment(
      rows: rows, source: String(source.dropLast()), original: original, font: body)
    var setting = setting
    setting.marker = nil
    paragraph(NSAttributedString(attachment: attachment), in: setting, as: .instead(original))
  }

  func inline(_ children: MarkupChildren, font: NSFont) -> NSAttributedString {
    let text = NSMutableAttributedString()
    for child in children { text.append(inline(child, font: font)) }
    return text
  }

  private func inline(_ markup: any Markup, font: NSFont) -> NSAttributedString {
    switch markup {
    case let text as Markdown.Text:
      let run = NSMutableAttributedString()
      for piece in Formula.split(text.string) {
        if piece.isFormula, let formula = Formula.attachment(piece.text, display: false, size: font.pointSize) {
          run.append(formula)
        } else {
          let written = piece.isFormula ? "$\(piece.text)$" : piece.text
          run.append(NSAttributedString(string: written, attributes: attributes(font: font)))
        }
      }
      return run
    case is SoftBreak:
      return NSAttributedString(string: " ", attributes: attributes(font: font))
    case is LineBreak:
      return NSAttributedString(string: "\u{2028}", attributes: attributes(font: font))
    case let code as InlineCode:
      var codeAttributes = attributes(font: NSFont.monospacedSystemFont(ofSize: font.pointSize - 1.5, weight: .regular))
      codeAttributes[.backgroundColor] = Tones.well
      return NSAttributedString(string: code.code, attributes: codeAttributes)
    case let strong as Strong:
      return inline(strong.children, font: ReadingStyle.bold(font))
    case let emphasis as Emphasis:
      return inline(emphasis.children, font: ReadingStyle.italic(font))
    case let strike as Strikethrough:
      let text = NSMutableAttributedString(attributedString: inline(strike.children, font: font))
      text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: text.fullRange)
      return text
    case let link as Markdown.Link:
      let text = NSMutableAttributedString(attributedString: inline(link.children, font: font))
      if let destination = link.destination, let url = URL(string: destination) {
        if let number = cite?(url) {
          text.append(Citation.badge(number, opening: url, beside: font))
        } else {
          text.addAttribute(.link, value: url, range: text.fullRange)
        }
      }
      return text
    case let image as Markdown.Image:
      var imageAttributes = attributes(font: font)
      imageAttributes[.foregroundColor] = Tones.inkMuted
      return NSAttributedString(string: image.plainText, attributes: imageAttributes)
    case let html as InlineHTML:
      return NSAttributedString(string: html.rawHTML, attributes: attributes(font: font))
    default:
      let text = NSMutableAttributedString()
      for child in markup.children { text.append(inline(child, font: font)) }
      return text
    }
  }

  private func style(
    in setting: Setting, spacing: CGFloat = ReadingStyle.paragraphSpacing,
    lineSpacing: CGFloat = ReadingStyle.lineSpacing
  ) -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = lineSpacing
    style.paragraphSpacing = spacing
    style.firstLineHeadIndent = setting.indent
    style.headIndent = setting.indent
    return style
  }

  func attributes(
    font: NSFont, style: NSParagraphStyle? = nil, decoration: BlockDecoration? = nil
  ) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Tones.ink]
    if let style { attributes[.paragraphStyle] = style }
    if let decoration { attributes[BlockDecoration.key] = decoration.rawValue }
    return attributes
  }
}

extension NSAttributedString {
  var fullRange: NSRange { NSRange(location: 0, length: length) }
}
