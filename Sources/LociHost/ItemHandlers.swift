import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func addTextItem(_ command: AddTextItem) async throws(HostError) -> Item {
    try await addTextItem(command, by: .person)
  }

  func addTextItem(_ command: AddTextItem, by saver: Saver) async throws(HostError) -> Item {
    guard let title = command.title ?? ItemTitle.of(command.text, fileName: command.fileName) else {
      throw .invalidRequest("the file has neither a heading nor a name")
    }
    let item = try attempt {
      try Item(id: environment.newID(), kind: .article, title: title, authors: command.authors)
    }
    try attempt { try store.add(item, content: command.text) }
    await follow([.item(item.id)])
    await saved(item.id, by: saver)
    return item
  }

  public func deleteItem(_ command: DeleteItem) async throws(HostError) -> Done {
    await loci.forget(item: command.item)
    do throws(HostError) {
      try attempt { try store.deleteItem(command.item, notes: command.notes) }
      await loci.forgotten(item: command.item)
    } catch {
      await loci.forgotten(item: command.item)
      throw error
    }
    await library.queue.forget(command.item)
    try? database.deleteEvents(about: command.item)
    var changes: Set<ContentChange> = [.item(command.item), .conversation(.item(command.item)), .events]
    if command.notes == .delete { changes.insert(.notes(.item(command.item))) }
    await follow(changes)
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
