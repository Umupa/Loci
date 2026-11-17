import SwiftUI

/// Every spacing in the interface is one of these.
enum Spacing {
  static let xxs: CGFloat = 4
  static let xs: CGFloat = 8
  static let s: CGFloat = 12
  static let m: CGFloat = 16
  static let l: CGFloat = 24
  static let xl: CGFloat = 32
  static let xxl: CGFloat = 48
}

enum Radius {
  /// Tags and small badges.
  static let small: CGFloat = 7
  /// Cards, selected rows and blocks inside panels. Inputs and segmented controls are capsules.
  static let card: CGFloat = 13
}

enum Size {
  static let sidebarMinimum: CGFloat = 180
  static let sidebarIdeal: CGFloat = 220
  static let cardMinimumWidth: CGFloat = 200
  static let cardThumbnailRatio: CGFloat = 16 / 9
  static let promptMaximumWidth: CGFloat = 560
  static let promptHeight: CGFloat = 44
  static let panelWidth: CGFloat = 260
  static let termCardWidth: CGFloat = 280
  static let toolOutputHeight: CGFloat = 220
  static let avatarSmall: CGFloat = 18
  static let avatarMedium: CGFloat = 24
  static let avatarLarge: CGFloat = 64
  static let thumbnailSymbol: CGFloat = 30
  static let emptySymbol: CGFloat = 44
  static let avatarGlyphRatio: CGFloat = 0.5
  static let sendButton: CGFloat = 28
  static let problemListWidth: CGFloat = 380
  static let settingsWidth: CGFloat = 520
  static let hairline: CGFloat = 0.5
  static let windowMinimum = CGSize(width: 720, height: 460)
}

/// How things move. Selection and hover change at once and use none of these.
enum Motion {
  static let standard = Animation.spring(duration: 0.35, bounce: 0.12)
  static let quick = Animation.snappy(duration: 0.2)
  /// A rebuild finishing sooner than this is not shown at all, so nothing flickers.
  static let quietDelay = Duration.milliseconds(300)
}
