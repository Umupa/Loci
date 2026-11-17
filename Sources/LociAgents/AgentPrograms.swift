import Foundation
import LociModel

/// The agent programs installed on this Mac, ready to drive.
///
/// Programs started from a window opened in the Finder inherit only launchd's bare PATH, so `node` and the
/// like are missing; every program gets the PATH the person's own terminal has instead.
public struct AgentPrograms: Sendable {
  private let search: AgentSearch
  private let environment: [String: String]
  private let launcher: any ProgramLauncher

  public init(
    search: AgentSearch, environment: [String: String] = ProcessInfo.processInfo.environment,
    launcher: any ProgramLauncher = SystemLauncher()
  ) {
    self.search = search
    var environment = environment
    environment["PATH"] = search.directories.map { $0.path(percentEncoded: false) }.joined(separator: ":")
    self.environment = environment
    self.launcher = launcher
  }

  /// The driver for a provider, or `nil` when its program is not installed or Loci cannot drive it yet.
  public func driver(for provider: Mentor.Provider) -> (any AgentDriver)? {
    guard let cli = AgentCLI.all.first(where: { $0.provider == provider }),
      let executable = search.executable(named: cli.names)
    else { return nil }
    switch provider {
    case .pi:
      return PiDriver(executable: executable, environment: environment, launcher: launcher)
    case .omp:
      return OmpDriver(executable: executable, environment: environment, launcher: launcher)
    case .grok:
      return AcpDriver.grok(executable: executable, environment: environment, launcher: launcher)
    case .hermes:
      return AcpDriver.hermes(executable: executable, environment: environment, launcher: launcher)
    case .claudeCode:
      return ClaudeCodeDriver(executable: executable, environment: environment, launcher: launcher)
    case .codex:
      return CodexDriver(executable: executable, environment: environment, launcher: launcher)
    case .opencode:
      return OpenCodeDriver(executable: executable, environment: environment, launcher: launcher)
    case .antigravity:
      return AcpDriver.antigravity(executable: executable, environment: environment, launcher: launcher)
    case .cursor:
      return AcpDriver.cursor(executable: executable, environment: environment, launcher: launcher)
    case .fx:
      return nil
    }
  }
}
