import Foundation
import LociModel

/// What the page in the built-in browser told about itself, from a script run in it after each load.
struct PageFacts: Equatable {
  /// Links to single videos on the page, in page order, without repeats.
  var videos: [FoundVideo] = []
  /// The page has a body of text long enough to read as an article.
  var hasArticle = false
  /// The page is a PDF the browser is showing.
  var isPDF = false
}

/// A video linked from a channel or list page.
struct FoundVideo: Hashable, Identifiable {
  let url: URL
  let title: String
  let thumbnail: URL?
  /// As the page wrote it, such as `34:12`.
  let duration: String?

  var id: URL { url }
}

/// The button beside the address bar: what the page in front can become in the library.
enum PageOffer: Equatable {
  /// The page is already an item.
  case inLibrary(EntityID)
  /// The page is one video; it goes into the library at once.
  case video
  /// The page lists videos; the reader picks which.
  case videos([FoundVideo])
  /// An episode, a paper or PDF, or an article.
  case add

  /// `nil` when the page is none of these, and the button is not shown.
  init?(at url: URL, facts: PageFacts, library: [Item]) {
    let address = PageAddress(url)
    if let item = library.first(where: { $0.source.map(PageAddress.init) == address }) {
      self = .inLibrary(item.id)
      return
    }
    let kind = LinkKind(url)
    if kind == .video {
      self = .video
    } else if facts.videos.count > 1 {
      self = .videos(facts.videos)
    } else if kind == .audio || kind == .paper || facts.isPDF || facts.hasArticle {
      self = .add
    } else {
      return nil
    }
  }
}

/// An address with what does not change the page taken off: `www.`, a trailing slash, the fragment and
/// tracking parameters. Two addresses of the same page compare equal.
struct PageAddress: Hashable {
  let host: String
  let path: String
  let query: [String]

  init(_ url: URL) {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let host = (components?.host ?? "").lowercased()
    self.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    let path = components?.path ?? ""
    self.path = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    query = (components?.queryItems ?? [])
      .filter { !Self.tracking($0.name) }
      .map { "\($0.name)=\($0.value ?? "")" }
      .sorted()
  }

  private static func tracking(_ name: String) -> Bool {
    let name = name.lowercased()
    return name.hasPrefix("utm_")
      || ["si", "feature", "fbclid", "gclid", "ref", "spm_id_from", "vd_source", "t"]
        .contains(name)
  }
}
