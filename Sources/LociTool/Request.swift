import Foundation
import LociModel

/// What the person, or rather Loci, asked the command to do.
enum Request: Hashable, Sendable {
  case search(String)
  case show(EntityID)
  case save(URL)
  case read(URL)
  case repo(URL, commit: CommitID?)
  case importFile(path: String, title: String?)
  case wait(EntityID)
  case panel(PanelRequest)
  case source(SourceRequest)
  case course(CourseRequest)
  case feeling(FeelingRequest)
  case schedule(ScheduleRequest)
  case followUp(FollowUpRequest)
  case next(NextRequest)
  case connector(ConnectorRequest)
  case recall(String)
  case nameProject(String)
  case describeProject(String)
  /// The overview, or one topic of it.
  case help(String?)

  /// The request in `arguments` (without the program's name), and whether to print the app's replies as
  /// they are.
  static func parse(_ arguments: [String]) throws(UsageError) -> (request: Request, json: Bool) {
    var words = arguments.filter { $0 != "--json" }
    let json = words.count != arguments.count
    guard !words.isEmpty else { return (.help(nil), json) }
    let verb = words.removeFirst()
    switch verb {
    case "search":
      let text = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
      guard !text.isEmpty else { throw UsageError("loci search needs words to look for: loci search <words>") }
      return (.search(text), json)
    case "show": return (.show(try id(words, verb: verb)), json)
    case "wait": return (.wait(try id(words, verb: verb)), json)
    case "save":
      guard words.count == 1, let url = URL(string: words[0]), url.isWebLink else {
        throw UsageError("loci save takes one http or https link: loci save <url>")
      }
      return (.save(url), json)
    case "read":
      guard words.count == 1, let url = URL(string: words[0]), url.isWebLink, url.user == nil else {
        throw UsageError("loci read takes one http or https link without credentials: loci read <url>")
      }
      return (.read(url), json)
    case "repo": return (try repository(words), json)
    case "import": return (try importing(words), json)
    case "panel": return (.panel(try PanelRequest.parse(words)), json)
    case "source": return (.source(try SourceRequest.parse(words)), json)
    case "course": return (.course(try CourseRequest.parse(words)), json)
    case "schedule": return (.schedule(try ScheduleRequest.parse(words)), json)
    case "followup": return (.followUp(try FollowUpRequest.parse(words)), json)
    case "next": return (.next(try NextRequest.parse(words)), json)
    case "connector": return (.connector(try ConnectorRequest.parse(words)), json)
    case "lesson": return (.course(try CourseRequest.lesson(words)), json)
    case "mood": return (.feeling(try mood(words)), json)
    case "sleep", "wake":
      guard words.isEmpty else { throw UsageError("loci \(verb) takes nothing more: loci \(verb)") }
      return (.feeling(verb == "sleep" ? .sleep : .wake), json)
    case "recall":
      let text = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
      guard !text.isEmpty else { throw UsageError("loci recall needs words to look for: loci recall <words>") }
      return (.recall(text), json)
    case "project": return (try project(words), json)
    case "help", "--help", "-h":
      guard words.count <= 1 else { throw UsageError("loci help takes at most one topic: loci help [<topic>]") }
      return (.help(words.first), json)
    default:
      throw UsageError("loci has no command \"\(verb)\". Run `loci help` to see the commands.")
    }
  }

  private static func project(_ words: [String]) throws(UsageError) -> Request {
    let text = words.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
    switch words.first {
    case "name" where !text.isEmpty: return .nameProject(text)
    case "describe" where !text.isEmpty: return .describeProject(text)
    default: throw UsageError("loci project needs: loci project name <name> | loci project describe <line>")
    }
  }

  private static func repository(_ words: [String]) throws(UsageError) -> Request {
    let usage =
      "loci repo takes one http or https repository link and an optional full commit SHA: "
      + "loci repo <url> [--commit <sha>]"
    guard let first = words.first, let url = URL(string: first), url.isWebLink, url.user == nil
    else { throw UsageError(usage) }
    if words.count == 1 { return .repo(url, commit: nil) }
    guard words.count == 3, words[1] == "--commit", let commit = CommitID(words[2].lowercased()) else {
      throw UsageError(usage)
    }
    return .repo(url, commit: commit)
  }

  static let moodUsage =
    "loci mood here <word> <valence 0-10> <why> | loci mood base <word> <valence 0-10> <energy 0-10> <why>"

