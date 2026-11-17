import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func createMentor(_ command: CreateMentor) async throws(HostError) -> Mentor {
    let request = command.request.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard !request.isEmpty else { throw .invalidRequest("say what the mentor should teach") }
    let others = try attempt { try database.mentors() }
    let agent = try await agentDefaults().forNewMentors
    let mentor = try attempt {
      try Mentor(
        id: environment.newID(), name: MentorLook.name(from: request),
        avatar: MentorLook.mark(after: others, pick: environment.pick).rawValue,
        color: MentorLook.color(after: others, pick: environment.pick), provider: agent.provider, model: agent.model,
        request: command.request.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    try attempt { try store.create(mentor) }
    await follow([.mentor(mentor.id)])
    try await begin(mentor)
    return mentor
  }

  public func renameMentor(_ command: RenameMentor) async throws(HostError) -> Mentor {
    let renamed = try attempt {
      let mentor = try store.mentor(command.mentor)
      let renamed = try Mentor(
        id: mentor.id, name: command.name.trimmingCharacters(in: .whitespacesAndNewlines), avatar: mentor.avatar,
        color: mentor.color, provider: mentor.provider, model: mentor.model, effort: mentor.effort,
        request: mentor.request)
      try store.save(renamed)
      return renamed
    }
    await follow([.mentor(renamed.id)])
    return renamed
  }

  public func deleteMentor(_ command: DeleteMentor) async throws(HostError) -> Done {
    let lessons = store.loadMentor(command.mentor).value?.writtenLessons ?? []
    await mentors.forget(command.mentor)
    do throws(HostError) {
      try attempt { try store.deleteMentor(command.mentor, notes: command.notes) }
      await mentors.forgotten(command.mentor)
    } catch {
      await mentors.forgotten(command.mentor)
      throw error
    }
    var changes: Set<ContentChange> = [.mentor(command.mentor)]
    if command.notes == .delete {
      for lesson in lessons { changes.insert(.notes(.lesson(LessonRef(mentor: command.mentor, lesson: lesson)))) }
    }
    await follow(changes)
    return Done()
  }

  public func listMentors() async throws(HostError) -> [Mentor] {
    try attempt { try database.mentors() }
  }

  /// Read from the files, which always win over the database.
  public func mentorPage(_ mentor: EntityID) async throws(HostError) -> MentorPage {
    let loaded = store.loadMentor(mentor)
    guard let snapshot = loaded.value else {
      if let problem = loaded.problems.first { throw .invalidFile(problem) }
      throw .notFound(mentor.description)
    }
    let marks = readingMarks(of: mentor)
    return MentorPage(
      mentor: snapshot.mentor, catalog: snapshot.catalog, writtenLessons: snapshot.writtenLessons,
      readLessons: marks.read, revisedLessons: marks.revised)
  }
}

/// How a new mentor is named and how it looks.
enum MentorLook {
  static let longestName = 24

  /// The sentence itself, shortened if it is long: Chinese may be cut anywhere, a Latin word is not cut in
  /// half. The mentor gives itself a proper name later.
  static func name(from request: String) -> String {
    guard request.count > longestName else { return request }
    let cut = request.prefix(longestName)
    let splitsWord = isWordCharacter(request[cut.endIndex]) && cut.last.map(isWordCharacter) == true
    if splitsWord, let space = cut.lastIndex(of: " "), space > cut.startIndex {
      return String(cut[..<space])
    }
    return cut.trimmingCharacters(in: .whitespaces)
  }

  private static func isWordCharacter(_ character: Character) -> Bool {
    character.isASCII && (character.isLetter || character.isNumber)
  }

  /// A sign no other mentor wears yet, or any sign once all are worn.
  static func mark(after others: [Mentor], pick: (Int) -> Int) -> Mentor.Mark {
    choose(from: Mentor.Mark.allCases, avoiding: Set(others.map(\.mark)), pick: pick)
  }

  /// A colour no other mentor has yet, or any colour once all are taken.
  static func color(after others: [Mentor], pick: (Int) -> Int) -> MentorColor {
    choose(from: MentorColor.palette, avoiding: Set(others.map(\.color.nearestInPalette)), pick: pick)
  }

  private static func choose<Look: Hashable>(from looks: [Look], avoiding taken: Set<Look>, pick: (Int) -> Int)
    -> Look
  {
    let free = looks.filter { !taken.contains($0) }
    let choices = free.isEmpty ? looks : free
    return choices[pick(choices.count)]
  }
}
