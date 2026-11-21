import SwiftUI

/// How a site a panel reads is marked before its title: the app's own drawing of the sites people follow most,
/// and the first letter of the name for any other. Nothing is fetched to draw it.
enum SiteMark: Equatable {
  case github, x, hackerNews, notion
  case letter(Character)

  /// From a domain such as `news.ycombinator.com`, or a whole address.
  init(_ site: String) {
    let host = URL(string: site)?.host() ?? site
    let labels = host.lowercased().split(separator: ".").map(String.init)
    let domain = labels.suffix(2).joined(separator: ".")
    switch domain {
    case "github.com": self = .github
    case "x.com", "twitter.com": self = .x
    case "ycombinator.com": self = .hackerNews
    case "notion.so", "notion.site": self = .notion
    default:
      let name = labels.count > 1 ? labels[labels.count - 2] : labels.first
      self = .letter(name?.first.map { Character($0.uppercased()) } ?? "·")
    }
  }
}

/// A site's mark in a small circle, ringed in the color of what it sits on so marks side by side stay apart.
struct SiteBadge: View {
  let site: String
  var size = Size.siteMark
  var ring = Palette.surface

  var body: some View {
    face
      .frame(width: size, height: size)
      .clipShape(Circle())
      .background(Circle().fill(ring).padding(-2))
      .accessibilityHidden(true)
  }

  @ViewBuilder private var face: some View {
    switch SiteMark(site) {
    case .github: drawn("github", on: Palette.Site.github)
    case .x: drawn("x", on: Palette.Site.x)
    case .hackerNews: letter("Y", ink: Palette.Site.mark, on: Palette.Site.hackerNews)
    case .notion:
      letter("N", ink: Palette.Site.notionInk, on: Palette.Site.notion, design: .serif)
        .overlay(Circle().strokeBorder(Palette.Site.notionInk, lineWidth: 1.2))
    case .letter(let first): letter(first, ink: Palette.ink, on: Palette.fillStrong)
    }
  }

  private func drawn(_ name: String, on background: Color) -> some View {
    background.overlay {
      if let mark = MarkArt.site(name) {
        Image(nsImage: mark).renderingMode(.template).resizable().scaledToFit()
          .foregroundStyle(Palette.Site.mark)
          .frame(width: size * 0.62, height: size * 0.62)
      }
    }
  }

  private func letter(
    _ letter: Character, ink: Color, on background: Color, design: Font.Design = .default
  ) -> some View {
    background.overlay {
      Text(verbatim: String(letter))
        .font(.system(size: size / 2, weight: .bold, design: design))
        .foregroundStyle(ink)
    }
  }
}

/// What marks a panel that has no sites of its own yet: the sites a request names, and Loci's face when it
/// reads the library too or names no site at all.
struct PanelSources: Equatable {
  var sites: [String]
  var loci = false

  static let loci = PanelSources(sites: [], loci: true)

  /// The sites `text` names, by domain or by name, with Loci's face after them when it names the library too;
  /// an example sent as it is keeps its own marks.
  static func named(in text: String, locale: Locale) -> PanelSources {
    let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    for example in PanelExample.all {
      var words = example.words
      words.locale = locale
      if String(localized: words) == typed { return example.sources }
    }
    let lowered = typed.lowercased()
    var found: [(at: String.Index, site: String)] = []
    for match in lowered.matches(of: /(?:https?:\/\/)?((?:[a-z0-9-]+\.)+[a-z]{2,})/) {
      found.append((match.range.lowerBound, Self.domain(String(match.1))))
    }
    for (names, site) in Self.named {
      for name in names { if let range = lowered.range(of: name) { found.append((range.lowerBound, site)) } }
    }
    var sites: [String] = []
    for (_, site) in found.sorted(by: { $0.at < $1.at }) where !sites.contains(site) { sites.append(site) }
    if sites.isEmpty { return .loci }
    return PanelSources(sites: sites, loci: Self.library.contains { lowered.contains($0) })
  }

  /// Words that say the panel reads the library as well as its sites.
  private static let library = ["资料库", "我读过", "读过的", "library", "loci://"]

  /// A site's usual domain, so `www.github.com` and `github.com` are one site.
  private static func domain(_ host: String) -> String {
    host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }

  /// Sites people name rather than spell out.
  private static let named: [([String], String)] = [
    (["github"], "github.com"), (["hacker news", "hackernews"], "news.ycombinator.com"),
    (["notion"], "notion.so"), (["twitter", "推特", "x 上"], "x.com"),
  ]
}

/// The marks of a panel's sites, overlapping a little, and Loci's face after them when it reads the library.
struct SiteBadges: View {
  let sites: [String]
  var loci = false
  var size = Size.siteMark
  var ring = Palette.surface

  init(sites: [String], loci: Bool = false, size: CGFloat = Size.siteMark, ring: Color = Palette.surface) {
    self.sites = sites
    self.loci = loci
    self.size = size
    self.ring = ring
  }

  init(_ sources: PanelSources, ring: Color = Palette.surface) {
    self.init(sites: sources.sites, loci: sources.loci, ring: ring)
  }

  var body: some View {
    HStack(spacing: -size * 0.27) {
      ForEach(Array(sites.enumerated()), id: \.offset) { _, site in
        SiteBadge(site: site, size: size, ring: ring)
      }
      if loci {
        LociAvatar(size: size, framing: .portrait).background(Circle().fill(ring).padding(-2))
      }
    }
  }
}
