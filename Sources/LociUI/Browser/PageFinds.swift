import Foundation
import LociModel

/// What a web page over the window can put into the library: the page itself when it is something the library
/// keeps, then the videos and the papers it links to. `nil` when there is none, and the button is not shown.
struct PageFinds: Equatable {
  enum Kind: Hashable { case page, video, paper }

  /// One thing on the page, as its row in the list shows it.
  struct Find: Hashable, Identifiable {
    let kind: Kind
    let url: URL
    let title: String
    var thumbnail: URL?
    /// The item the library already keeps it as.
    var inLibrary: EntityID?

    var id: URL { url }
  }

  /// What clicking the button does.
  enum Click: Equatable {
    /// Only the page is left to keep, and it is kept at once.
    case keepPage
    /// More than the page is left; the list opens.
    case choose
    /// Everything is kept; the page opens in the library.
    case open(EntityID)
  }

  /// In list order: the page, the videos, the papers.
  let all: [Find]

  init?(at url: URL, title: String, facts: PageFacts, library: [Item]) {
    let kept = Dictionary(
      library.compactMap { item in item.source.map { (PageAddress($0), item.id) } }, uniquingKeysWith: { first, _ in first })
    var seen: Set<PageAddress> = []
    var all: [Find] = []
    func add(_ kind: Kind, _ link: URL, _ title: String, thumbnail: URL? = nil) {
      let address = PageAddress(link)
      guard seen.insert(address).inserted else { return }
      all.append(Find(kind: kind, url: link, title: title, thumbnail: thumbnail, inLibrary: kept[address]))
    }
    let kind = LinkKind(url)
    if kind != .article || facts.isPDF || facts.hasArticle {
      add(.page, url, title)
    } else {
      seen.insert(PageAddress(url))
    }
    for video in facts.videos { add(.video, video.url, video.title, thumbnail: video.thumbnail) }
    for paper in facts.papers { add(.paper, paper.url, paper.title) }
    guard !all.isEmpty else { return nil }
    self.all = all
  }

  /// What is not in the library yet.
  var left: [Find] { all.filter { $0.inLibrary == nil } }

  var page: Find? { all.first { $0.kind == .page } }

  /// The page is in the library; with no page, everything on it is.
  var kept: Bool { page.map { $0.inLibrary != nil } ?? left.isEmpty }

  var click: Click {
    let left = left
    if left.isEmpty, let item = page?.inLibrary ?? all.first?.inLibrary { return .open(item) }
    if left.count == 1, left.first?.kind == .page { return .keepPage }
    return .choose
  }

  /// The number on the button: how many are left to choose from, when clicking opens the list.
  var count: Int? { click == .choose ? left.count : nil }
}
