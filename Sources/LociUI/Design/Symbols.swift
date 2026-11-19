import LociModel

/// The SF Symbols the interface uses, by meaning.
enum Symbols {
  static let library = "books.vertical"
  static let problem = "exclamationmark.triangle.fill"
  static let send = "arrow.up"
  static let attach = "paperclip"
  static let settings = "gearshape"
  static let agents = "terminal"
  static let fold = "chevron.right"
  static let popup = "chevron.up.chevron.down"
  static let highlight = "highlighter"
  static let thought = "text.bubble"
  static let ask = "bubble.left"
  static let sidebar = "sidebar.left"
  static let panel = "sidebar.right"
  static let stop = "stop.fill"
  static let done = "checkmark"
  static let browser = web
  static let media = "slider.horizontal.3"
  static let play = "play.fill"
  static let pause = "pause.fill"
  static let back5 = "gobackward.5"
  static let forward5 = "goforward.5"
  static let fullScreen = "arrow.up.left.and.arrow.down.right"
  static let subtitles = "captions.bubble"
  static let external = "arrow.up.forward.square"
  static let backToPlaying = "play.circle"
  static let download = "arrow.down.to.line"
  static let update = "arrow.up"
  static let restart = "arrow.clockwise"
  static let retry = "exclamationmark"
  static let add = "plus"
  static let camera = "camera"
  static let lock = "lock"
  static let reload = "arrow.clockwise"
  static let back = "chevron.left"
  static let forward = "chevron.right"
  static let search = "magnifyingglass"
  static let more = "ellipsis"
  static let cancel = "xmark"
  static let recognizing = "waveform"
  static let copy = "doc.on.doc"
  static let latest = "arrow.down"
  static let thinking = "brain"
  static let tools = "hammer"
  static let web = "globe"
  static let remote = "display.2"

  static func machine(_ model: MachineModel) -> String {
    switch model {
    case .laptop: "laptopcomputer"
    case .mini: "macmini"
    case .iMac, .other: "desktopcomputer"
    case .studio: "macstudio"
    case .pro: "macpro.gen3"
    }
  }

  static func tool(_ kind: ToolActivity.Kind) -> String {
    switch kind {
    case .read: "doc.text"
    case .edit: "pencil"
    case .create: "doc.badge.plus"
    case .delete: "trash"
    case .execute: "terminal"
    case .search: "magnifyingglass"
    case .other: "wrench.and.screwdriver"
    }
  }

  static func kind(_ kind: ItemKind) -> String {
    switch kind {
    case .article: "doc.text"
    case .paper: "book.closed"
    case .video: "play.rectangle"
    case .audio: "headphones"
    case .repository: "chevron.left.forwardslash.chevron.right"
    }
  }
}

/// An item's kind without what the kind carries, for grouping and filtering.
enum ItemKind: String, CaseIterable, Codable, Hashable {
  case video, audio, article, paper, repository

  /// The kinds the sidebar lists, in a fixed order.
  static let listed: [ItemKind] = [.video, .audio, .article, .paper]

  init(_ kind: Item.Kind) {
    switch kind {
    case .article: self = .article
    case .paper: self = .paper
    case .video: self = .video
    case .audio: self = .audio
    case .repository: self = .repository
    }
  }
}
