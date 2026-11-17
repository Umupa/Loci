import Foundation
import LociModel

/// Drives Claude Code through its bidirectional JSON Lines protocol.
public struct ClaudeCodeDriver: AgentDriver {
  public let provider = Mentor.Provider.claudeCode
  private let executable: URL
  private let arguments: [String]
  private let environment: [String: String]?
  private let launcher: any ProgramLauncher
  private let clock: any Clock<Duration>
  private let makeSessionID: @Sendable () -> String

  public init(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock(),
    makeSessionID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) {
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.launcher = launcher
    self.clock = clock
    self.makeSessionID = makeSessionID
  }

  public func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession {
    if let resume = configuration.resume, resume.provider != provider { throw .sessionNotFound }
    let handle = configuration.resume ?? SessionHandle(provider: provider, value: makeSessionID())
    var arguments = [
      "--print", "--output-format", "stream-json", "--verbose", "--input-format", "stream-json",
      "--permission-prompt-tool", "stdio", "--include-partial-messages", "--permission-mode",
      configuration.permission == .full ? "bypassPermissions" : "default",
    ]
    if configuration.permission == .full { arguments += ["--allow-dangerously-skip-permissions"] }
    arguments += [configuration.resume == nil ? "--session-id" : "--resume", handle.value]
    if let model = configuration.model { arguments += ["--model", model] }
    let program = try launcher.launch(
      Invocation(
        executable: executable, arguments: arguments + self.arguments,
        workingDirectory: configuration.workingDirectory, environment: environment))
    let channel = ClaudeCodeChannel(program: program, clock: clock)
    do throws(AgentError) {
      _ = try await channel.request(.control("initialize"), within: .seconds(45))
      return ClaudeCodeSession(handle: handle, channel: channel, clock: clock)
    } catch {
      await channel.shutDown(patience: .zero)
      if configuration.resume != nil, case .exited(_, let text) = error,
        text.localizedCaseInsensitiveContains("No conversation found")
      {
        throw .sessionNotFound
      }
      throw error
    }
  }
}
