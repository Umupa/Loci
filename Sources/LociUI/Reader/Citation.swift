import AppKit

/// A citation in reading text: a small amber disc with the cited source's number, raised a little off the line,
/// that opens the place it cites.
enum Citation {
  static func badge(_ number: Int, opening url: URL, beside font: NSFont) -> NSAttributedString {
    let side = (font.pointSize * 0.94).rounded()
    let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
      Tones.tint.setFill()
      NSBezierPath(ovalIn: rect).fill()
      let label = NSAttributedString(
        string: "\(number)",
        attributes: [
          .font: NSFont.monospacedSystemFont(ofSize: side * 0.6, weight: .semibold),
          .foregroundColor: Tones.citationInk,
        ])
      let size = label.size()
      label.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
      return true
    }
    let attachment = NSTextAttachment()
    attachment.image = image
    attachment.bounds = CGRect(x: 0, y: font.capHeight - side * 0.62, width: side, height: side)
    let badge = NSMutableAttributedString(string: "\u{202F}")
    let disc = NSMutableAttributedString(attachment: attachment)
    disc.addAttribute(.link, value: url, range: disc.fullRange)
    disc.addAttribute(.toolTip, value: url.absoluteString, range: disc.fullRange)
    badge.append(disc)
    return badge
  }
}
