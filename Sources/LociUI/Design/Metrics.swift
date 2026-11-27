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
  /// A lane of panels on the main page, and the conversation lifted while it moves.
  static let lane: CGFloat = 24
  /// A message bubble and the composer.
  static let bubble: CGFloat = 20
  /// A next-up card.
  static let nextUpCard: CGFloat = 24
  /// A cover in a list, and a menu's rows.
  static let thumbnail: CGFloat = 6
  /// A cover on its own, and the video player.
  static let cover: CGFloat = 10
  /// A push button, as System Settings draws one.
  static let push: CGFloat = 6
  /// A message in a conversation.
  static let message: CGFloat = 24
  /// The field at the foot of a conversation, a capsule while it holds one line.
  static let composer: CGFloat = 24
  /// A row of the sidebar.
  static let sidebarRow: CGFloat = 9
  /// A sheet dropped over the window.
  static let sheet: CGFloat = 24
  static let importSheet: CGFloat = 22
  /// A cover in the gallery.
  static let galleryCover: CGFloat = 11
  /// The window's own corners, which the light around its edge follows.
  static let window: CGFloat = 18
  /// A panel beside the main conversation, and the blocks inside it.
  static let panel: CGFloat = 26
  static let panelBlock: CGFloat = 12
}

enum Size {
  static let sidebarIdeal: CGFloat = 228
  /// Room at the top of the sidebar for the window's close, minimize and zoom buttons.
  static let trafficLights: CGFloat = 36
  /// Where the close button sits: inside the floating sidebar, as far from its edge as the panel is from the
  /// window's.
  static let windowButtons = CGPoint(x: 22, y: 22)
  static let cardMinimumWidth: CGFloat = 200
  static let panelWidth: CGFloat = 384
  static let updateButton: CGFloat = 28
  /// The strip along a pane's edge that drags it wider.
  static let resizer: CGFloat = 8
  /// Where the button that brings the sidebar back sits, clear of the window's buttons.
  static let sidebarToggleLeading: CGFloat = 84
  /// The narrowest the reading column gets when the panel beside it is dragged wide.
  static let readerMinimum: CGFloat = 320
  static let thoughtFieldWidth: CGFloat = 240
  /// The tallest a picture stands on a highlight's card.
  static let notePicture: CGFloat = 160
  /// The largest a picture opened from a highlight gets.
  static let openedPicture: CGFloat = 900
  /// The cover beside the thought on a whole item.
  static let wholeCover = CGSize(width: 34, height: 44)
  static let iconButton: CGFloat = 28
  static let avatarTiny: CGFloat = 16
  static let emptySymbol: CGFloat = 44
  /// The round buttons in the field at the foot of a conversation.
  static let composerButton: CGFloat = 32
  static let composerHeight: CGFloat = 48
  /// The widest a message gets beside something read, and in the main conversation at its widest.
  static let messageWidest: CGFloat = 424
  static let talkMessageWidest: CGFloat = 540
  /// The room between one message and the next.
  static let messageGap: CGFloat = 10
  static let problemListWidth: CGFloat = 380
  static let settingsWidth: CGFloat = 600
  static let wideSettingsWidth: CGFloat = 640
  static let hairline: CGFloat = 0.5
  /// From the top of the window to the first line of a lesson; the title sits within 40 of the edge.
  static let readingTop: CGFloat = 34
  static let windowMinimum = CGSize(width: 720, height: 460)

  /// What went wrong, told in full on an item's own page.
  static let jobDetail: CGFloat = 320
  static let taskDock: CGFloat = 540
  static let preparingWidth: CGFloat = 880
  static let meter: CGFloat = 96
  static let meterHeight: CGFloat = 4
  static let pushHeight: CGFloat = 22

  /// The panel beside a video, a podcast or an article.
  static let mediaPanel: CGFloat = 372
  static let scrubberHeight: CGFloat = 22
  static let knob: CGFloat = 12
  static let controlButton: CGFloat = 32
  /// The cover at the top of an episode's page.
  static let episodeCover: CGFloat = 112
  /// The column an episode's page reads in.
  static let episodeColumn: CGFloat = 620
  static let episodePlay: CGFloat = 36
  /// The play bar along the foot of the window, and the cover in it.
  static let playBar = CGSize(width: 640, height: 56)
  static let playBarCover: CGFloat = 40
  /// A video left while playing, in a corner of the window.
  static let videoCorner = CGSize(width: 320, height: 180)
  /// The column a transcript keeps for the time of each sentence.
  static let timeColumn: CGFloat = 40

