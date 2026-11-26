import Foundation

/// A `gh` command that only reads, as the app checked it: a command and subcommand that read, the words
/// after them, and options from a list of those that only shape what is read. `gh` is run with arguments
/// built again from these, every option written `--name=value`, and `gh api` always with `--method=GET`,
/// so nothing `gh` could read differently from this check, such as `-XPOST`, ever reaches it.
public struct GitHubRead: Hashable, Sendable {
  /// `["pr", "view"]`, or `["api"]`.
  public let command: [String]
  /// The words after the command: numbers, names, a search, or for `api` the one REST endpoint.
  public let words: [String]
  /// By long name, in the order given; `nil` for an option that takes no value.
  public let options: [Option]

  public struct Option: Hashable, Sendable {
    public let name: String
    public let value: String?
  }

  /// The arguments `gh` is run with.
  public var arguments: [String] {
    let method = command == ["api"] ? ["--method=GET"] : []
    return command + method + words
      + options.map { option in "--\(option.name)" + (option.value.map { "=\($0)" } ?? "") }
  }

  /// Reads the words the companion gave; refused, with the reason, when anything in them is not known to only
  /// read.
  public init(checking given: [String]) throws(GitHubRefusal) {
    guard let first = given.first else { throw GitHubRefusal("Give gh a command, such as [\"pr\", \"view\", \"12\"].") }
    var rest = given.dropFirst()
    let table: [String: GitHubReads.Takes]
    if first == "api" {
      command = ["api"]
      table = GitHubReads.apiOptions
    } else {
      guard let subcommands = GitHubReads.reads[first] else {
        throw GitHubRefusal("gh \(first) is not a command that only reads. Allowed: \(GitHubReads.allowed).")
      }
      guard let subcommand = rest.first, subcommands.contains(subcommand) else {
        let named = rest.first.map { " \($0)" } ?? ""
        throw GitHubRefusal(
          "gh \(first)\(named) would change something or is not one that only reads; for \(first), only "
            + subcommands.sorted().joined(separator: ", ") + ".")
      }
      command = [first, subcommand]
      rest = rest.dropFirst()
      table = GitHubReads.options
    }
    var words: [String] = []
    var options: [Option] = []
    while let word = rest.popFirst() {
      guard word.hasPrefix("-") else {
        words.append(word)
        continue
      }
      let parts = word.split(separator: "=", maxSplits: 1).map(String.init)
      let given = parts[0]
      guard let (name, takes) = GitHubReads.option(given, in: table) else {
        throw GitHubRefusal(GitHubReads.unknown(given, in: command))
      }
      switch takes {
      case .nothing:
        guard parts.count == 1 else { throw GitHubRefusal("gh \(given) takes no value.") }
        options.append(Option(name: name, value: nil))
      case .value:
        guard let value = parts.count == 2 ? parts[1] : rest.popFirst() else {
          throw GitHubRefusal("gh \(given) needs a value.")
        }
        if let refusal = GitHubReads.refusal(of: name, value) { throw GitHubRefusal(refusal) }
        if name != "method" { options.append(Option(name: name, value: value)) }
      }
    }
    if command == ["api"] {
      guard words.count == 1, let endpoint = words.first else {
        throw GitHubRefusal("gh api takes one REST endpoint, such as repos/o/r/releases.")
      }
      if endpoint == "graphql" {
        throw GitHubRefusal("gh api graphql can change things; use a REST endpoint with GET.")
      }
    }
    self.words = words
    self.options = options
  }
}

/// Why `gh` was not run.
public struct GitHubRefusal: Error, Hashable, Sendable {
  public let reason: String

  public init(_ reason: String) {
    self.reason = reason
  }
}

/// What the app lets `gh` read with.
enum GitHubReads {
  /// The subcommands that read, by command.
  static let reads: [String: Set<String>] = [
    "pr": ["list", "view", "diff", "checks", "status"],
    "issue": ["list", "view", "status"],
    "repo": ["view", "list"],
    "release": ["list", "view"],
    "run": ["list", "view"],
    "workflow": ["list", "view"],
    "search": ["repos", "issues", "prs", "code", "commits"],
    "label": ["list"],
  ]

  enum Takes: Hashable {
    case nothing, value
  }

  /// The options of the reading subcommands that only shape what is read, by long name, with their short ones.
  static let options: [String: Takes] = [
    "repo": .value, "limit": .value, "state": .value, "json": .value, "jq": .value, "template": .value,
    "search": .value, "label": .value, "author": .value, "assignee": .value, "base": .value, "head": .value,
    "job": .value, "branch": .value, "status": .value, "sort": .value, "order": .value, "owner": .value,
    "language": .value, "created": .value, "updated": .value, "event": .value, "user": .value, "attempt": .value,
    "comments": .nothing, "log": .nothing, "log-failed": .nothing, "verbose": .nothing, "patch": .nothing,
    "name-only": .nothing, "draft": .nothing,
  ]

  /// The options of `gh api` that only shape a GET. `method` is let through only as GET, and then dropped:
  /// the app writes `--method=GET` itself.
  static let apiOptions: [String: Takes] = [
    "jq": .value, "header": .value, "hostname": .value, "cache": .value, "template": .value, "preview": .value,
    "method": .value, "paginate": .nothing, "include": .nothing, "silent": .nothing, "slurp": .nothing,
    "verbose": .nothing,
  ]

  /// Short options, each one letter given alone; `-XPOST`, `-Lfoo` and the like are never read as these.
  static let short: [String: String] = [
    "-R": "repo", "-L": "limit", "-s": "state", "-q": "jq", "-t": "template", "-S": "search", "-l": "label",
    "-A": "author", "-a": "assignee", "-B": "base", "-j": "job", "-b": "branch", "-c": "comments", "-v": "verbose",
    "-u": "user",
  ]
  static let apiShort: [String: String] = [
    "-q": "jq", "-H": "header", "-t": "template", "-p": "preview", "-X": "method", "-i": "include",
  ]

  static func option(_ given: String, in table: [String: Takes]) -> (String, Takes)? {
    let shorts = table == apiOptions ? apiShort : short
    let name = given.hasPrefix("--") ? String(given.dropFirst(2)) : shorts[given]
    guard let name, let takes = table[name] else { return nil }
    return (name, takes)
  }

  /// Why a value may not be given to an option that otherwise only reads.
  static func refusal(of option: String, _ value: String) -> String? {
    switch option {
    case "method" where value.uppercased() != "GET": "gh api --method \(value) is not a GET; connectors only send GET."
    case "header" where value.lowercased().contains("method-override"):
      "gh api with a method-override header is not a GET; connectors only send GET."
    default: nil
    }
  }

  static func unknown(_ option: String, in command: [String]) -> String {
    let named = "gh \(command.joined(separator: " ")) \(option)"
    if ["--web", "-w"].contains(option) { return "\(named) opens a browser; connectors only read." }
    if command == ["api"] {
      return "\(named) is not an option that only shapes a GET; connectors only send GET, with --jq, --header, "
        + "--paginate and the like."
    }
    return "\(named) is not an option that only shapes what is read; write each option alone, such as --limit 5."
  }

  static var allowed: String {
    reads.keys.sorted().map { "\($0) \(reads[$0]?.sorted().joined(separator: "|") ?? "")" }.joined(separator: "; ")
      + "; api (GET only)"
  }
}
