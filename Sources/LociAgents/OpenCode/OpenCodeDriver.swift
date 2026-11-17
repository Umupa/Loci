import Foundation
import LociModel

/// Drives OpenCode through its standard-input ACP transport.
public struct OpenCodeDriver: AgentDriver {
  public let provider = Mentor.Provider.opencode

  private let executable: URL
  private let arguments: [String]
  private let environment: [String: String]?
  private let launcher: any ProgramLauncher
  private let clock: any Clock<Duration>

  public init(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.launcher = launcher
    self.clock = clock
  }

  public func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession {
    var environment = environment ?? ProcessInfo.processInfo.environment
    environment["OPENCODE_PERMISSION"] = configuration.permission == .ask ? #"{"*":"ask"}"# : #"{"*":"allow"}"#
    return try await AcpDriver(
      provider: provider, executable: executable, arguments: { [arguments] _ in ["acp"] + arguments },
      environment: environment, launcher: launcher, clock: clock, setModel: true
    ).open(configuration)
  }
}
