import Foundation

extension AcpDriver {
  /// Cursor through `cursor-agent acp`. `arguments` holds root CLI options before the subcommand.
  public static func cursor(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) -> AcpDriver {
    AcpDriver(
      provider: .cursor, executable: executable, arguments: { _ in arguments + ["acp"] },
      environment: { _ in environment }, launcher: launcher, clock: clock, setModel: .preferConfigOption,
      resumeMethod: "session/load", authenticationMethod: "cursor_login",
      clientMetadata: ["parameterizedModelPicker": .bool(true)])
  }
}