  static let addressHeight: CGFloat = 32
  static let tabHeight: CGFloat = 28
  static let primaryHeight: CGFloat = 30
  static let largeButtonHeight: CGFloat = 34
  static let browserField = CGSize(width: 560, height: 52)
  static let linkField: CGFloat = 44
  static let siteTile: CGFloat = 58
  static let keepList: CGFloat = 340

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
  static let importSheetWidth: CGFloat = 500
  static let importCover = CGSize(width: 132, height: 82.5)
  /// From the top of the window to a sheet dropped over it.
  static let remoteSheetTop: CGFloat = 64
  /// Where the field of a conversation would be, while its Mac is offline.
  static let offlineLine: CGFloat = 56

  /// The tallest a panel's rows stand until it is opened out.
  static let panelTallest: CGFloat = 300
  /// The room over the main page's lanes, where the window's buttons and the conversation's grip sit.
  static let boardTop: CGFloat = 52
  /// How far above the conversation its grip sits, in the room over the lanes and below the strip that drags
  /// the window.
  static let gripLift: CGFloat = 22
  /// The panels of a folded lane, opened over the page.
  static let railSheet: CGFloat = 372
  /// A panel's mark on a folded lane.
  static let railMark: CGFloat = 30
  /// A project's seal in the project bar, and the large one over a new project's field.
  static let seal: CGFloat = 22
  static let sealLarge: CGFloat = 64
  /// How far above the middle of the page a new project's field sits.
  static let newProjectLift: CGFloat = 76
  /// The room kept on each side of the project bar for the buttons in the page's corners.
  static let projectBarClearance: CGFloat = 84
  /// The widest the project bar spreads on wide windows before folding overflow into its list.
  static let projectBarWidest: CGFloat = 580
  /// The widest an open project's name spreads in the project bar.
  static let projectNameWidest: CGFloat = 180
  /// The narrowest it yields to before overflow projects fold out of the bar.
  static let projectNameNarrow: CGFloat = 76
  /// The least a question card is tall, its button at its foot; any card is taken as this tall until it has
  /// laid out at its own height.
  static let nextUpCard: CGFloat = 96
  /// The room over the lanes when the project bar is there: the bar, then the conversation's grip.
  static let projectBarRoom: CGFloat = 78
  /// The room over the panel lanes when the project bar is there: only the bar, so the first card or panel
  /// starts just under it, as panels have no grip above them.
  static let panelRoom: CGFloat = 56
  static let railSheetTallest: CGFloat = 640
  /// A site's small round mark before a panel's title.
  static let siteMark: CGFloat = 22
  static let panelCover: CGFloat = 40
}

/// How things move. Selection and hover change at once and use none of these.
enum Motion {
  static let standard = Animation.spring(duration: 0.35, bounce: 0.12)
  static let quick = Animation.snappy(duration: 0.2)
  /// The slider pill gliding between tabs in the project bar.
  static let slider = Animation.spring(duration: 0.28, bounce: 0.08)
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
  /// An item dropping into the gallery.
  static let land = Animation.spring(response: 0.55, dampingFraction: 0.62)
  /// The task dock opening into its list.
  static let dock = Animation.spring(response: 0.35, dampingFraction: 0.72)
  /// The companion's face and name flying between the chat and its home page.
  static let companionFlight = Animation.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.56)
  /// What else is on the home page rising into place after the face, one after another.
  static let companionRise = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.38)
  /// What Loci is doing changing to the next thing.
  static let swap = Animation.timingCurve(0.28, 0.67, 0.32, 1, duration: 0.35)
  /// How long a reply being written goes on with no tool after it before it shows.
  static let replyHold: Duration = .seconds(1)
  /// The light crossing the line that says what Loci is doing.
  static let sheen = Animation.linear(duration: 2.2).repeatForever(autoreverses: false)
  /// How faint a breathing dot gets before it brightens again.
  static let breathLow = 0.3
  /// A rebuild finishing sooner than this is not shown at all, so nothing flickers.
  static let quietDelay = Duration.milliseconds(300)
  /// The runtime island growing out of its trigger, or sliding between its halves.
  static let islandOpen = Animation.spring(response: 0.42, dampingFraction: 0.74)
  /// The runtime island folding back into its trigger.
  static let islandClose = Animation.spring(response: 0.32, dampingFraction: 0.84)
  /// A trigger giving under the press.
  static let islandTouch = Animation.spring(response: 0.26, dampingFraction: 0.72)
  /// How long the pointer rests on a rail tab before it opens, so crossing the rail on the way to a list does not
  /// switch tabs.
  static let railDwell = Duration.milliseconds(140)
}

extension EnvironmentValues {
  @Entry var suppressMotion = false

  var reducesMotion: Bool { suppressMotion || accessibilityReduceMotion }
}
