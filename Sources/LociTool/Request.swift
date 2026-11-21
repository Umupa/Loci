import Foundation
import LociModel

/// What the person, or rather Loci, asked the command to do.
enum Request: Hashable, Sendable {
  case search(String)
  case show(EntityID)
  case save(URL)
  case importFile(path: String, title: String?)
  case wait(EntityID)
  case panel(PanelRequest)
  case help

  /// The request in `arguments` (without the program's name), and whether to print the app's replies as
  /// they are.
  static func parse(_ arguments: [String]) throws(UsageError) -> (request: Request, json: Bool) {
    var words = arguments.filter { $0 != "--json" }
    let json = words.count != arguments.count
    guard !words.isEmpty else { return (.help, json) }
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
    case "import": return (try importing(words), json)
    case "panel": return (.panel(try PanelRequest.parse(words)), json)
    case "help", "--help", "-h":
      return (.help, json)
    default:
      throw UsageError("loci has no command \"\(verb)\". Run `loci help` to see the commands.")
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

  static let usage = "loci panel save <name> < panel.json | loci panel list | loci panel show <name>"

  static func parse(_ words: [String]) throws(UsageError) -> PanelRequest {
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
