import LociModel

/// One agent command-line program and the names it is installed under. Each one prints its version for `--version`.
struct AgentCLI: Hashable, Sendable {
  let provider: Provider
  /// The names the program is installed under, the likeliest first.
  let names: [String]

  /// The ten programs Loci can run on, in the order `Provider` lists them.
  static let all: [AgentCLI] = [
    AgentCLI(provider: .pi, names: ["pi-coding-agent", "pi"]),
    AgentCLI(provider: .omp, names: ["omp"]),
    AgentCLI(provider: .grok, names: ["grok"]),
    AgentCLI(provider: .antigravity, names: ["agy"]),
    AgentCLI(provider: .cursor, names: ["cursor-agent"]),
    AgentCLI(provider: .fx, names: ["fx"]),
    AgentCLI(provider: .hermes, names: ["hermes"]),
    AgentCLI(provider: .claudeCode, names: ["claude"]),
    AgentCLI(provider: .codex, names: ["codex"]),
    AgentCLI(provider: .opencode, names: ["opencode"]),
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
