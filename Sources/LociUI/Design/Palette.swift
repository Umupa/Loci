import AppKit
import LociModel
import SwiftUI

/// The warm colors. Each one has its own value in dark and in light; neither is the other inverted.
///
/// Text colors are checked against the backgrounds they sit on, so every pair stays readable.
enum Palette {
  /// The content area.
  static let canvas = Color(nsColor: Tones.canvas)
  /// The panel beside the text, and code blocks.
  static let well = Color(nsColor: Tones.well)
  /// The warm surface under the sidebar's glass.
  static let sidebarWash = LinearGradient(
    stops: [
      .init(color: Color(nsColor: Tones.sidebarTop), location: 0.15),
      .init(color: Color(nsColor: Tones.sidebarMiddle), location: 0.55),
      .init(color: Color(nsColor: Tones.sidebarBottom), location: 0.85),
    ],
    startPoint: .top, endPoint: .bottom)
  /// Cards and input fields.
  static let surface = Color(nsColor: Tones.surface)
  /// Under what is lifted while it is dragged.
  static let liftShadow = Color(nsColor: NSColor(dark: 0x000000, light: 0x3C2A0E, alpha: (dark: 0.55, light: 0.22)))
  static let ink = Color(nsColor: Tones.ink)
  static let inkMuted = Color(nsColor: Tones.inkMuted)
  /// Neutral symbols and text in the sidebar.
  static let sidebarInkMuted = Color(nsColor: Tones.sidebarInkMuted)
  static let sidebarSectionInk = Color(dark: 0xA89A89, light: 0x5D5A56)
  static let sidebarSelectedInk = Color(dark: 0xFFB84D, light: 0x784409)
  /// Section labels, dates and glyphs; never for text that must be read.
  static let inkFaint = Color(nsColor: Tones.inkFaint)
  /// Hairlines between things and around cards.
  static let line = Color(nsColor: Tones.line)
  /// Hairlines that must show on a card, such as between rows of a group.
  static let lineStrong = Color(nsColor: Tones.lineStrong)
  /// Behind a row under the pointer.
  static let fill = Color(nsColor: Tones.fill)
  /// The track of a segmented control, and behind a button under the pointer.
  static let fillStrong = Color(nsColor: Tones.fillStrong)
  /// Amber, for marks and controls: progress, highlights, where you are, and the face of a button, a switch or a
  /// choice that is on. Use `accentInk` when amber is the color of text.
  static let accent = Color(nsColor: Tones.accent)
  static let accentInk = Color(nsColor: Tones.accentInk)
  /// A price or value that went up: red, as markets in China write it.
  static let rise = Color(dark: 0xF0675A, light: 0xD0453A)
  /// A price or value that went down: green.
  static let fall = Color(dark: 0x3DBB7F, light: 0x23905E)
  /// The block a quote's change is written on, as soft in the dark as the design's.
  static let riseBlockColor = NSColor(dark: 0xE78472, light: 0xD0453A)
  static let fallBlockColor = NSColor(dark: 0x74C296, light: 0x23905E)
  static let riseBlock = Color(nsColor: riseBlockColor)
  static let fallBlock = Color(nsColor: fallBlockColor)
  /// Words and glyphs on an amber fill, such as a button's.
  static let onAccent = Color(nsColor: Tones.onAccent)
  /// The dot by the companion's face while it is awake or a little tired.
  static let presenceAwake = Color(nsColor: Tones.presenceAwake)
  /// The dot while it is sleepy or asleep, or its Mac is offline.
  static let presenceAway = Color(nsColor: Tones.presenceAway)
  /// Around the dot by the face at the top of the sidebar, the color of the sidebar there.
  static let sidebarRing = Color(nsColor: Tones.sidebarTop)
  /// Loci's messages, and the person's, a shade apart.
  static let bubble = Color(nsColor: Tones.bubble)
  static let bubbleMine = Color(nsColor: Tones.bubbleMine)
  /// Around Loci's message in light, where white would melt into the paper.
  static let bubbleEdge = Color(nsColor: NSColor(dark: 0x000000, light: 0x000000, alpha: (dark: 0, light: 0.05)))
  /// The field at the foot of a conversation: a wash over the blur behind it, and its edge, low in dark so
  /// it sits in the page rather than shining over it.
  static let composerGlass = Color(nsColor: NSColor(dark: 0x22201D, light: 0xFAF9F6, alpha: (dark: 0.62, light: 0.72)))
  static let composerEdge = Color(nsColor: NSColor(dark: 0xFFFFFF, light: 0x000000, alpha: (dark: 0.08, light: 0.07)))
  /// Behind what is selected: a wash of amber, never a solid block.
  static let tint = Color(nsColor: Tones.tint)
  /// Behind text selected in the reader: a wash of ink, so it never reads as a highlight.
  static let selection = Color(nsColor: Tones.selection)
  /// Under the words of a highlight.
  static let mark = Color(nsColor: Tones.mark)
  /// Over a passage or card just jumped to, fading out.
  static let flash = Color(nsColor: Tones.flash)
  /// A thing that is ready to use, such as an installed agent.
  static let ready = Color(nsColor: Tones.ready)
  /// The thumb of a segmented control and the face of a push button.
  static let thumb = Color(nsColor: Tones.thumb)
  /// The light ring around a small avatar, lifting it off whatever it sits on.
  static let ring = Color(nsColor: Tones.ring)
  /// Around a card in dark, where a shadow would not show.
  static let cardEdge = Color(nsColor: NSColor(rgb: 0xFFF5E6)).opacity(0.06)
  /// The brown a card's shadow is tinted, so it reads warm on the paper.
  static let warmShadow = Color(nsColor: NSColor(rgb: 0x281E0F))
  /// The brown under Loci's portrait.
  static let portraitShadow = Color(nsColor: NSColor(rgb: 0x78460A))

