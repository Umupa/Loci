import Foundation
import LociModel

/// What the page in the built-in browser told about itself, from a script run in it after each load.
struct PageFacts: Equatable {
  /// Links to single videos on the page, in page order, without repeats.
  var videos: [FoundVideo] = []
  /// Links to papers and PDFs, in page order, without repeats or the page itself.
  var papers: [FoundPaper] = []
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

/// A paper or PDF a page links to, named by its link.
struct FoundPaper: Hashable, Identifiable {
  let url: URL
  let title: String

  var id: URL { url }
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
