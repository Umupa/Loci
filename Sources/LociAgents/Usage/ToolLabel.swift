import Foundation

/// The name the usage page gives a tool call: the `loci` subcommand it ran, else the program a shell command
/// started, else the tool's own name.
public struct ToolLabel: Hashable, Sendable {
  public let name: String
  /// Whether the call changed something: a `loci` command that is not only reading, or a file written.
  public let writes: Bool

  /// A tool other than a shell, by the name the CLI gives it.
  public init(tool: String) {
    name = tool
    writes = Self.fileWriters.contains(tool)
  }

  /// A shell command, as the CLI ran it.
  public init(command: String) {
    if let words = Self.lociWords(in: command) {
      name = "loci " + words[0]
      writes = !Self.reads(words)
    } else {
      name = Self.program(in: command) ?? "shell"
      writes = false
    }
  }

  private static let fileWriters: Set<String> = ["Write", "Edit", "MultiEdit", "NotebookEdit", "apply_patch"]
  private static let readingCommands: Set<String> = [
    "help", "search", "show", "wait", "read", "repo", "recall", "connector",
  ]
  private static let readingVerbs: Set<String> = ["list", "show", "help"]

  private static func reads(_ words: [String]) -> Bool {
    readingCommands.contains(words[0]) || words.dropFirst().first.map(readingVerbs.contains) == true
  }

  private static func lociWords(in command: String) -> [String]? {
    let pattern =
      #/(?:^|[\s;&|(`])(?:"\$LOCI"|\$LOCI|"\$\{LOCI\}"|\$\{LOCI\}|loci)\s+([a-z][a-z-]*)(?:\s+([a-z][a-z-]*))?/#
    guard let match = command.firstMatch(of: pattern) else { return nil }
    return [String(match.1)] + (match.2.map { [String($0)] } ?? [])
  }

  private static let keywords: Set<String> = ["do", "then", "else", "time", "sudo", "env", "exec", "nohup", "{", "("]
  private static let builtins: Set<String> = [
    "cd", "for", "while", "until", "if", "fi", "done", "esac", "case", "export", "set", "unset", "local", "echo",
    "printf", "true", "false", "read", "}", ")", "[", "[[", "test",
  ]

  private static func program(in command: String) -> String? {
    for segment in command.split(whereSeparator: { ";&|\n".contains($0) }) {
      var words = segment.split(whereSeparator: \.isWhitespace).map(String.init)
      while let first = words.first, keywords.contains(first) { words.removeFirst() }
      guard let first = words.first, !builtins.contains(first), !isAssignment(first) else { continue }
      let bare = first.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`$(){}"))
      guard !bare.isEmpty, bare.first?.isLetter == true || bare.first == "/" || bare.first == "." else { continue }
      return URL(filePath: bare).lastPathComponent
    }
    return nil
  }

  private static func isAssignment(_ word: String) -> Bool {
    guard let equals = word.firstIndex(of: "=") else { return false }
    let name = word[..<equals]
    return !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
  }
}
