import Foundation
import LociModel

/// Drives omp through the shared Pi-family RPC implementation.
public struct OmpDriver: AgentDriver {
  public let provider = Mentor.Provider.omp

  private let driver: PiDriver

  public init(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) {
    driver = PiDriver(
      variant: .omp, executable: executable, arguments: arguments, environment: environment, launcher: launcher,
      clock: clock)
  }

  public func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession {
    try await driver.open(configuration)
  }
}
