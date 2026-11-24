import Foundation
import LociModel

extension LocalHost {
  public func recall(_ command: Recall) async throws(HostError) -> [RecallHit] {
    try attempt { try database.recall(command.text, limit: min(max(1, command.limit), 50)) }
  }
}

extension LocalHost {
  /// Read from the file each time, which the review and the person may both have changed.
  public func wikiPage(_ name: String) async throws(HostError) -> WikiPage {
    guard let text = try attempt({ try store.wikiPage(name) }) else { throw .notFound(name) }
    return WikiPage(name: name, parsing: text, title: itemTitles())
  }

  public func forgetWikiLine(_ command: ForgetWikiLine) async throws(HostError) -> Done {
    try attempt {
      guard let text = try store.wikiPage(command.page),
        let remaining = MemoryEntry.removing(command.line, from: text)
      else { throw HostError.notFound(command.line) }
      try store.saveWikiPage(remaining, as: command.page)
    }
    await follow([.loci(.wiki)])
    return Done()
  }
}
