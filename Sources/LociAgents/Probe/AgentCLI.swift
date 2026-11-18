import LociModel

/// One agent command-line program: the names it is installed under, and how it says its version.
struct AgentCLI: Hashable, Sendable {
  let provider: Provider
  /// The names the program is installed under, the likeliest first.
  let names: [String]
  /// The arguments that make the program print its version; `nil` when it has no such flag.
  let versionArguments: [String]?

  /// The ten programs Loci can run on, in the order `Provider` lists them.
  static let all: [AgentCLI] = [
    AgentCLI(provider: .pi, names: ["pi-coding-agent", "pi"], versionArguments: ["--version"]),
    AgentCLI(provider: .omp, names: ["omp"], versionArguments: ["--version"]),
    AgentCLI(provider: .grok, names: ["grok"], versionArguments: ["--version"]),
    AgentCLI(provider: .antigravity, names: ["agy_acp_server.par"], versionArguments: nil),
    AgentCLI(provider: .cursor, names: ["cursor-agent"], versionArguments: ["--version"]),
    AgentCLI(provider: .fx, names: ["fx"], versionArguments: ["--version"]),
    AgentCLI(provider: .hermes, names: ["hermes"], versionArguments: ["--version"]),
    AgentCLI(provider: .claudeCode, names: ["claude"], versionArguments: ["--version"]),
    AgentCLI(provider: .codex, names: ["codex"], versionArguments: ["--version"]),
    AgentCLI(provider: .opencode, names: ["opencode"], versionArguments: ["--version"]),
  ]
}

/// A version in what a program printed.
enum AgentVersion {
  /// The whole answer, trimmed, when one of its words is a version like `1.2.3` or `v1.2.3-beta.1`.
  /// `nil` when none is, so a usage message is not taken for a version.
  static func text(in answer: String) -> String? {
    let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.split(whereSeparator: \.isWhitespace).contains(where: isVersion) else { return nil }
    return trimmed
  }

  static func isVersion(_ word: Substring) -> Bool {
    var rest = word
    if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }
    let halves = rest.split(separator: "-", maxSplits: 1)
    guard
      let numbers = halves.first?.split(separator: ".", omittingEmptySubsequences: false),
      numbers.count == 3,
      numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(digit) })
    else { return false }
    guard halves.count == 2 else { return true }
    let build = halves[1]
    return !build.isEmpty && build.allSatisfy { digit($0) || $0.isASCII && ($0.isLetter || ".-+".contains($0)) }
  }

  private static func digit(_ character: Character) -> Bool {
    character.isASCII && character.isNumber
  }
}
