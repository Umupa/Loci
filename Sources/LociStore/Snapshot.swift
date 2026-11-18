import Foundation
import LociModel

/// Everything the folder holds, read in one pass. Enough to rebuild any index from the files alone.
public struct Snapshot: Sendable {
  public let items: [Item]
  public let notes: [ContentRef: [Note]]
  /// Every file that could not be used. Each one only takes its own contents out of the snapshot.
  public let problems: [FileProblem]
  /// Where each item was found, so its content can be read without looking the folder up again.
  let itemFolders: [EntityID: URL]
}

extension Store {
  public func load() -> Snapshot {
    var problems: [FileProblem] = []
    let items = unique(subfolders(of: libraryFolder), as: FileProblem.Subject.item, problems: &problems) { folder in
      try decodeJSON(Item.self, at: folder.appending(path: Self.itemFile))
    }
    return Snapshot(
      items: items.map(\.value), notes: allNotes(problems: &problems), problems: problems,
      itemFolders: Dictionary(uniqueKeysWithValues: items.map { ($0.value.id, $0.folder) }))
  }

  /// Reads each folder, keeping the first folder for each id: one whose name ends in the id, else the
  /// first by name. Later folders with the same id are reported as duplicates.
  private func unique<Value: Identified>(
    _ folders: [URL], as subject: (EntityID) -> FileProblem.Subject, problems: inout [FileProblem],
    read: (URL) throws -> Value
  ) -> [(value: Value, folder: URL)] {
    var found: [(value: Value, folder: URL)] = []
    for folder in folders {
      do {
        found.append((try read(folder), folder))
      } catch StoreError.notFound {
        continue
      } catch {
        let owner = id(ofFolder: folder) ?? FolderName.id(in: folder.lastPathComponent)
        problems.append(problem(at: folder, error).attributed(to: owner.map(subject)))
      }
    }
    let preferred = found.sorted { lhs, rhs in
      let lhsNamed = FolderName.id(in: lhs.folder.lastPathComponent) == lhs.value.id
      let rhsNamed = FolderName.id(in: rhs.folder.lastPathComponent) == rhs.value.id
      return lhsNamed != rhsNamed ? lhsNamed : lhs.folder.lastPathComponent < rhs.folder.lastPathComponent
    }
    var seen = Set<EntityID>()
    var kept: [(value: Value, folder: URL)] = []
    for entry in preferred {
      if seen.insert(entry.value.id).inserted {
        kept.append(entry)
      } else {
        problems.append(
          FileProblem(
            path: relativePath(of: entry.folder), kind: .duplicateID,
            reason: "another folder already holds \(entry.value.id)", subject: subject(entry.value.id)))
      }
    }
    return kept.sorted { $0.folder.lastPathComponent < $1.folder.lastPathComponent }
  }

  private func allNotes(problems: inout [FileProblem]) -> [ContentRef: [Note]] {
    var contents: [ContentRef] = []
    for file in files(in: notesFolder.appending(path: Self.libraryNotesFolder), withExtension: "jsonl") {
      if let item = EntityID(canonical: file.deletingPathExtension().lastPathComponent) { contents.append(.item(item)) }
    }
    var notes: [ContentRef: [Note]] = [:]
    for content in contents {
      let loaded = self.notes(on: content)
      notes[content] = loaded.value
      problems += loaded.problems
    }
    return notes
  }
}

protocol Identified {
  var id: EntityID { get }
}

extension Item: Identified {}
