import Foundation
import LociModel

/// Looks for the agent command-line programs a mentor can run, and asks each one it finds for its version.
public struct AgentProbe: Sendable {
  private let launcher: any ProgramLauncher
  private let clock: any Clock<Duration>
  private let search: AgentSearch
  private let workingDirectory: URL
  private let patience: Duration

  public init(
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock(),
    search: AgentSearch, workingDirectory: URL = URL.homeDirectory, patience: Duration = .seconds(15)
  ) {
    self.launcher = launcher
    self.clock = clock
    self.search = search
    self.workingDirectory = workingDirectory
    self.patience = patience
  }

  /// What each of the ten providers is on this Mac, in `Mentor.Provider.allCases` order.
  public func installations() async -> [AgentInstallation] {
    var found: [AgentInstallation] = []
    for cli in AgentCLI.all {
      found.append(await installation(of: cli))
    }
    return found
  }

  private func installation(of cli: AgentCLI) async -> AgentInstallation {
    guard let executable = search.executable(named: cli.names) else { return .missing(cli.provider) }
    let version = await version(of: executable, listed: cli.versionArguments)
    return .installed(
      .init(provider: cli.provider, executable: executable, version: version, signIn: .unknown))
  }

  private func version(of executable: URL, listed arguments: [String]?) async -> String? {
    guard let arguments else { return nil }
    let said = await OneShot(launcher: launcher, clock: clock).output(
      Invocation(executable: executable, arguments: arguments, workingDirectory: workingDirectory),
      within: patience)
    return said.flatMap(AgentVersion.text(in:))
  }
}

extension AgentProbe {
  /// A probe that looks where this Mac keeps agent programs: the login shell's PATH first, because a window
  /// opened from Finder inherits only launchd's bare PATH.
  public static func forThisMac(
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock(),
    environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = URL.homeDirectory
  ) async -> AgentProbe {
    let search = await AgentSearch.forThisMac(
      launcher: launcher, clock: clock, environment: environment, home: home)
    return AgentProbe(launcher: launcher, clock: clock, search: search, workingDirectory: home)
  }
}
