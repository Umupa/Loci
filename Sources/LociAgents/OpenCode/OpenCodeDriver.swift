import Foundation

extension AcpDriver {
  /// OpenCode through its standard-input ACP transport.
  public static func opencode(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) -> AcpDriver {
    AcpDriver(
      provider: .opencode, executable: executable, arguments: { _ in ["acp"] + arguments },
      environment: { _ in
        var environment = environment ?? ProcessInfo.processInfo.environment
        environment["OPENCODE_PERMISSION"] = #"{"*":"allow"}"#
        return environment
      }, launcher: launcher, clock: clock, setModel: .preferConfigOption)
  }
}
