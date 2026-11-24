import Foundation
import LociModel

/// What the library knows of how far into each item the reader is.
struct Progress: Equatable {
  /// Every item the reader has a position in.
  var states: [EntityID: ReadingState] = [:]

  /// How much of `item` has been watched, heard or read, from its position and length. Read items are full;
  /// a book's position carries its share; other text items have no share to show.
  func share(of item: Item) -> Double? {
    guard let state = states[item.id] else { return nil }
    if state.finished { return 1 }
    if case .item(_, .spot(let spot)) = state.position { return spot.share.value }
    guard let length = item.length, case .item(_, .time(let span)) = state.position else { return nil }
    return Timeline.share(span.start, of: length)
  }

  /// Books with the one read most recently first, then those not opened yet as they came; other kinds as they
  /// came.
  func ordered(_ items: [Item], by category: LibraryCategory?) -> [Item] {
    guard category == .book else { return items }
    let read = items.filter { states[$0.id] != nil }.sorted {
      (states[$0.id]?.updatedAt.millisecondsSince1970 ?? 0) > (states[$1.id]?.updatedAt.millisecondsSince1970 ?? 0)
    }
    return read + items.filter { states[$0.id] == nil }
  }
}

extension Item {
  /// How long a video or audio item runs, once known.
  var length: Duration? {
    switch kind {
    case .video(let duration), .audio(let duration): duration
    case .article, .paper, .repository, .book: nil
    }
  }

  /// The line under the title: length and where it comes from, as `34:12 · CNCF` or `blog.cloudflare.com`.
  var byline: String {
    [length.map(MediaTime.text), sourceName].compactMap { $0 }.joined(separator: " · ")
  }

  var sourceName: String? {
    site ?? source?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
  }
}
