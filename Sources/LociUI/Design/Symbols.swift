import LociModel

/// The SF Symbols the interface uses, by meaning.
enum Symbols {
  static let start = "square.and.pencil"
  static let library = "books.vertical"
  static let problem = "exclamationmark.triangle.fill"
  static let send = "arrow.up"
  static let link = "link"
  static let lesson = "doc.plaintext"
  static let settings = "gearshape"
  static let agents = "terminal"
  static let lessonUnwritten = "circle.dashed"
  static let lessonUnread = "circle"
  static let lessonRead = "checkmark.circle.fill"
  static let lessonRevised = "circle.badge.exclamationmark"
  static let fold = "chevron.right"
  static let popup = "chevron.up.chevron.down"
  static let highlight = "pencil.tip"
  static let thought = "text.bubble"
  static let ask = "bubble.left"
  static let sidebar = "sidebar.left"
  static let panel = "sidebar.right"
  static let stop = "stop.fill"
  static let done = "checkmark"
  static let browser = "safari"
  static let media = "play.square.stack"
  static let play = "play.fill"
  static let pause = "pause.fill"
  static let back5 = "gobackward.5"
  static let forward5 = "goforward.5"
  static let fullScreen = "arrow.up.left.and.arrow.down.right"
  static let subtitles = "captions.bubble"
  static let external = "arrow.up.forward.square"
  static let backToPlaying = "arrow.up"
  static let download = "arrow.down.to.line"
  static let add = "plus"
  static let lock = "lock"
  static let reload = "arrow.clockwise"
  static let back = "chevron.left"
  static let forward = "chevron.right"
  static let search = "magnifyingglass"
  static let more = "ellipsis"
  static let cancel = "xmark"
  static let attach = "paperclip"
  static let recognizing = "waveform"
  static let thoughtSmall = "text.bubble"
  static let copy = "doc.on.doc"
  static let latest = "arrow.down"
  static let tools = "square.stack.3d.up"
  static let web = "globe"
  static let remote = "dot.radiowaves.left.and.right"

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
    case .read: "doc.text.magnifyingglass"
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
    case .paper: "doc.richtext"
    case .video: "play.rectangle"
    case .audio: "mic"
    case .repository: "chevron.left.forwardslash.chevron.right"
    }
  }
}

/// An item's kind without what the kind carries, for grouping and filtering.
enum ItemKind: String, CaseIterable, Codable, Hashable {
  case video, audio, article, paper, repository

  /// The kinds the sidebar lists, in a fixed order: video, podcasts and articles always, as the places links
  /// are added to; papers and repositories once there is one.
  static func listed(in items: [Item]) -> [ItemKind] {
    let present = Set(items.map { ItemKind($0.kind) })
    return allCases.filter { always.contains($0) || present.contains($0) }
  }

  private static let always: Set<ItemKind> = [.video, .audio, .article]

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
