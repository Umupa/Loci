import Foundation

extension AcpDriver {
  /// Cursor through `cursor-agent acp`. `extra` holds root CLI options before the subcommand.
  public static func cursor(
    executable: URL, extra: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) -> AcpDriver {
    AcpDriver(
      provider: .cursor, executable: executable, arguments: { _ in extra + ["acp"] },
      environment: environment, launcher: launcher, clock: clock, setModel: true,
      authenticationMethod: "cursor_login", resumeMethod: "session/load",
      clientMetadata: ["parameterizedModelPicker": .bool(true)])
  }
}