  private static func mood(_ words: [String]) throws(UsageError) -> FeelingRequest {
    func score(_ word: String) throws(UsageError) -> Score {
      guard let number = Int(word), let score = Score(number) else {
        throw UsageError("\(word) is not a whole number from 0 to 10: \(moodUsage)")
      }
      return score
    }
    func why(_ words: ArraySlice<String>) throws(UsageError) -> String {
      let why = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
      guard !why.isEmpty else { throw UsageError("Say why at the end: \(moodUsage)") }
      return why
    }
    switch words.first {
    case "here" where words.count >= 4:
      return .here(word: words[1], valence: try score(words[2]), why: try why(words[3...]))
    case "base" where words.count >= 5:
      return .base(word: words[1], valence: try score(words[2]), energy: try score(words[3]), why: try why(words[4...]))
    default:
      throw UsageError(moodUsage)
    }
  }

  private static func id(_ words: [String], verb: String) throws(UsageError) -> EntityID {
    guard words.count == 1, let id = EntityID(words[0]) else {
      throw UsageError("loci \(verb) takes one item id, as `loci search` prints it: loci \(verb) <id>")
    }
    return id
  }

  private static func importing(_ words: [String]) throws(UsageError) -> Request {
    var words = words
    var title: String?
    if let flag = words.firstIndex(of: "--title") {
      guard words.indices.contains(flag + 1) else { throw UsageError("--title needs a title: --title \"<title>\"") }
      title = words[flag + 1].trimmingCharacters(in: .whitespaces)
      words.removeSubrange(flag...(flag + 1))
      guard title?.isEmpty == false else { throw UsageError("--title needs a title: --title \"<title>\"") }
    }
    guard words.count == 1 else { throw UsageError("loci import takes one file: loci import <file> [--title <title>]") }
    if title != nil, !isArticle(words[0]) {
      throw UsageError("--title is for .md files; a video or audio file is titled after its name")
    }
    return .importFile(path: words[0], title: title)
  }
}

/// `loci panel …`: the panels Loci keeps beside the main conversation.
enum PanelRequest: Hashable, Sendable {
  /// Reads the panel's JSON from standard input.
  case save(String)
  case list
  case show(String)
  /// Adds Loci's item at the end of a section; `proposed` leaves it for the person to take or not.
  case add(panel: String, section: String, text: String, proposed: Bool)
  /// Keeps these of the entries a panel that follows a source was offered, with one sentence on them.
  case pick(panel: String, ids: [String], say: String)

  static let usage =
    "loci panel save <name> < panel.json | loci panel list | loci panel show <name>"
    + " | loci panel add <name> <section> <text> [--propose] | loci panel pick <name> --say <sentence> [<id>...]"

  static func parse(_ words: [String]) throws(UsageError) -> PanelRequest {
    if words.first == "pick" {
      var rest = Array(words.dropFirst())
      guard let index = rest.firstIndex(of: "--say"), rest.indices.contains(index + 1) else {
        throw UsageError("loci panel pick needs one sentence on what is new: --say \"…\"")
      }
      let say = rest[index + 1]
      rest.removeSubrange(index...(index + 1))
      guard let name = rest.first else { throw UsageError(usage) }
      return .pick(panel: try self.name(name), ids: Array(rest.dropFirst()), say: say)
    }
    if words.first == "add" {
      let rest = words.dropFirst().filter { $0 != "--propose" }
      let text = rest.dropFirst(2).joined(separator: " ").trimmingCharacters(in: .whitespaces)
      guard rest.count >= 3, !text.isEmpty else { throw UsageError(usage) }
      return .add(
        panel: rest[rest.startIndex], section: rest[rest.startIndex + 1], text: text,
        proposed: rest.count + 1 < words.count)
    }
    switch (words.first, words.count) {
    case ("list", 1): return .list
    case ("save", 2): return .save(try name(words[1]))
    case ("show", 2): return .show(words[1])
    default: throw UsageError(usage)
    }
  }

  private static func name(_ name: String) throws(UsageError) -> String {
    if let problem = PanelCheck.problems(ofName: name).first { throw UsageError(problem.reason) }
    return name
  }
}

/// Whether a file is imported as an article rather than as video or audio.
func isArticle(_ path: String) -> Bool {
  ["md", "markdown"].contains(URL(filePath: path).pathExtension.lowercased())
}

/// The command was written wrong; the message says how to write it.
struct UsageError: Error, Hashable {
  let message: String

  init(_ message: String) {
    self.message = message
  }
}
