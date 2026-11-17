import Foundation
import LociModel

/// How providers are named and which of them can be picked.
enum Agents {
  /// The program's own name, the same in every language.
  static func name(of provider: Mentor.Provider) -> String {
    switch provider {
    case .pi: "Pi"
    case .omp: "Oh My Pi"
    case .grok: "Grok"
    case .antigravity: "Antigravity"
    case .cursor: "Cursor"
    case .fx: "fx"
    case .hermes: "Hermes"
    case .claudeCode: "Claude Code"
    case .codex: "Codex"
    case .opencode: "OpenCode"
    }
  }

  /// Pi and Grok, which Loci is tested with, every provider found installed, and the one in use even if it is
  /// gone, so a picker never loses its selection. In `Mentor.Provider.allCases` order.
  static func choosable(_ installations: [AgentInstallation], keeping current: Mentor.Provider) -> [Mentor.Provider] {
    let installed = installations.compactMap { installation -> Mentor.Provider? in
      if case .installed(let found) = installation { found.provider } else { nil }
    }
    let offered = Set(installed + [.pi, .grok, current])
    return Mentor.Provider.allCases.filter(offered.contains)
  }

  /// The models a picker offers: what the agent lists, and the one in use even if it does not list it.
  static func offered(_ listed: [String], keeping current: String?) -> [String] {
    guard let current, !listed.contains(current) else { return listed }
    return [current] + listed
  }

  /// A model as people say it: a Claude alias capitalized, and Pi's provider prefix dropped.
  static func modelName(_ model: String) -> String {
    if ["fable", "opus", "sonnet", "haiku"].contains(model) { return model.capitalized }
    return model.split(separator: "/").last.map(String.init) ?? model
  }

  static func effortName(_ effort: ThinkingEffort) -> LocalizedStringResource {
    switch effort {
    case .off: .loci("effort.off")
    case .minimal: .loci("effort.minimal")
    case .low: .loci("effort.low")
    case .medium: .loci("effort.medium")
    case .high: .loci("effort.high")
    case .xhigh: .loci("effort.xhigh")
    case .max: .loci("effort.max")
    }
  }

  /// Installed agents first, then the missing ones, each in `Mentor.Provider.allCases` order.
  static func installedFirst(_ installations: [AgentInstallation]) -> [AgentInstallation] {
    let installed = installations.filter { if case .installed = $0 { true } else { false } }
    return installed + installations.filter { if case .missing = $0 { true } else { false } }
  }

  /// The version number in what a program printed about itself, such as `2.1.4` in `2.1.4 (Claude Code)`.
  static func version(_ printed: String) -> String? {
    printed.split(whereSeparator: \.isWhitespace).lazy.map { $0.trimmingPrefix("v") }
      .first { $0.first?.isNumber == true && $0.contains(".") }.map(String.init)
  }
}
