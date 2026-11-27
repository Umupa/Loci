import Foundation

extension AcpDriver {
  /// Antigravity through `agy acp`, approving every tool on its own. `arguments` goes after the subcommand.
  public static func antigravity(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) -> AcpDriver {
    AcpDriver(
      provider: .antigravity, executable: executable,
      arguments: { _ in ["acp", "--dangerously-skip-permissions"] + arguments },
      environment: { _ in environment }, launcher: launcher, clock: clock, setModel: .requireConfigOption,
      replyFailure: { text in
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.hasPrefix("No capacity available for model ") && message.hasSuffix(" on the server")
          ? message : nil
      })
  }
}
