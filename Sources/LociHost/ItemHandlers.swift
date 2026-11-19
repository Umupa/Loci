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
    let language = library.context.targetLanguage
    let page = try attempt {
      let item = try store.item(id)
      guard item.kind == .article, let text = try store.fetchedContent(of: id) else {
        return ItemPage(item: item, text: nil)
      }
      let foreign = item.language.map { JobRun.primary($0) != JobRun.primary(language) } ?? true
      return ItemPage(
        item: item, text: text, translatable: foreign,
        translation: foreign ? try store.articleTranslation(of: id, into: language) : nil)
    }
    guard page.translatable else { return page }
    return ItemPage(
      item: page.item, text: page.text, translatable: true, translation: page.translation,
      translating: await library.translator.progress(of: id))
  }

  public func translateArticle(_ id: EntityID) async throws(HostError) -> Done {
    let page = try await itemPage(id)
    guard page.translatable else { throw .invalidRequest("\(page.item.title) is not an article in another language") }
    await library.translator.start(id)
    await follow([.item(id)])
    return Done()
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
