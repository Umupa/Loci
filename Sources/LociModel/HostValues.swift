/// A mentor with its catalog, as one view shows it.
public struct MentorPage: Hashable, Codable, Sendable {
  public let mentor: Mentor
  /// `nil` when `catalog.yaml` cannot be read; the problem is in `Health`.
  public let catalog: Catalog?
  /// Lessons that have text, whether or not the catalog lists them.
  public let writtenLessons: [Lesson.Slug]
  /// Lessons read to the end.
  public let readLessons: Set<Lesson.Slug>
  /// Lessons the mentor revised since the reader last saw them.
  public let revisedLessons: Set<Lesson.Slug>

  public init(
    mentor: Mentor, catalog: Catalog?, writtenLessons: [Lesson.Slug], readLessons: Set<Lesson.Slug> = [],
    revisedLessons: Set<Lesson.Slug> = []
  ) {
    self.mentor = mentor
    self.catalog = catalog
    self.writtenLessons = writtenLessons
    self.readLessons = readLessons
    self.revisedLessons = revisedLessons
  }
}

/// An item with its text and the lessons that cite it, as one view shows it.
public struct ItemPage: Hashable, Codable, Sendable {
  public let item: Item
  /// The text of an article or paper; `nil` for kinds read some other way.
  public let text: String?
  public let citedBy: [CitingLesson]

  public init(item: Item, text: String?, citedBy: [CitingLesson]) {
    self.item = item
    self.text = text
    self.citedBy = citedBy
  }
}

/// One citation of an item, with the names needed to show where it comes from.
public struct CitingLesson: Hashable, Codable, Sendable {
  public let citation: Citation
  public let mentorName: String
  /// `nil` when the lesson is written but missing from its mentor's catalog.
  public let lessonTitle: String?

  public init(citation: Citation, mentorName: String, lessonTitle: String?) {
    self.citation = citation
    self.mentorName = mentorName
    self.lessonTitle = lessonTitle
  }
}

/// Whether the host's storage is sound, and which files it could not use.
public struct Health: Hashable, Codable, Sendable {
  public let database: DatabaseState
  /// The database was replaced when this host started, so reading positions were lost.
  public let readingStateLost: Bool
  public let fileProblems: [FileProblem]

  public init(database: DatabaseState, readingStateLost: Bool, fileProblems: [FileProblem]) {
    self.database = database
    self.readingStateLost = readingStateLost
    self.fileProblems = fileProblems
  }

  public enum DatabaseState: Hashable, Codable, Sendable {
    /// Lists and search may be out of date until the rebuild finishes.
    case rebuilding
    case ready
    /// Lists and search are unavailable; files can still be read.
    case failed(String)
  }
}

/// The reply of a command that has nothing to say beyond having succeeded.
public struct Done: Hashable, Codable, Sendable {
  public init() {}
}
