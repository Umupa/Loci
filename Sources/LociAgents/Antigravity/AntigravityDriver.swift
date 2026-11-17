import Foundation

extension AcpDriver {
  /// Antigravity's standalone `agy_acp_server.par`, launched beside its bundled resources.
  public static func antigravity(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) -> AcpDriver {
    AcpDriver(
      provider: .antigravity, executable: executable, arguments: { _ in arguments },
      environment: { _ in environment }, launcher: launcher, clock: clock, setModel: .requireConfigOption,
      mode: "yolo",
      processDirectory: executable.deletingLastPathComponent(),
      replyFailure: { text in
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.hasPrefix("No capacity available for model ") && message.hasSuffix(" on the server")
          ? message : nil
      })
  }
}
