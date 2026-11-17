import SwiftUI

/// The type scale. Interface and reading text are both the system sans-serif; macOS has no dynamic type
/// sizes, so sizes are fixed points.
enum Typography {
  /// The name at the top of a mentor's or an item's page.
  static let title = Font.system(size: 22, weight: .semibold)
  /// The start page's question.
  static let prompt = Font.system(size: 15)
  static let body = Font.system(size: 13)
  static let bodyEmphasis = Font.system(size: 13, weight: .medium)
  /// Plain text of items and lessons.
  static let reading = Font.system(size: 15)
  static let readingLineSpacing: CGFloat = 10
  static let readingWidth: CGFloat = 680
  static let caption = Font.system(size: 11)
  static let mono = Font.system(size: 11).monospaced()
}
