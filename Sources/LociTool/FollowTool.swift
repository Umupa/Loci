import Foundation
import LociModel

/// `loci follow …`: the channels and shows the person follows.
enum FollowRequest: Hashable, Sendable {
  case follow(URL)
  case list

  static let usage = "loci follow <channel, show or feed link> | loci follow list"

  static func parse(_ words: [String]) throws(UsageError) -> FollowRequest {
    if words == ["list"] { return .list }
    guard words.count == 1, let url = URL(string: words[0]), url.isWebLink else { throw UsageError(usage) }
    return .follow(url)
  }
}

extension Tool {
  func follow(_ request: FollowRequest, json: Bool) async throws(Failure) -> Outcome {
    switch request {
    case .follow(let link):
      let reply = try await line.run(AddFollow(link))
      if json { return .worked(Self.text(reply)) }
      let follow = try Failure.decoding(Follow.self, from: reply)
      return .worked("Following \(follow.name) (\(follow.page.absoluteString)).")
    case .list:
      let reply = try await line.run(ListFollows())
      if json { return .worked(Self.text(reply)) }
      let follows = try Failure.decoding([FollowListing].self, from: reply)
      guard !follows.isEmpty else { return .worked("The person follows no one yet.") }
      return .worked(follows.map(Self.described).joined(separator: "\n\n"))
    }
  }

  private static func described(_ listing: FollowListing) -> String {
    var lines = ["\(listing.follow.name)  \(listing.follow.page.absoluteString)"]
    if let latest = listing.latest {
      lines.append("    newest: \(latest.title)  \(latest.link.absoluteString)")
    }
    for kept in listing.kept { lines.append("    in the library: \(kept.title)  \(kept.item)") }
    return lines.joined(separator: "\n")
  }
}
