import Foundation
import LociModel

/// Everything the folder holds, read in one pass. Enough to rebuild any index from the files alone.
public struct Snapshot: Sendable {
  public let mentors: [MentorSnapshot]
  public let items: [Item]
  public let notes: [ContentRef: [Note]]
  /// Every file that could not be used. Each one only takes its own contents out of the snapshot.
  public let problems: [FileProblem]
  /// Where each item was found, so its content can be read without looking the folder up again.
  let itemFolders: [EntityID: URL]
}

public struct MentorSnapshot: Sendable {
  public let mentor: Mentor
  /// `nil` when `catalog.yaml` is invalid; a problem says why.
  public let catalog: Catalog?
  /// Lessons with a file, whether or not the catalog lists them.
  public let writtenLessons: [Lesson.Slug]
  /// What every written lesson cites.
  public let citations: [Citation]
}

extension Store {
  public func load() -> Snapshot {
    var problems: [FileProblem] = []
    let mentors = unique(subfolders(of: mentorsFolder), as: FileProblem.Subject.mentor, problems: &problems) { folder in
      try decodeJSON(Mentor.self, at: folder.appending(path: Self.mentorFile))
    }
    let items = unique(subfolders(of: libraryFolder), as: FileProblem.Subject.item, problems: &problems) { folder in
      try decodeJSON(Item.self, at: folder.appending(path: Self.itemFile))
    }
    let snapshots = mentors.map { mentor, folder in snapshot(of: mentor, in: folder, problems: &problems) }
    return Snapshot(
      mentors: snapshots, items: items.map(\.value), notes: allNotes(problems: &problems), problems: problems,
      itemFolders: Dictionary(uniqueKeysWithValues: items.map { ($0.value.id, $0.folder) }))
  }

  /// One mentor's files, read the same way `load()` reads them. `nil` when the mentor is gone or its
  /// `mentor.json` cannot be read.
  public func loadMentor(_ id: EntityID) -> Loaded<MentorSnapshot?> {
    var problems: [FileProblem] = []
    do {
      let folder = try mentorFolder(id)
      let mentor = try decodeJSON(Mentor.self, at: folder.appending(path: Self.mentorFile))
      let snapshot = snapshot(of: mentor, in: folder, problems: &problems)
      return Loaded(value: snapshot, problems: problems)
    } catch StoreError.notFound {
      return Loaded(value: nil, problems: [])
    } catch {
      return Loaded(value: nil, problems: [problem(at: mentorsFolder, error).attributed(to: .mentor(id))])
    }
  }

  private func snapshot(of mentor: Mentor, in folder: URL, problems: inout [FileProblem]) -> MentorSnapshot {
    var own: [FileProblem] = []
    defer { problems += own.map { $0.attributed(to: .mentor(mentor.id)) } }
    let catalog = catalog(in: folder, problems: &own)
    checkGlossary(in: folder, problems: &own)
    var written: [Lesson.Slug] = []
    var citations: [Citation] = []
    for file in files(in: folder.appending(path: Self.lessonsFolder), withExtension: "md") {
      let name = file.deletingPathExtension().lastPathComponent
      guard let slug = Lesson.Slug(name) else {
        own.append(
          FileProblem(path: relativePath(of: file), kind: .misnamed, reason: "\(name) is not a lesson slug"))
        continue
      }
      written.append(slug)
      let ref = LessonRef(mentor: mentor.id, lesson: slug)
      citations += self.citations(inFile: file, of: ref, problems: &own) ?? []
    }
    return MentorSnapshot(mentor: mentor, catalog: catalog, writtenLessons: written, citations: citations)
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

  /// The glossary is not mirrored; reading it here only reports a file that cannot be used.
  private func checkGlossary(in folder: URL, problems: inout [FileProblem]) {
    let url = folder.appending(path: Self.glossaryFile)
    do {
      _ = try decodeYAML(Glossary.self, at: url)
    } catch StoreError.notFound {
      return
    } catch {
      problems.append(problem(at: url, error))
    }
  }

  private func citations(inFile file: URL, of ref: LessonRef, problems: inout [FileProblem]) -> [Citation]? {
    let text: String
    do {
      text = try readText(file)
    } catch StoreError.notFound {
      return nil
    } catch {
      problems.append(problem(at: file, error))
      return []
    }
    let found: LessonText.Citations
    do {
      found = try LessonText(parsing: text).citations(in: ref)
    } catch {
      problems.append(problem(at: file, error))
      found = LessonText.citations(in: ref, front: nil, body: LessonText.body(of: text))
    }
    problems += found.brokenLocators.map {
      FileProblem(path: relativePath(of: file), kind: .brokenLocator, reason: "cannot read \($0)")
    }
    return found.citations
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
