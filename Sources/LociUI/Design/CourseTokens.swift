import AppKit
import SwiftUI

extension Palette {
  /// The desk a course is built on, behind the title page, the sources and the open book.
  static let desk = Color(dark: 0x151413, light: 0xF3F1EC)
  /// The face of the card a course is built in.
  static let builderFace = Color(dark: 0x1A1917, light: 0xFBFAF7)
  /// A page of a course: paper in dark as in light, a little warmer in dark so it does not glare.
  static let leaf = Color(dark: 0xECE6D8, light: 0xFFFDF8)
  /// The edge of the pages under a book's cover, a shade under `leaf`.
  static let leafShade = Color(dark: 0xE2DBCB, light: 0xF5F1E8)
  /// Ink on a course's pages, the same in both appearances as the paper nearly is.
  static let leafInk = Color(nsColor: NSColor(rgb: 0x1D1B18))
  /// Words on a book's cloth.
  static let clothInk = Color(nsColor: NSColor(rgb: 0xF5ECDC))
  /// A book's bookmark ribbon, darker at its edges.
  static let ribbon = Color(nsColor: NSColor(rgb: 0xC5463A))
  static let ribbonEdge = Color(nsColor: NSColor(rgb: 0x9E2B22))

  /// The cloths a course's book is bound in: muted, so a shelf of them reads as one set. A book is the same
  /// thing in light and dark, so each is one color.
  enum Cloth {
    static let all: [Color] = [slate, oxblood, moss, ochre, teal, plum]
    static let slate = Color(nsColor: NSColor(rgb: 0x3D4955))
    static let oxblood = Color(nsColor: NSColor(rgb: 0x5E2C28))
    static let moss = Color(nsColor: NSColor(rgb: 0x4A5541))
    static let ochre = Color(nsColor: NSColor(rgb: 0x80602F))
    static let teal = Color(nsColor: NSColor(rgb: 0x2F4B4A))
    static let plum = Color(nsColor: NSColor(rgb: 0x4E3A4E))
  }

  /// The small pictures of a course's sources, by kind; each stands for a thing, so is the same in both
  /// appearances.
  enum SourceThumb {
    static let video = Color(nsColor: NSColor(rgb: 0x243039))
    static let videoDeep = Color(nsColor: NSColor(rgb: 0x141A20))
    static let page = Color(nsColor: NSColor(rgb: 0x3F6FA8))
    static let pageDeep = Color(nsColor: NSColor(rgb: 0x2B4F80))
  }
}

extension Tones {
  /// The number on a citation's amber disc.
  static let citationInk = NSColor(dark: 0xF0B456, light: 0x94590A)
}

extension Radius {
  /// The card a course is built in.
  static let builder: CGFloat = 26
  /// A book's cover: tight at the spine, round at the fore-edge.
  static let bookSpine: CGFloat = 4
  static let bookEdge: CGFloat = 10
  /// An answer card, and a source card on the desk.
  static let answer: CGFloat = 16
}

extension Size {
  static let builderChat: CGFloat = 350
  static let builderHead: CGFloat = 60
  static let builderFoot: CGFloat = 66
  static let titlePage = CGSize(width: 330, height: 500)
  static let openBook = CGSize(width: 560, height: 400)
  static let sourceCard: CGFloat = 104
  static let sourceDesk: CGFloat = 600
  static let bookMinimum: CGFloat = 190
  static let courseNav: CGFloat = 226
  static let wishField: CGFloat = 52
  static let lessonColumn: CGFloat = 560
  static let bead: CGFloat = 12
}

extension Motion {
  /// The builder growing out of the field or the book, and going back into the book.
  static let expand = Animation.spring(duration: 0.64, bounce: 0.18)
  /// A written page turning over.
  static let turn = Animation.timingCurve(0.45, 0.05, 0.3, 1, duration: 1.05)
  /// A chosen answer flying to its line on the title page.
  static let fly = Animation.timingCurve(0.45, 0.05, 0.3, 1, duration: 0.76)
  /// The seal coming down on the title page.
  static let stamp = Animation.spring(duration: 0.55, bounce: 0.38)
  /// A book lifting and turning a little under the pointer.
  static let tilt = Animation.spring(duration: 0.5, bounce: 0.3)
  /// Words being inked in, a character at a time.
  static let inkPerCharacter = 0.028
  /// Seconds for the light to cross a title being written.
  static let shimmerPeriod = 2.2
}

extension Typography {
  static let bookTitle = Serif.Face(size: 21, weight: .semibold)
  static let bookSubtitle = Serif.Face(size: 12.5)
  static let titlePageTitle = Serif.Face(size: 44, weight: .semibold)
  static let titlePageSubtitle = Serif.Face(size: 16)
  static let lessonTitle = Serif.Face(size: 36, weight: .semibold)
  static let leafTitle = Serif.Face(size: 21, weight: .semibold)
  static let leafBody = Serif.Face(size: 13.5)
  static let sourceTitle = Serif.Face(size: 14.5, weight: .semibold)
}

extension Symbols {
  static let course = "text.book.closed"
  static let pencil = "pencil"
  static let collapseBuilder = "chevron.down"
}
