import Foundation
import LociModel

extension LocalHost {
  public func recall(_ command: Recall) async throws(HostError) -> [RecallHit] {
    try await recall(command, from: .chat)
  }

  /// What a session in `home` may find: never a project kept out of memory but its own. Paths are given as
  /// the session sees them from its folder.
  func recall(_ command: Recall, from home: Home) async throws(HostError) -> [RecallHit] {
    let hidden = loci.context.hiddenFromRecall(in: home)
    let hits = try attempt { try database.recall(command.text, limit: min(max(1, command.limit), 50), hiding: hidden) }
    guard home != .chat else { return hits }
    return hits.map { hit in
      let path = hit.path.hasPrefix(home.folder) ? String(hit.path.dropFirst(home.folder.count)) : "../../" + hit.path
      return RecallHit(path: path, day: hit.day, snippet: hit.snippet)
    }
  }
}

extension LocalHost {
  /// Read from the file each time, which the review and the person may both have changed.
  public func wikiPage(_ name: String) async throws(HostError) -> WikiPage {
    guard let text = try attempt({ try store.home(.chat).wikiPage(name) }) else { throw .notFound(name) }
    return WikiPage(name: name, parsing: text, title: itemTitles())
  }

  public func forgetWikiLine(_ command: ForgetWikiLine) async throws(HostError) -> Done {
    try attempt {
      guard let text = try store.home(.chat).wikiPage(command.page),
        let remaining = MemoryEntry.removing(command.line, from: text)
      else { throw HostError.notFound(command.line) }
      try store.home(.chat).saveWikiPage(remaining, as: command.page)
    }
    await follow([.loci(.wiki)])
    return Done()
  }
}
