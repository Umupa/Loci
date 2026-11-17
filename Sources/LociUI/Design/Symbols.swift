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
  static let nextLesson = "arrow.right"
  static let highlight = "highlighter"
  static let thought = "text.bubble"
  static let ask = "questionmark.bubble"
  static let panel = "sidebar.right"
  static let stop = "stop.fill"
  static let done = "checkmark"
  static let permission = "hand.raised.fill"

  static func tool(_ kind: ToolActivity.Kind) -> String {
    switch kind {
    case .read: "doc.text.magnifyingglass"
    case .edit: "pencil"
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
    case .audio: "waveform"
    case .repository: "chevron.left.forwardslash.chevron.right"
    }
  }
}

/// An item's kind without what the kind carries, for grouping and filtering.
enum ItemKind: String, CaseIterable, Codable, Hashable {
  case article, paper, video, audio, repository

  /// Kinds that have at least one item, in a fixed order. Empty kinds are not listed.
  static func present(in items: [Item]) -> [ItemKind] {
    let present = Set(items.map { ItemKind($0.kind) })
    return allCases.filter(present.contains)
  }

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
