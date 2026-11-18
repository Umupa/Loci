import Foundation
import GRDB
import LociModel

extension StoreDatabase {
  /// Replaces every mirror and the search index with what the files say now.
  ///
  /// Safe at any time: the result depends only on the files, so rebuilding twice, or rebuilding after
  /// following changes one by one, gives the same tables.
  @discardableResult
  public func rebuild(from store: Store) throws -> [FileProblem] {
    let read = readMirrors(from: store)
    try replaceMirrors(with: read.updates)
    return read.problems
  }

  /// Everything a rebuild writes, read from the files. Reading and writing are separate steps so the
  /// order of a rebuild against concurrent changes can be tested.
  func readMirrors(from store: Store) -> (updates: [MirrorUpdate], problems: [FileProblem]) {
    let snapshot = store.load()
    let updates =
      snapshot.items.map { item in
        MirrorUpdate.item(
          item.id, item,
          content: Self.text(of: item) {
            try store.content(inFolder: snapshot.itemFolders[item.id] ?? store.itemFolder(item.id))
          })
      }
      + snapshot.notes.map { MirrorUpdate.notes($0.key, $0.value) }
    return (updates, snapshot.problems)
  }

  func replaceMirrors(with updates: [MirrorUpdate]) throws {
    try queue.write { db in
      for table in Schema.mirrorTables { try db.execute(sql: "DELETE FROM \(table)") }
      for update in updates { try update.write(db) }
    }
  }

  /// Updates only the rows the changes touch.
  @discardableResult
  public func apply(_ changes: Set<ContentChange>, from store: Store) throws -> [FileProblem] {
    if changes.contains(.everything) { return try rebuild(from: store) }
    var problems: [FileProblem] = []
    var updates: [MirrorUpdate] = []
    for change in changes {
      switch change {
      case .item(let id):
        let item = Self.item(id, in: store, problems: &problems)
        updates.append(.item(id, item, content: item.flatMap { Self.text(of: $0) { try store.content(of: id) } }))
      case .notes(let content):
        let notes = store.notes(on: content)
        problems += notes.problems
        updates.append(.notes(content, notes.value))
      case .everything, .reading, .job, .media, .conversation, .turnEnded, .review, .events, .loci, .runtime:
        continue
      }
    }
    try queue.write { db in
      for update in updates { try update.write(db) }
    }
    return problems
  }

  private static func item(_ id: EntityID, in store: Store, problems: inout [FileProblem]) -> Item? {
    do {
      return try store.item(id)
    } catch StoreError.invalid(let problem) {
      problems.append(problem.attributed(to: .item(id)))
      return nil
    } catch {
      return nil
    }
  }

  private static func text(of item: Item, reading content: () throws -> String) -> String? {
    switch item.kind {
    case .article, .paper: try? content()
    case .video, .audio, .repository: nil
    }
  }
}
