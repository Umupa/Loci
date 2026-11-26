import Foundation
import LociModel

/// The SF Symbols the interface uses, by meaning.
enum Symbols {
  static let library = "books.vertical"
  static let libraryKept = "books.vertical.fill"
  static let problem = "exclamationmark.triangle.fill"
  static let send = "arrow.up"
  static let settings = "gearshape"
  static let window = "macwindow"
  static let quit = "power"
  static let schedule = "clock"
  static let panels = "square.grid.2x2"
  static let review = "moon"
  static let followUp = "arrow.uturn.backward"
  static let notes = "doc.text"
  static let agents = "terminal"
  static let fold = "chevron.right"
  static let popup = "chevron.up.chevron.down"
  static let highlight = "highlighter"
  static let thought = "text.bubble"
  static let ask = "bubble.left"
  static let delete = "trash"
  static let picture = "photo"
  static let panel = "sidebar.right"
  static let contents = "list.bullet"
  static let followedBack = "arrow.uturn.backward"
  /// The text-size glyphs: SF Symbols draws them as words in some languages, so they are drawn in
  /// `latinGlyphs` to stay the aA glyph everywhere.
  static let textSize = "textformat.size"
  static let textSmaller = "textformat.size.smaller"
  static let textLarger = "textformat.size.larger"
  static let latinGlyphs = Locale(identifier: "en")
  static let atlas = "rectangle.3.group"
  static let stop = "stop.fill"
  static let done = "checkmark"
  static let browser = "globe"
  static let media = "slider.horizontal.3"
  static let play = "play.fill"
  static let pause = "pause.fill"
  static let back5 = "gobackward.5"
  static let forward5 = "goforward.5"
  static let back15 = "gobackward.15"
  static let forward30 = "goforward.30"
  static let pictureInPicture = "pip.enter"
  static let fullScreen = "arrow.up.left.and.arrow.down.right"
  static let subtitles = "captions.bubble"
  static let keyPoints = "list.star"
  static let subtitleStyle = "textformat.size"
  static let external = "arrow.up.forward.square"
  static let backToPlaying = "play.circle"
  static let chapterPlaying = "waveform"
  static let download = "arrow.down.to.line"
  static let layout = "rectangle.split.3x1"
  static let update = "arrow.up"
  static let translate = "translate"
  static let tidy = "paragraphsign"
  static let restart = "arrow.clockwise"
  static let retry = "exclamationmark"
  static let add = "plus"
  static let link = "link"
  static let folder = "folder"
  static let camera = "camera"
  static let lock = "lock"
  static let reload = "arrow.clockwise"
  static let home = "house"
  static let signIn = "person.crop.circle.badge.checkmark"
  static let back = "chevron.left"
  static let forward = "chevron.right"
  static let search = "magnifyingglass"
  static let more = "ellipsis"
  static let collapse = "arrow.down.right.and.arrow.up.left"
  static let openOut = "arrow.up.left.and.arrow.down.right"
  static let unfold = "chevron.down"
  static let undo = "arrow.counterclockwise"
  static let cancel = "xmark"
  static let pin = "pin.fill"
  static let recognizing = "waveform"
  static let copy = "doc.on.doc"
  static let latest = "arrow.down"
  static let remote = "display.2"
  static let disk = "internaldrive"
  static let online = "dot.radiowaves.left.and.right"
  static let why = "quote.opening"

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

  static func category(_ category: LibraryCategory) -> String {
    switch category {
    case .article: kind(.article)
    case .video: kind(.video)
    case .audio: kind(.audio)
    case .book: kind(.book)
    }
  }

  static func kind(_ kind: ItemKind) -> String {
    switch kind {
    case .article: "doc.text"
    case .paper: "book.closed"
    case .video: "play.rectangle"
    case .audio: "headphones"
    case .repository: "chevron.left.forwardslash.chevron.right"
    case .book: "book"
    }
  }
}

/// An item's kind without its associated values, for item icons and labels.
enum ItemKind: Equatable {
  case video, audio, article, paper, repository, book

  init(_ kind: Item.Kind) {
    switch kind {
    case .article: self = .article
    case .paper: self = .paper
    case .video: self = .video
    case .audio: self = .audio
    case .repository: self = .repository
    case .book: self = .book
    }
  }
}
