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
  /// A small button's wash, and a chip under the input field.
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
  /// The round corners of a message, and the tighter ones where it meets the next from the same speaker.
  static let message: CGFloat = 18
  static let messageJoin: CGFloat = 6
  /// The field at the foot of a conversation.
  static let composer: CGFloat = 22
  /// A row of the sidebar, and Loci's own row at its top.
  static let sidebarRow: CGFloat = 9
  static let sidebarLoci: CGFloat = 12
  /// A sheet dropped over the window.
  static let sheet: CGFloat = 24
}

enum Size {
  static let sidebarIdeal: CGFloat = 228
  /// Room at the top of the sidebar for the window's close, minimize and zoom buttons.
  static let trafficLights: CGFloat = 36
  /// Where the close button sits: inside the floating sidebar, as far from its edge as the panel is from the
  /// window's.
  static let windowButtons = CGPoint(x: 22, y: 22)
  static let cardMinimumWidth: CGFloat = 200
  static let cardThumbnailRatio: CGFloat = 16 / 9
  static let panelWidth: CGFloat = 384
  static let updateButton: CGFloat = 28
  /// The strip along a pane's edge that drags it wider.
  static let resizer: CGFloat = 8
  /// Where the button that brings the sidebar back sits, clear of the window's buttons.
  static let sidebarToggleLeading: CGFloat = 84
  /// The narrowest the reading column gets when the panel beside it is dragged wide.
  static let readerMinimum: CGFloat = 320
  static let thoughtFieldWidth: CGFloat = 300
  static let toolOutputHeight: CGFloat = 220
  static let iconButton: CGFloat = 28
  static let avatarTiny: CGFloat = 16
  static let thumbnailSymbol: CGFloat = 30
  static let emptySymbol: CGFloat = 44
  static let sendButton: CGFloat = 30
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
  /// What went wrong, told in full on an item's own page.
  static let jobDetail: CGFloat = 320
  static let meter: CGFloat = 96
  static let meterHeight: CGFloat = 4
  static let pushHeight: CGFloat = 22

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
  static let linkField: CGFloat = 44
  static let siteTile: CGFloat = 58
  static let videoPicker: CGFloat = 372
  static let pickerThumbnail: CGFloat = 96

  static let settingsTile: CGFloat = 38
  static let componentTile: CGFloat = 28
  static let radio: CGFloat = 16
  static let dot: CGFloat = 6

  /// From the bottom of the sidebar to the menu of Macs that rises from its foot.
  static let machineMenuLift: CGFloat = 40
  /// A row of a grouped list, in settings and in sheets.
  static let settingsRow: CGFloat = 44
  static let machineGlyph: CGFloat = 54
  static let pairingCode: CGFloat = 44
  static let remoteSheetWidth: CGFloat = 400
  /// From the top of the window to a sheet dropped over it.
  static let remoteSheetTop: CGFloat = 64
  /// Where the field of a conversation would be, while its Mac is offline.
  static let offlineLine: CGFloat = 56
}

/// How things move. Selection and hover change at once and use none of these.
enum Motion {
  static let standard = Animation.spring(duration: 0.35, bounce: 0.12)
  static let quick = Animation.snappy(duration: 0.2)
  /// Opening and closing the sidebar, or the panel beside the text.
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
  /// A message, event or card arriving: it rises into place as it fades in.
  static let arrive = Animation.timingCurve(0.28, 0.67, 0.32, 1, duration: 0.45)
  /// How faint a breathing dot gets before it brightens again.
  static let breathLow = 0.3
  /// A rebuild finishing sooner than this is not shown at all, so nothing flickers.
  static let quietDelay = Duration.milliseconds(300)
}
