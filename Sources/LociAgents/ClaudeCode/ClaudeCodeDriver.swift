import Foundation
import LociModel

/// Drives Claude Code through its bidirectional JSON Lines protocol.
public struct ClaudeCodeDriver: AgentDriver {
  public let provider = Provider.claudeCode
  private let executable: URL
  private let arguments: [String]
  private let environment: [String: String]?
  private let launcher: any ProgramLauncher
  private let clock: any Clock<Duration>
  private let makeSessionID: @Sendable () -> String

  public static func claudeCode(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock(),
    makeSessionID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) -> ClaudeCodeDriver {
    ClaudeCodeDriver(
      executable: executable, arguments: arguments, environment: environment, launcher: launcher, clock: clock,
      makeSessionID: makeSessionID)
  }

  public func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession {
    if let resume = configuration.resume, resume.provider != provider { throw .sessionNotFound }
    let handle = configuration.resume ?? SessionHandle(provider: provider, value: makeSessionID())
    var arguments = [
      "--print", "--output-format", "stream-json", "--verbose", "--input-format", "stream-json",
      "--permission-prompt-tool", "stdio", "--include-partial-messages", "--permission-mode", "bypassPermissions",
      "--allow-dangerously-skip-permissions",
    ]
    arguments += [configuration.resume == nil ? "--session-id" : "--resume", handle.value]
    if let model = configuration.model { arguments += ["--model", model] }
    if let effort = configuration.effort, provider.efforts.contains(effort) {
      arguments += ["--effort", effort.rawValue]
    }
    let program = try launcher.launch(
      Invocation(
        executable: executable, arguments: arguments + self.arguments,
        workingDirectory: configuration.workingDirectory, environment: configuration.environment(over: environment)))
    let channel = ClaudeCodeChannel(program: program, clock: clock)
    do throws(AgentError) {
      _ = try await channel.request(.control("initialize"), within: .seconds(45))
      return ClaudeCodeSession(handle: handle, channel: channel, clock: clock)
    } catch {
      await channel.connection.shutDown(patience: .zero)
      if configuration.resume != nil, case .exited(_, let text) = error,
        text.localizedCaseInsensitiveContains("No conversation found")
      {
        throw .sessionNotFound
      }
      throw error
    }
  }
}
