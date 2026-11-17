import Foundation

extension AcpDriver {
  /// Hermes through `hermes acp`, with model and approval mode selected over ACP.
  public static func hermes(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) -> AcpDriver {
    AcpDriver(
      provider: .hermes, executable: executable, arguments: { _ in ["acp"] + arguments },
      environment: { _ in environment }, launcher: launcher, clock: clock, setModel: .preferConfigOption,
      resumeMethod: "session/load", mode: "dont_ask")
  }
}
