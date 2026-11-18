import Foundation
import LociModel

/// How one tool call reads in the conversation: what was done, and to what.
struct ToolTitle: Equatable {
  enum Action: Equatable {
    /// The command itself is the title.
    case ran
    case read, edited, created, searched
    /// A tool Loci has no word for, under the agent's own name for it.
    case used(String)
  }

  let action: Action
  /// The command, a file's name or the query; `nil` when the agent did not say.
  let object: String?

  init(_ tool: ToolActivity) {
    let subject = tool.subject.flatMap { $0.isEmpty ? nil : $0 }
    switch tool.kind {
    case .execute:
      action = .ran
      object = subject.map(Self.unwrapped) ?? tool.name
    case .read:
      action = .read
      object = subject.map(Self.fileName)
    case .edit:
      action = .edited
      object = subject.map(Self.fileName)
    case .create:
      action = .created
      object = subject.map(Self.fileName)
    case .search where Self.isWebSearch(tool.name):
      action = .searched
      object = subject
    case .search:
      action = .ran
      object = subject.map(Self.unwrapped) ?? tool.name
    case .other:
      action = .used(tool.name)
      object = subject
    }
  }

  /// The words before the object; `nil` for a command, which speaks for itself.
  var verb: LocalizedStringResource? {
    switch action {
    case .ran: nil
    case .read: .loci("tool.read")
    case .edited: .loci("tool.edited")
    case .created: .loci("tool.created")
    case .searched: .loci("tool.searched")
    case .used: nil
    }
  }

  /// A command or a tool's own name, set in monospace.
  var isCode: Bool {
    switch action {
    case .ran, .used: true
    case .read, .edited, .created, .searched: false
    }
  }

  /// The command a shell was asked to run, without the shell: `/bin/zsh -lc 'ls -a'` is `ls -a`.
  static func unwrapped(_ command: String) -> String {
    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let match = trimmed.firstMatch(of: /^(?:\S*\/)?(?:zsh|bash|sh)\s+-l?c\s+(?<body>[\s\S]+)$/) else {
      return trimmed
    }
    let body = String(match.body)
    if body.count >= 2, body.hasPrefix("'"), body.hasSuffix("'") {
      return String(body.dropFirst().dropLast()).replacing(#"'\''"#, with: "'")
    }
    if body.count >= 2, body.hasPrefix("\""), body.hasSuffix("\"") {
      return String(body.dropFirst().dropLast()).replacing(#"\""#, with: "\"")
    }
    return body
  }

  static func fileName(_ path: String) -> String {
    let name = URL(filePath: path).lastPathComponent
    return name.isEmpty ? path : name
  }

  private static func isWebSearch(_ name: String) -> Bool {
    let plain = name.lowercased().filter(\.isLetter)
    return plain == "websearch" || plain == "search" || plain == "googlesearch"
  }
}

/// What a run of tool calls did, counted by action: three commands run and two files read.
struct ToolTally: Equatable {
  var ran = 0
  var read = 0
  var edited = 0
  var created = 0
  var searched = 0
  var used = 0

  init(_ tools: [ToolActivity]) {
    for tool in tools {
      switch ToolTitle(tool).action {
      case .ran: ran += 1
      case .read: read += 1
      case .edited: edited += 1
      case .created: created += 1
      case .searched: searched += 1
      case .used: used += 1
      }
    }
  }

  /// One phrase per action that happened, in a fixed order.
  var phrases: [LocalizedStringResource] {
    var phrases: [LocalizedStringResource] = []
    if ran > 0 { phrases.append(.loci("tools.ran \(ran)")) }
    if read > 0 { phrases.append(.loci("tools.read \(read)")) }
    if created > 0 { phrases.append(.loci("tools.created \(created)")) }
    if edited > 0 { phrases.append(.loci("tools.edited \(edited)")) }
    if searched > 0 { phrases.append(.loci("tools.searched \(searched)")) }
    if used > 0 { phrases.append(.loci("tools.used \(used)")) }
    return phrases
  }
}
