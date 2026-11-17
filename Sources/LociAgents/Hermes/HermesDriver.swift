import Foundation

extension AcpDriver {
  /// Hermes through `hermes acp`, with model and approval mode selected over ACP.
  public static func hermes(
    executable: URL, environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) -> AcpDriver {
    AcpDriver(
      provider: .hermes, executable: executable, arguments: { _ in ["acp"] },
      environment: environment, launcher: launcher, clock: clock, resumeMethod: "session/load",
      modelViaProtocol: true, mode: { $0.permission == .ask ? "default" : "dont_ask" })
  }
}