  /// Behind a cover while it loads, and under a player.
  static let coverBackdrop = Color(nsColor: Tones.coverBackdrop)
  /// In a small thumbnail of an item that has no cover: paper in light, the backdrop in dark.
  static let coverPlaceholder = Color(nsColor: Tones.coverPlaceholder)
  /// Words over a cover or a picture, the same in light and dark because the picture is.
  static let onCover = Color(nsColor: NSColor(rgb: 0xFFF6EA))
  static let onCoverMuted = Color(nsColor: NSColor(rgb: 0xFFF0E0)).opacity(0.7)
  /// The word on the label marking the item to start with, on `onCover`.
  static let firstInk = Color(nsColor: NSColor(rgb: 0x94590A))
  /// The dark wash a cover's title sits on.
  static let coverShade = Color(nsColor: NSColor(rgb: 0x0E0A07))
  /// The face of a menu or a sheet Loci draws itself: the color of `floating`, but solid, so nothing under it
  /// shows through the words.
  static let menuFace = Color(nsColor: Tones.menuFace)
  /// Over the window behind a sheet.
  static let scrim = Color(nsColor: Tones.scrim)
  /// Over a conversation behind the runtime island: deep enough that the island reads as lifted above it.
  static let islandScrim = Color(nsColor: Tones.islandScrim)
  /// The tiles that ripple under Extra High thinking.
  static let effortExtraHigh = Color(nsColor: Tones.effortExtraHigh)
  /// The tiles that ripple under Max thinking.
  static let effortMax = Color(nsColor: Tones.effortMax)
  /// Over a conversation behind a web page opened on it: dark enough that the page stands apart even where the
  /// blur under it is not drawn.
  static let pageScrim = Color(nsColor: Tones.pageScrim)
  /// Menus and bars that float over the page.
  static let floating = Color(nsColor: Tones.floating)

  /// A finished stage on the stage ruler.
  static let accentLine = Color(nsColor: Tones.accentLine)
  /// A faint amber glow: the ring around a new project's field, and the heart of the light under the bar.
  static let glow = Color(nsColor: Tones.glow)
  /// Work that failed.
  static let failure = Color(nsColor: Tones.failure)
  /// Paper and ink for the cover of an item without a picture.
  static let paper = Color(dark: 0x302B25, light: 0xF6F1E7)
  static let paperFoot = Color(dark: 0x27231E, light: 0xEDE5D6)
  static let paperInk = Color(dark: 0xF2E8D7, light: 0x2B2621)
  static let paperInkMuted = Color(dark: 0xB6A897, light: 0x6F6150)

