import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func addTextItem(_ command: AddTextItem) async throws(HostError) -> Item {
    guard let title = ItemTitle.of(command.text, fileName: command.fileName) else {
      throw .invalidRequest("the file has neither a heading nor a name")
    }
    let item = try attempt { try Item(id: environment.newID(), kind: .article, title: title) }
    try attempt { try store.add(item, content: command.text) }
    await follow([.item(item.id)])
    await happened(.saved(item.id))
    return item
  }

  /// Sets the items aside, so they leave the library at once and can still come back. What was set aside
  /// by the deletion before goes for good first: only the latest deletion can be undone.
  public func deleteItems(_ command: DeleteItems) async throws(HostError) -> Done {
    await discardSetAside()
    var changes: Set<ContentChange> = [.events]
    for item in command.items {
      await loci.forget(item: item)
      await library.queue.setAside(item)
      do throws(HostError) {
        try attempt { try store.setAside(item) }
        await loci.forgotten(item: item)
      } catch {
        await loci.forgotten(item: item)
        await library.queue.putBack(item)
        await follow(changes)
        throw error
      }
      changes.formUnion([.item(item), .notes(.item(item)), .conversation(.item(item))])
    }
    await follow(changes)
    return Done()
  }

  public func restoreDeleted() async throws(HostError) -> [Item] {
    var restored: [Item] = []
    var changes: Set<ContentChange> = [.events]
    for id in store.setAsideItems() {
      try attempt { try store.restore(id) }
      changes.formUnion([.item(id), .notes(.item(id)), .conversation(.item(id))])
      await library.queue.putBack(id)
      if let item = try? store.item(id) { restored.append(item) }
    }
    await follow(changes)
    return restored
  }

  /// Gets rid of what was set aside, with what the database still keeps of it: its conversation, its
  /// events and its job.
  func discardSetAside() async {
    for item in store.setAsideItems() {
      do {
        try store.discardSetAside(item)
      } catch {
        await hub.failed("could not discard a deleted item: \(error)")
        continue
      }
      try? database.deleteConversation(on: item)
      try? database.deleteEvents(about: item)
      await library.queue.forget(item)
    }
  }

  public func renameItem(_ command: RenameItem) async throws(HostError) -> Item {
    let title = command.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let item = try attempt { try store.item(command.item) }
    let renamed = try attempt {
      try Item(
        id: item.id, kind: item.kind, title: title, authors: item.authors, source: item.source,
        language: item.language, contentHash: item.contentHash, site: item.site, published: item.published)
    }
    try attempt { try store.retitle(renamed, from: item.title) }
    await follow([.item(item.id)])
    return renamed
  }

  public func setCover(_ command: SetCover) async throws(HostError) -> Done {
    guard let file = await hub.takeUpload(command.upload.id) else { throw .notFound("upload \(command.upload.id)") }
    let format = file.pathExtension.lowercased()
    guard SetCover.formats.contains(format) else { throw .invalidRequest("\(file.lastPathComponent) is not a picture") }
    try attempt { try store.saveCover(copying: file, of: command.item) }
    await follow([.item(command.item)])
    return Done()
  }

  public func listItems() async throws(HostError) -> [Item] {
    try attempt { try database.items() }
  }

  public func itemText(_ item: EntityID) async throws(HostError) -> String {
    try attempt { try store.content(of: item) }
  }

  public func itemPage(_ id: EntityID) async throws(HostError) -> ItemPage {
    try attempt {
      let item = try store.item(id)
      let text: String? =
        switch item.kind {
        case .article: try store.fetchedContent(of: id)
        case .paper, .video, .audio, .repository: nil
        }
      return ItemPage(item: item, text: text)
    }
  }
}

enum ItemTitle {
  /// The first `# ` heading, or else the file name without its extension.
  static func of(_ text: String, fileName: String) -> String? {
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) where line.hasPrefix("# ") {
      let heading = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
      if !heading.isEmpty { return heading }
    }
    let base = fileName.split(separator: "/").last.map(String.init) ?? fileName
    let stem = base.lastIndex(of: ".").map { $0 > base.startIndex ? String(base[..<$0]) : base } ?? base
    let title = stem.trimmingCharacters(in: .whitespaces)
    return title.isEmpty ? nil : title
  }
}
