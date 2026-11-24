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

  /// Sets the items aside, so they leave the library at once and can still come back.
  public func deleteItems(_ command: DeleteItems) async throws(HostError) -> Done {
    try await deletions.through { () async throws(HostError) in
      try await setAsideItems(command.items)
    }
  }

  private func setAsideItems(_ items: [EntityID]) async throws(HostError) -> Done {
    let previous = setAsideDeletion()
    var changes: Set<ContentChange> = []
    var replacedUndo = false
    for item in items {
      await loci.forget(.item(item))
      await library.queue.setAside(item)
      do throws(HostError) {
        try attempt { try store.setAside(item) }
        await loci.forgotten(.item(item))
        if !replacedUndo {
          replacedUndo = true
          await discardSetAside(previous)
        }
      } catch {
        await loci.forgotten(.item(item))
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
    try await deletions.through { () async throws(HostError) in
      try await restoreSetAsideItems()
    }
  }

  private func restoreSetAsideItems() async throws(HostError) -> [Item] {
    var restored: [Item] = []
    var changes: Set<ContentChange> = []
    for id in store.setAsideItems() {
      try attempt { try store.restore(id) }
      changes.formUnion([.item(id), .notes(.item(id)), .conversation(.item(id))])
      await library.queue.putBack(id)
      if let item = try? store.item(id) { restored.append(item) }
    }
    await follow(changes)
    return restored
  }

  func setAsideDeletion() -> (items: [EntityID], courses: [EntityID]) {
    (store.setAsideItems(), store.setAsideCourses())
  }

  /// Retires the previous undo and finishes cleanup of deletions that have expired.
  func discardSetAside(_ deletion: (items: [EntityID], courses: [EntityID])? = nil) async {
    let deletion = deletion ?? setAsideDeletion()
    await discardSetAsideCourses(deletion.courses)
    for item in deletion.items {
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
        language: item.language, contentHash: item.contentHash, site: item.site, published: item.published,
        why: item.why)
    }
    try attempt { try store.retitle(renamed, from: item.title) }
    await follow([.item(item.id)])
    return renamed
  }

  public func setCover(_ command: SetCover) async throws(HostError) -> Done {
    guard let file = await hub.takeUpload(command.upload.id) else { throw .notFound("upload \(command.upload.id)") }
    let format = file.pathExtension.lowercased()
    guard SetCover.formats.contains(format) else { throw .invalidRequest("\(file.lastPathComponent) is not a picture") }
    do {
      try await library.context.covers.replace(command.item, with: file)
    } catch {
      throw HostError(error)
    }
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
    let language = library.context.choice(of: id)?.translation?.language ?? library.context.targetLanguage
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
    let job = await library.queue.job(of: id)
    let progress: TranslationProgress?
    if let job, job.stage == .translate {
      progress =
        switch job.state {
        case .queued: .running(Fraction(0))
        case .running(let fraction, _): .running(fraction ?? Fraction(0))
        case .failed(let failure): .failed(failure.reason)
        case .waiting(.modelService): .failed("No model service is configured to translate.")
        case .paused, .waiting, .done: nil
        }
    } else {
      progress = nil
    }
    return ItemPage(
      item: page.item, text: page.text, translatable: true, translation: page.translation,
      translating: progress)
  }

  public func translateArticle(_ id: EntityID) async throws(HostError) -> Done {
    let page = try await itemPage(id)
    guard page.translatable else { throw .invalidRequest("\(page.item.title) is not an article in another language") }
    do {
      try await library.queue.requestArticleTranslation(id)
    } catch {
      throw HostError(error)
    }
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
