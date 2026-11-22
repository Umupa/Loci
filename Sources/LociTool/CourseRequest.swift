import Foundation
import LociModel

enum CourseRequest: Hashable, Sendable {
  case ask
  case goal
  case ready
  case addSource(CourseSource.Draft)
  case readSource(EntityID)
  case listSources
  case plan
  case writeLesson(Lesson.ID, String)

  static func parse(_ words: [String]) throws(UsageError) -> CourseRequest {
    switch words {
    case ["ask"]: return .ask
    case ["goal"]: return .goal
    case ["ready"]: return .ready
    case ["plan"]: return .plan
    default:
      guard words.first == "source" else {
        throw UsageError("Use loci course ask, goal, ready, source, or plan. Run loci help for details.")
      }
      return try source(Array(words.dropFirst()))
    }
  }

  static func lesson(_ words: [String]) throws(UsageError) -> CourseRequest {
    guard words.count == 3, words[0] == "write", let id = Lesson.ID(words[1]), isArticle(words[2]) else {
      throw UsageError("Use loci lesson write <lesson-id> <file.md>; use an ID from loci course plan.")
    }
    return .writeLesson(id, words[2])
  }

  private static func source(_ words: [String]) throws(UsageError) -> CourseRequest {
    let usage = "Use loci course source add <url> [--title T] [--kind paper|video|repository|page] [--commit SHA]."
    switch (words.first, words.count) {
    case ("list", 1): return .listSources
    case ("read", 2):
      guard let id = EntityID(words[1]) else {
        throw UsageError("Use loci course source read <id>; get the ID with loci course source list.")
      }
      return .readSource(id)
    case ("add", 2...):
      guard let url = URL(string: words[1]), url.isWebLink else {
        throw UsageError("Give an http or https source URL. " + usage)
      }
      let flags = try sourceFlags(words.dropFirst(2), usage: usage)
      let kind = try flags["--kind"].map { (text) throws(UsageError) in
        guard let kind = CourseSource.Kind(rawValue: text) else { throw UsageError(usage) }
        return kind
      }
      let commit = try flags["--commit"].map { (text) throws(UsageError) in
        guard let id = CommitID(text) else { throw UsageError("--commit needs the full lowercase commit SHA.") }
        return id
      }
      do {
        return .addSource(try CourseSource.Draft(url: url, title: flags["--title"], kind: kind, commit: commit))
      } catch {
        throw UsageError("\(error). " + usage)
      }
    default:
      throw UsageError(usage + " Use loci course source list or loci course source read <id>.")
    }
  }

  private static func sourceFlags(_ words: ArraySlice<String>, usage: String) throws(UsageError) -> [String: String] {
    var flags: [String: String] = [:]
    var iterator = words.makeIterator()
    while let flag = iterator.next() {
      guard ["--title", "--kind", "--commit"].contains(flag), flags[flag] == nil, let value = iterator.next(),
        !value.hasPrefix("--")
      else { throw UsageError("Give each source option once, followed by its value. " + usage) }
      flags[flag] = value
    }
    return flags
  }
}
