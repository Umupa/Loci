import Foundation
import LociModel

/// The agent programs installed on this Mac, ready to drive.
///
/// Programs started from a window opened in the Finder inherit only launchd's bare PATH, so `node` and the
/// like are missing; every program gets the PATH the person's own terminal has instead, with the `loci`
/// command first when the app has one. A login shell may put another `loci` first again, so its full path
/// is in `LOCI` too.
public struct AgentPrograms: Sendable {
  private let search: AgentSearch
  private let environment: [String: String]
  private let launcher: any ProgramLauncher

  public init(
    search: AgentSearch, tool: AgentTool? = nil, environment: [String: String] = ProcessInfo.processInfo.environment,
    launcher: any ProgramLauncher = SystemLauncher()
  ) {
    self.search = search
    var environment = environment
    let directories = (tool.map { [$0.folder] } ?? []) + search.directories
    environment["PATH"] = directories.map { $0.path(percentEncoded: false) }.joined(separator: ":")
    if let tool {
      environment[LocalCall.socketVariable] = tool.socket.path(percentEncoded: false)
      environment[LocalCall.commandVariable] = tool.folder.appending(path: "loci").path(percentEncoded: false)
    }
    self.environment = environment
    self.launcher = launcher
  }

  /// Why there is no driver for a provider: its program is nowhere to be found, or it is there and cannot
  /// be run.
  public func unavailability(of provider: Provider) -> AgentStartFailure {
    guard let cli = AgentCLI.all.first(where: { $0.provider == provider }), search.isBlocked(named: cli.names) else {
      return .notInstalled
    }
    return .wouldNotStart
  }

  /// The driver for a provider, or `nil` when its program is not installed or Loci cannot drive it yet.
  public func driver(for provider: Provider) -> (any AgentDriver)? {
    guard let cli = AgentCLI.all.first(where: { $0.provider == provider }),
      let executable = search.executable(named: cli.names)
    else { return nil }
    switch provider {
    case .pi:
      return PiDriver.pi(executable: executable, environment: environment, launcher: launcher)
    case .omp:
      return PiDriver.omp(executable: executable, environment: environment, launcher: launcher)
    case .grok:
      return AcpDriver.grok(executable: executable, environment: environment, launcher: launcher)
    case .hermes:
      return AcpDriver.hermes(executable: executable, environment: environment, launcher: launcher)
    case .claudeCode:
      return ClaudeCodeDriver.claudeCode(executable: executable, environment: environment, launcher: launcher)
    case .codex:
      return CodexDriver.codex(executable: executable, environment: environment, launcher: launcher)
    case .opencode:
      return AcpDriver.opencode(executable: executable, environment: environment, launcher: launcher)
    case .antigravity:
      return AcpDriver.antigravity(executable: executable, environment: environment, launcher: launcher)
    case .cursor:
      return AcpDriver.cursor(executable: executable, environment: environment, launcher: launcher)
    case .fx:
      return nil
    }
  }
}
