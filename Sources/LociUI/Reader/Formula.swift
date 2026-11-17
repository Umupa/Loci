import AppKit
import SwiftMath

/// A LaTeX formula set by SwiftMath and placed in the text as an image, on its own line or among words.
enum Formula {
  /// Languages of a fenced code block that holds a formula instead of code.
  static let blockLanguages: Set<String> = ["math", "latex", "tex"]

  /// The formula as one attachment character, or `nil` when SwiftMath cannot read it.
  static func attachment(_ latex: String, display: Bool, size: CGFloat) -> NSAttributedString? {
    var image = MathImage(
      latex: latex.trimmingCharacters(in: .whitespacesAndNewlines), fontSize: display ? size * 1.15 : size,
      textColor: Tones.ink, labelMode: display ? .display : .text, textAlignment: .left)
    let (error, rendered, layout) = image.asImage()
    guard error == nil, let rendered, let layout else { return nil }
    let attachment = NSTextAttachment()
    attachment.image = rendered
    attachment.bounds = CGRect(
      x: 0, y: -layout.descent, width: rendered.size.width, height: rendered.size.height)
    return NSAttributedString(attachment: attachment)
  }

  /// `$$ … $$` written as a paragraph of its own.
  static func display(in paragraph: String) -> String? {
    let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 4, trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$") else { return nil }
    return String(trimmed.dropFirst(2).dropLast(2))
  }

  /// Pieces of a run of text: words as written, and `$ … $` formulas. A dollar sign followed or preceded by
  /// a space is a price, not a formula.
  static func split(_ text: String) -> [(text: String, isFormula: Bool)] {
    var pieces: [(String, Bool)] = []
    var rest = Substring(text)
    while let match = rest.firstMatch(of: /\$([^\s$](?:[^$\n]*[^\s$])?)\$/) {
      if match.range.lowerBound > rest.startIndex { pieces.append((String(rest[..<match.range.lowerBound]), false)) }
      pieces.append((String(match.1), true))
      rest = rest[match.range.upperBound...]
    }
    if !rest.isEmpty { pieces.append((String(rest), false)) }
    return pieces
  }
}
