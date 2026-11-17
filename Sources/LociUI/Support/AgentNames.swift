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
}
