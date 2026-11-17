import Foundation
import LociModel

/// Everything the folder holds, read in one pass. Enough to rebuild any index from the files alone.
public struct Snapshot: Sendable {
  public let mentors: [MentorSnapshot]
  public let items: [Item]
  public let notes: [ContentRef: [Note]]
  /// Every file that could not be used. Each one only takes its own contents out of the snapshot.
  public let problems: [FileProblem]
}

public struct MentorSnapshot: Sendable {
  public let mentor: Mentor
  /// `nil` when `catalog.yaml` is invalid; a problem says why.
  public let catalog: Catalog?
  /// What every written lesson cites, whether or not the catalog lists it.
  public let citations: [Citation]
}

extension Store {
  public func load() -> Snapshot {
    var problems: [FileProblem] = []
    let mentors = unique(subfolders(of: mentorsFolder), problems: &problems) { folder in
      try decodeJSON(Mentor.self, at: folder.appending(path: Self.mentorFile))
    }
    let items = unique(subfolders(of: libraryFolder), problems: &problems) { folder in
      try decodeJSON(Item.self, at: folder.appending(path: Self.itemFile))
    }
    let snapshots = mentors.map { mentor, folder in
      MentorSnapshot(
        mentor: mentor, catalog: catalog(in: folder, problems: &problems),
        citations: citations(in: folder, of: mentor.id, problems: &problems))
    }
    return Snapshot(
      mentors: snapshots, items: items.map(\.value), notes: allNotes(problems: &problems), problems: problems)
  }

  /// Reads each folder, keeping the first folder for each id: one whose name ends in the id, else the
  /// first by name. Later folders with the same id are reported as duplicates.
  private func unique<Value: Identified>(
    _ folders: [URL], problems: inout [FileProblem], read: (URL) throws -> Value
  ) -> [(value: Value, folder: URL)] {
    var found: [(value: Value, folder: URL)] = []
    for folder in folders {
      do {
        found.append((try read(folder), folder))
      } catch StoreError.notFound {
        continue
      } catch {
        problems.append(problem(at: folder, error))
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
            reason: "another folder already holds \(entry.value.id)"))
      }
    }
    return kept.sorted { $0.folder.lastPathComponent < $1.folder.lastPathComponent }
  }

  private func catalog(in folder: URL, problems: inout [FileProblem]) -> Catalog? {
    do {
      return try decodeYAML(Catalog.self, at: folder.appending(path: Self.catalogFile))
    } catch StoreError.notFound {
      return try? Catalog(chapters: [])
    } catch {
      problems.append(problem(at: folder.appending(path: Self.catalogFile), error))
      return nil
    }
  }

  private func citations(in folder: URL, of mentor: EntityID, problems: inout [FileProblem]) -> [Citation] {
    var citations: [Citation] = []
    for file in files(in: folder.appending(path: Self.lessonsFolder), withExtension: "md") {
      let name = file.deletingPathExtension().lastPathComponent
      guard let slug = Lesson.Slug(name) else {
        problems.append(
          FileProblem(path: relativePath(of: file), kind: .misnamed, reason: "\(name) is not a lesson slug"))
        continue
      }
      let ref = LessonRef(mentor: mentor, lesson: slug)
      guard let text = try? readText(file) else {
        problems.append(FileProblem(path: relativePath(of: file), kind: .unreadable, reason: "not UTF-8 text"))
        continue
      }
      let found: LessonText.Citations
      do {
        found = try LessonText(parsing: text).citations(in: ref)
      } catch {
        problems.append(problem(at: file, error))
        found = LessonText.citations(in: ref, front: nil, body: LessonText.body(of: text))
      }
      citations += found.citations
      problems += found.brokenLocators.map {
        FileProblem(path: relativePath(of: file), kind: .brokenLocator, reason: "cannot read \($0)")
      }
    }
    return citations
  }

  private func allNotes(problems: inout [FileProblem]) -> [ContentRef: [Note]] {
    var contents: [ContentRef] = []
    for file in files(in: notesFolder.appending(path: Self.libraryNotesFolder), withExtension: "jsonl") {
      if let item = EntityID(canonical: file.deletingPathExtension().lastPathComponent) { contents.append(.item(item)) }
    }
    for folder in subfolders(of: notesFolder.appending(path: Self.mentorNotesFolder)) {
      guard let mentor = EntityID(canonical: folder.lastPathComponent) else { continue }
      for file in files(in: folder, withExtension: "jsonl") {
        if let slug = Lesson.Slug(file.deletingPathExtension().lastPathComponent) {
          contents.append(.lesson(LessonRef(mentor: mentor, lesson: slug)))
        }
      }
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

extension Mentor: Identified {}
extension Item: Identified {}