  /// The light that flows around work under way, and around the window while Loci saves.
  enum Glow {
    static let amber = Color(nsColor: NSColor(rgb: 0xE9A23B))
    static let coral = Color(nsColor: NSColor(rgb: 0xFF7B5C))
    static let gold = Color(nsColor: NSColor(rgb: 0xFFD27A))
  }

  /// The band of a calendar page on an approval card, red as the system's calendar draws it.
  enum Mark {
    static let calendar = Color(nsColor: NSColor(rgb: 0xE5484D))
  }

  /// The colors sites mark themselves with, the same in light and dark as their marks are.
  enum Site {
    static let github = Color(nsColor: NSColor(rgb: 0x1F2328))
    static let hackerNews = Color(nsColor: NSColor(rgb: 0xFF6600))
    static let mark = Color(nsColor: NSColor(rgb: 0xFFFFFF))
  }

  /// Code, colored by what each word is. Code sits on `well`.
  enum Code {
    static let keyword = Color(nsColor: Tones.codeKeyword)
    static let string = Color(nsColor: Tones.codeString)
    static let number = Color(nsColor: Tones.codeNumber)
    static let name = Color(nsColor: Tones.codeName)
  }

  /// The pairs of text and background the interface uses, for checking contrast.
  static let readablePairs: [(text: Color, background: Color, name: String)] = [
    (ink, canvas, "ink on canvas"), (ink, surface, "ink on surface"),
    (ink, well, "ink on well"),
    (ink, Color(nsColor: Tones.sidebarTop), "ink on the sidebar's top"),
    (ink, Color(nsColor: Tones.sidebarBottom), "ink on the sidebar's bottom"),
    (sidebarInkMuted, Color(nsColor: Tones.sidebarTop), "muted on the sidebar's top"),
    (sidebarInkMuted, Color(nsColor: Tones.sidebarBottom), "muted on the sidebar's bottom"),
    (sidebarSectionInk, Color(nsColor: Tones.sidebarTop), "section on the sidebar's top"),
    (sidebarSectionInk, Color(nsColor: Tones.sidebarBottom), "section on the sidebar's bottom"),
    (ink, bubble, "Loci's message"), (ink, bubbleMine, "the person's message"), (ink, tint, "selected text"),
    (ink, selection, "text selected in the reader"), (ink, mark, "highlighted text"),
    (ink, Color(nsColor: Tones.readerMark), "highlighted text in the reader"),
    (inkMuted, canvas, "muted on canvas"), (inkMuted, surface, "muted on surface"),
    (accentInk, canvas, "amber text on canvas"), (accentInk, surface, "amber text on surface"),
    (onAccent, accent, "text on amber"),
    (paperInk, paper, "cover title on paper"), (paperInk, paperFoot, "cover title on paper foot"),
    (paperInkMuted, paper, "cover source on paper"), (paperInkMuted, paperFoot, "cover source on paper foot"),
    (Code.keyword, well, "code keyword"), (Code.string, well, "code string"),
    (Code.number, well, "code number"), (Code.name, well, "code name"),
  ]
}

