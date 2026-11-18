import AppKit
import SwiftUI

/// The type scale. Interface and reading text are the system sans-serif; titles a reader dwells on and quoted
/// words are the system serif (New York, and Songti for Chinese). macOS has no dynamic type sizes, so sizes
/// are fixed points.
enum Typography {
  /// The name at the top of an item's page and of a settings page.
  static let title = Font.system(size: 20, weight: .bold)
  static let body = Font.system(size: 13)
  static let bodyEmphasis = Font.system(size: 13, weight: .medium)
  /// Above a group of rows in the sidebar.
  static let sectionLabel = Font.system(size: 11, weight: .semibold)
  /// The words of a segmented control or a chip.
  static let control = Font.system(size: 12, weight: .medium)
  static let caption = Font.system(size: 11)
  static let mono = Font.system(size: 11).monospaced()

  /// Words quoted from the text, in a message or a card.
  static let quote = Serif.Face(size: 13)
  /// The words of a highlight on its card.
  static let highlightQuote = Serif.Face(size: 14)

  /// An item's title in the library's list.
  static let rowTitle = Serif.Face(size: 14, weight: .semibold)
  /// An item's title over its cover on the shelf.
  static let shelfTitle = Serif.Face(size: 17, weight: .semibold)
  /// The title under a player.
  static let mediaTitle = Serif.Face(size: 22, weight: .semibold)
  /// A chapter's name between the sentences of a transcript.
  static let chapterTitle = Serif.Face(size: 15.5, weight: .semibold)
  /// A sentence of a transcript, and its translation under it.
  static let transcript = Font.system(size: 14)
  static let transcriptTranslation = Font.system(size: 13)
  /// The clock under a player.
  static let clock = Font.system(size: 11.5).monospaced()
  /// A small button's words.
  static let button = Font.system(size: 12.5, weight: .medium)
  static let buttonStrong = Font.system(size: 13, weight: .semibold)

  /// Plain text of items.
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
