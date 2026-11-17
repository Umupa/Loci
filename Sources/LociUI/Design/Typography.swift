import AppKit
import SwiftUI

/// The type scale. Interface and reading text are the system sans-serif; titles a reader dwells on and quoted
/// words are the system serif (New York, and Songti for Chinese). macOS has no dynamic type sizes, so sizes
/// are fixed points.
enum Typography {
  /// The name at the top of an item's page and of a settings page.
  static let title = Font.system(size: 20, weight: .bold)
  /// The start page's question.
  static let prompt = Font.system(size: 15)
  static let body = Font.system(size: 13)
  static let bodyEmphasis = Font.system(size: 13, weight: .medium)
  /// A lesson in the sidebar's course list.
  static let lessonRow = Font.system(size: 12.5)
  /// Above a group of rows in the sidebar.
  static let sectionLabel = Font.system(size: 11, weight: .semibold)
  /// The words of a segmented control or a chip.
  static let control = Font.system(size: 12, weight: .medium)
  static let caption = Font.system(size: 11)
  static let mono = Font.system(size: 11).monospaced()

  /// A lesson's title.
  static let lessonTitle = Font.system(size: 32, weight: .semibold, design: .serif)
  /// A heading inside a lesson.
  static let sectionTitle = Font.system(size: 20, weight: .semibold, design: .serif)
  /// A mentor's name on its page.
  static let mentorName = Font.system(size: 34, weight: .semibold, design: .serif)
  /// A course's title on its cover.
  static let coverTitle = Font.system(size: 19, weight: .semibold, design: .serif)
  /// A heading in a mentor's reply.
  static let replyTitle = Font.system(size: 18, weight: .semibold, design: .serif)
  /// Words quoted from the text, in a message or a card.
  static let quote = Font.system(size: 13, design: .serif)
  /// The words of a highlight on its card.
  static let highlightQuote = Font.system(size: 14, design: .serif)

  /// Plain text of items and lessons.
  static let reading = Font.system(size: readingSize)
  static let readingSize: CGFloat = 16
  static let readingWidth: CGFloat = 564
}

extension NSFont {
  /// The system serif, as `Font.Design.serif` is in SwiftUI.
  static func serif(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let system = NSFont.systemFont(ofSize: size, weight: weight)
    return system.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? system
  }
}
