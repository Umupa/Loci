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
  /// Tags and small badges, and a lesson's row in the sidebar.
  static let small: CGFloat = 7
  /// A row in the sidebar.
  static let row: CGFloat = 8
  /// Grouped rows in settings, code blocks and steps of a reply.
  static let group: CGFloat = 12
  /// Cards and blocks inside panels. Inputs and segmented controls are capsules.
  static let card: CGFloat = 14
  /// A message bubble and the composer.
  static let bubble: CGFloat = 20
  /// A cover in a list, and a menu's rows.
  static let thumbnail: CGFloat = 6
  /// A cover on its own, and the video player.
  static let cover: CGFloat = 10
  /// A push button, as System Settings draws one.
  static let push: CGFloat = 6
}

enum Size {
  static let sidebarIdeal: CGFloat = 236
  /// Room at the top of the sidebar for the window's close, minimize and zoom buttons.
  static let trafficLights: CGFloat = 36
  /// Where the close button sits: inside the floating sidebar, as far from its edge as the panel is from the
  /// window's.
  static let windowButtons = CGPoint(x: 22, y: 22)
  static let cardMinimumWidth: CGFloat = 200
  static let cardThumbnailRatio: CGFloat = 16 / 9
  static let promptMaximumWidth: CGFloat = 560
  static let promptHeight: CGFloat = 44
  static let panelWidth: CGFloat = 384
  /// The strip along a pane's edge that drags it wider.
  static let resizer: CGFloat = 8
  /// Where the button that brings the sidebar back sits, clear of the window's buttons.
  static let sidebarToggleLeading: CGFloat = 84
  /// The narrowest the reading column gets when the panel beside it is dragged wide.
  static let readerMinimum: CGFloat = 320
  /// The row at the top of the panel beside the text.
  static let panelHeader: CGFloat = 52
  static let termCardWidth: CGFloat = 280
  static let thoughtFieldWidth: CGFloat = 300
  static let toolOutputHeight: CGFloat = 220
  static let rowHeight: CGFloat = 30
  static let lessonRowHeight: CGFloat = 26
  static let lessonGlyph: CGFloat = 12
  static let iconButton: CGFloat = 28
  static let avatarSmall: CGFloat = 20
  static let avatarTiny: CGFloat = 16
  static let avatarMedium: CGFloat = 24
  static let avatarLarge: CGFloat = 64
  static let thumbnailSymbol: CGFloat = 30
  static let emptySymbol: CGFloat = 44
  static let sendButton: CGFloat = 28
  static let problemListWidth: CGFloat = 380
  static let settingsWidth: CGFloat = 600
  static let wideSettingsWidth: CGFloat = 640
  static let hairline: CGFloat = 0.5
  /// From the top of the window to the first line of a lesson; the title sits within 40 of the edge.
  static let readingTop: CGFloat = 34
  static let windowMinimum = CGSize(width: 720, height: 460)

  /// The library's covers: a row of the ones being watched, over a list.
  static let shelfHeight: CGFloat = 214
  static let shelfGap: CGFloat = 16
  /// The first cover on the shelf is this much wider than the other two.
  static let shelfLead: CGFloat = 1.35
  static let listThumbnail: CGFloat = 84
  static let listStatus: CGFloat = 250
  static let meter: CGFloat = 96
  static let meterHeight: CGFloat = 4
  static let pushHeight: CGFloat = 22
  /// The empty library's field, as on the start page.
  static let startFieldWidth: CGFloat = 600

  /// The panel beside a video, a podcast or an article.
  static let mediaPanel: CGFloat = 372
  static let scrubberHeight: CGFloat = 22
  static let knob: CGFloat = 12
  static let diamond: CGFloat = 7
  static let controlButton: CGFloat = 32
  static let podcastCover: CGFloat = 300
  static let podcastColumn: CGFloat = 460
  static let podcastPlay: CGFloat = 52
  static let podcastButton: CGFloat = 38
  /// The column a transcript keeps for the time of each sentence.
  static let timeColumn: CGFloat = 40

  static let addressHeight: CGFloat = 32
  static let primaryHeight: CGFloat = 30
  static let browserField = CGSize(width: 560, height: 52)
  static let siteTile: CGFloat = 58
  static let videoPicker: CGFloat = 372
  static let pickerThumbnail: CGFloat = 96

  static let settingsTile: CGFloat = 38
  static let componentTile: CGFloat = 28
  static let radio: CGFloat = 16
  static let dot: CGFloat = 6
}

/// How things move. Selection and hover change at once and use none of these.
enum Motion {
  static let standard = Animation.spring(duration: 0.35, bounce: 0.12)
  static let quick = Animation.snappy(duration: 0.2)
  /// Opening and closing a course in the sidebar, or the panel beside the text.
  static let fold = Animation.spring(duration: 0.3, bounce: 0.1)
  /// A new message or card rising into place.
  static let rise = Animation.spring(response: 0.28, dampingFraction: 0.67)
  static let riseDistance: CGFloat = 10
  /// How far a button shrinks while pressed.
  static let pressScale: CGFloat = 0.97
  /// A passage or card just jumped to keeps its flash this long, then fades.
  static let flashHold = Duration.milliseconds(380)
  static let flashFade = Animation.easeOut(duration: 1)
  /// The flash in the reader fades in steps this long, over about a second.
  static let flashFadeStep = Duration.milliseconds(50)
  /// A rebuild finishing sooner than this is not shown at all, so nothing flickers.
  static let quietDelay = Duration.milliseconds(300)
}
