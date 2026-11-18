import Foundation
import LociModel

/// What the library knows of how far into each item the reader is.
struct Progress: Equatable {
  /// Every item the reader has a position in.
  var states: [EntityID: ReadingState] = [:]

  /// How much of `item` has been watched or heard, from its position and length. Read items are full; text
  /// items have no share to show.
  func share(of item: Item) -> Double? {
    guard let state = states[item.id] else { return nil }
    if state.finished { return 1 }
    guard let length = item.length, case .item(_, .time(let span)) = state.position else { return nil }
    return Timeline.share(span.start, of: length)
  }

  /// The items being watched, heard or read now: started, not finished, latest first, at most three.
  func shelf(of items: [Item]) -> [Item] {
    let started = items.compactMap { item -> (Item, ReadingState)? in
      guard let state = states[item.id], state.position != nil, !state.finished else { return nil }
      return (item, state)
    }
    return started.sorted { $0.1.updatedAt > $1.1.updatedAt }.prefix(3).map(\.0)
  }
}

extension Item {
  /// How long a video or audio item runs, once known.
  var length: Duration? {
    switch kind {
    case .video(let duration), .audio(let duration): duration
    case .article, .paper, .repository: nil
    }
  }

  /// The line under the title: length and where it comes from, as `34:12 · CNCF` or `blog.cloudflare.com`.
  var byline: String {
    let place = site ?? source?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
    return [length.map(MediaTime.text), place].compactMap { $0 }.joined(separator: " · ")
  }
}
