import Foundation
import LociModel

/// Drives Codex through the app-server's standard input and output.
public struct CodexDriver: AgentDriver {
  public let provider = Mentor.Provider.codex
  private let executable: URL
  private let arguments: [String]
  private let environment: [String: String]?
  private let launcher: any ProgramLauncher
  private let clock: any Clock<Duration>

  public init(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.launcher = launcher
    self.clock = clock
  }

  public func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession {
    if let resume = configuration.resume, resume.provider != .codex { throw .sessionNotFound }
    let program = try launcher.launch(
      .init(
        executable: executable, arguments: ["app-server"] + arguments,
        workingDirectory: configuration.workingDirectory, environment: environment))
    let channel = CodexChannel(program: program, clock: clock)
    do throws(AgentError) {
      _ = try await channel.request(
        "initialize",
        params: .object([
          "clientInfo": .object(["name": .string("loci"), "version": .string("0.1.0")]),
          "capabilities": .object(["experimentalApi": .bool(false)]),
        ]), within: .seconds(45))
      try await channel.send(.object(["method": .string("initialized")]))
      var params: [String: JSONValue] = [
        "cwd": .string(configuration.workingDirectory.path),
        "approvalPolicy": .string(configuration.permission == .ask ? "untrusted" : "never"),
        "approvalsReviewer": .string("user"),
        "sandbox": .string(configuration.permission == .ask ? "read-only" : "danger-full-access"),
      ]
      if let model = configuration.model { params["model"] = .string(model) }
      if let resume = configuration.resume { params["threadId"] = .string(resume.value) }
      let method = configuration.resume == nil ? "thread/start" : "thread/resume"
      let result: JSONValue
      do throws(AgentError) {
        result = try await channel.request(method, params: .object(params), within: .seconds(45))
      } catch {
        if configuration.resume != nil, case .rejected(let message) = error,
          Self.missing(message)
        {
          throw .sessionNotFound
        }
        throw error
      }
      guard let id = result["thread"]?["id"]?.string else { throw .rejected(method) }
      return CodexSession(handle: .init(provider: .codex, value: id), channel: channel)
    } catch {
      await channel.shutDown(patience: .zero)
      throw error
    }
  }

  private static func missing(_ message: String) -> Bool {
    let message = message.lowercased()
    return message.contains("thread")
      && ["not found", "no rollout found", "does not exist", "unknown thread"]
        .contains { message.contains($0) }
  }
}
