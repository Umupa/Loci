import LociModel
import SwiftUI

/// How a site a panel reads is marked before its title: a connector's icon for a site a connector is on, the
/// same as the Connectors page draws it, Hacker News's own mark, and a seal with the first letter of the name for
/// any other. Nothing is fetched to draw it.
enum SiteMark: Equatable {
  case connector(ConnectorID)
  case hackerNews
  case letter(Character)

  /// From a domain such as `news.ycombinator.com`, a whole address, or a connector's id.
  init(_ site: String) {
    if let connector = ConnectorSites.connector(for: site) {
      self = .connector(connector)
      return
    }
    let host = URL(string: site)?.host() ?? site
    let labels = host.lowercased().split(separator: ".").map(String.init)
    if labels.suffix(2).joined(separator: ".") == "ycombinator.com" {
      self = .hackerNews
      return
    }
    let name = labels.count > 1 ? labels[labels.count - 2] : labels.first
    self = .letter(name?.first.map { Character($0.uppercased()) } ?? "·")
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
      .background(Circle().fill(Palette.paper))
      .clipShape(Circle())
      .background(Circle().fill(ring).padding(-2))
      .accessibilityHidden(true)
  }

  @ViewBuilder private var face: some View {
    switch SiteMark(site) {
    case .connector(let id):
      ConnectorArt(id: id, size: size * 0.62)
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
    case .hackerNews:
      Palette.Site.hackerNews.overlay {
        Text(verbatim: "Y").font(.system(size: size / 2, weight: .bold)).foregroundStyle(Palette.Site.mark)
      }
    case .letter(let first): SiteSeal(letter: String(first), side: size)
    }
  }
}

/// A site's first letter in serif ink inside a thin ring, on paper: how the cover of an item without a picture
/// and a site the app has no mark for are marked.
struct SiteSeal<Face: View>: View {
  let side: CGFloat
  @ViewBuilder let face: Face

  var body: some View {
    face
      .foregroundStyle(Palette.paperInk)
      .frame(width: side, height: side)
      .overlay(Circle().strokeBorder(Palette.paperInk.opacity(0.7), lineWidth: max(side * 0.025, 1)))
  }
}

extension SiteSeal where Face == Text {
  init(letter: String, side: CGFloat) {
    self.init(side: side) { Text(serif: letter.uppercased(), Serif.Face(size: side * 0.46, weight: .medium)) }
  }

  /// The first letter or digit in `text`, falling back to its first non-whitespace character.
  static func letter(for text: String) -> String {
    let meaningful = text.first { $0.isLetter || $0.isNumber }
    guard let chosen = meaningful ?? text.first(where: { !$0.isWhitespace }) else { return "" }
    return String(chosen).uppercased()
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
