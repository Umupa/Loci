import AppKit
import Markdown

/// Setting a heading or paragraph with its translation, when there is one to show.
extension MarkdownRenderer {
  /// How close a translation sits under its original when both are shown.
  static let besideGap: CGFloat = 6

  /// Sets `text`, the passage `markup` written out, and its translation as the mode asks: under it in the
  /// interface face and a quieter color, over it with the original quieter, or in its place in its own face.
  func passage(
    _ text: NSAttributedString, of markup: any Markup, in setting: Setting, before: CGFloat = 0,
    after: CGFloat? = nil
  ) {
    guard let translation, translation.mode != .original,
      let translated = translation.passages[Self.source(of: markup)]
    else {
      paragraph(text, in: setting, before: before, after: after)
      return
    }
    let font = (text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil) ?? body
    switch translation.mode {
    case .both where translation.order == .translationAbove:
      let source = NSRange(location: (tracker.original as NSString).length, length: text.length)
      paragraph(
        inline(of: translated, font: font), in: setting, before: before, after: Self.besideGap, as: .above(source))
      var under = setting
      under.marker = nil
      let quiet = NSMutableAttributedString(attributedString: text)
      quiet.addAttribute(.foregroundColor, value: Tones.inkMuted, range: quiet.fullRange)
      paragraph(quiet, in: under, after: after)
    case .both:
      let source = paragraph(text, in: setting, before: before, after: Self.besideGap)
      var under = setting
      under.marker = nil
      let quiet = NSMutableAttributedString(attributedString: inline(of: translated, font: Self.beside(font)))
      quiet.addAttribute(.foregroundColor, value: Tones.inkMuted, range: quiet.fullRange)
      paragraph(quiet, in: under, after: after, as: .beside(source))
    case .translation, .original:
      let source = paragraph(text, in: setting, before: before, after: after, as: .hidden)
      paragraph(inline(of: translated, font: font), in: setting, before: before, after: after, as: .instead(source))
    }
  }

  /// The Markdown a passage is known by, as the host wrote it when it sent the passage to be translated.
  static func source(of markup: any Markup) -> String {
    markup.detachedFromParent.format().trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The interface face a little smaller than `font`, keeping whether it is bold.
  static func beside(_ font: NSFont) -> NSFont {
    let bold = font.fontDescriptor.symbolicTraits.contains(.bold)
    return NSFont.systemFont(ofSize: max(font.pointSize * 0.88, 13), weight: bold ? .semibold : .regular)
  }

  /// The words of a translated heading or paragraph, set like the original's.
  private func inline(of markdown: String, font: NSFont) -> NSAttributedString {
    var node: (any Markup)? = Document(parsing: markdown).child(at: 0)
    while let current = node, !(current is Paragraph || current is Heading) { node = current.child(at: 0) }
    guard let node else { return NSAttributedString(string: markdown, attributes: attributes(font: font)) }
    return inline(node.children, font: font)
  }
}