/// The same colors for AppKit, which draws the reader's text.
enum Tones {
  static let canvas = NSColor(dark: 0x121110, light: 0xFCFBF8)
  static let well = NSColor(dark: 0x191715, light: 0xF6F3EE)
  static let surface = NSColor(dark: 0x1E1C19, light: 0xFFFFFF)
  static let sidebarTop = NSColor(dark: 0x302925, light: 0xF5ECDE)
  static let sidebarMiddle = NSColor(dark: 0x2C2520, light: 0xE7DCCF)
  static let sidebarBottom = NSColor(dark: 0x251F1B, light: 0xD6D2CF)
  static let sidebarInkMuted = NSColor(dark: 0xBCB2A5, light: 0x5D5A56)
  static let ink = NSColor(dark: 0xF2EEE6, light: 0x1D1B18)
  static let inkMuted = NSColor(dark: 0x9A968F, light: 0x6E6B66)
  static let inkFaint = NSColor(dark: 0x5E5C59, light: 0xACAAA7)
  static let line = NSColor(dark: 0xFFF5E6, light: 0x1D1B18, alpha: (dark: 0.08, light: 0.09))
  static let lineStrong = NSColor(dark: 0xFFF5E6, light: 0x1D1B18, alpha: (dark: 0.13, light: 0.14))
  static let fill = NSColor(dark: 0xFFF5E6, light: 0x1D1B18, alpha: (dark: 0.05, light: 0.045))
  static let fillStrong = NSColor(dark: 0xFFF5E6, light: 0x1D1B18, alpha: (dark: 0.09, light: 0.08))
  static let accent = NSColor(dark: 0xEBA53A, light: 0xD98E1F)
  static let bubble = NSColor(dark: 0x211F1C, light: 0xFFFFFF)
  static let bubbleMine = NSColor(dark: 0x2E2B27, light: 0xEEECE7)
  static let accentInk = NSColor(dark: 0xF3D9AE, light: 0x94590A)
  static let onAccent = NSColor(dark: 0x1A1206, light: 0x1A1206)
  static let tint = NSColor(dark: 0xEBA53A, light: 0xD98E1F, alpha: (dark: 0.17, light: 0.15))
  static let selection = NSColor(dark: 0xFFF5E6, light: 0x1D1B18, alpha: (dark: 0.16, light: 0.11))
  static let mark = NSColor(dark: 0xEBA53A, light: 0xD98E1F, alpha: (dark: 0.30, light: 0.26))
  static let readerMark = NSColor(dark: 0xF3BA65, light: 0xD98E1F, alpha: (dark: 0.30, light: 0.20))
  static let flash = NSColor(dark: 0xEBA53A, light: 0xD98E1F, alpha: (dark: 0.6, light: 0.6))
  static let ready = NSColor(dark: 0x6CC783, light: 0x34A853)
  static let presenceAwake = NSColor(dark: 0x4FBF6E, light: 0x2E9E50)
  static let presenceAway = NSColor(dark: 0x7A766F, light: 0xA9A59E)
  static let thumb = NSColor(dark: 0x5A544D, light: 0xFFFFFF)
  static let ring = NSColor(dark: 0xFFF5E6, light: 0xFFFFFF, alpha: (dark: 0.14, light: 0.9))
  static let coverBackdrop = NSColor(dark: 0x2A2420, light: 0x2A2420)
  static let accentLine = NSColor(dark: 0xEBA53A, light: 0xD98E1F, alpha: (dark: 0.6, light: 0.55))
  static let glow = NSColor(dark: 0xEBA53A, light: 0xD98E1F, alpha: (dark: 0.13, light: 0.16))
  static let failure = NSColor(dark: 0xEE7A60, light: 0xC9503A)
  static let coverPlaceholder = NSColor(dark: 0x2A2420, light: 0xEFEAE2)
  static let menuFace = NSColor(dark: 0x2C2824, light: 0xFDFBF8)
  static let scrim = NSColor(dark: 0x000000, light: 0x281C0C, alpha: (dark: 0.32, light: 0.10))
  static let islandScrim = NSColor(dark: 0x000000, light: 0x281C0C, alpha: (dark: 0.36, light: 0.12))
  static let effortExtraHigh = NSColor(dark: 0xB57BF8, light: 0xA855F7)
  static let effortMax = NSColor(dark: 0xF4B942, light: 0xF4B942)
  static let pageScrim = NSColor(dark: 0x000000, light: 0x281C0C, alpha: (dark: 0.45, light: 0.22))
  static let floating = NSColor(dark: 0x2C2824, light: 0xFDFBF8, alpha: (dark: 0.96, light: 0.96))
  static let codeKeyword = NSColor(dark: 0xE09A6A, light: 0x9C4524)
  static let codeString = NSColor(dark: 0xA9C27C, light: 0x4F6A22)
  static let codeNumber = NSColor(dark: 0xDDB86E, light: 0x7E5600)
  static let codeName = NSColor(dark: 0x93B9CC, light: 0x2C5F78)
}

extension Color {
  init(dark: UInt32, light: UInt32) {
    self.init(nsColor: NSColor(dark: dark, light: light))
  }
}

extension NSColor {
  /// A color that follows the appearance it is drawn in, for text drawn by AppKit.
  convenience init(dark: UInt32, light: UInt32, alpha: (dark: CGFloat, light: CGFloat) = (1, 1)) {
    self.init(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return NSColor(rgb: isDark ? dark : light).withAlphaComponent(isDark ? alpha.dark : alpha.light)
    }
  }
}

extension NSColor {
  convenience init(rgb: UInt32) {
    self.init(
      srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
  }
}
