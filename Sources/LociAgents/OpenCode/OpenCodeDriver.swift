import Foundation
import LociModel

/// Drives OpenCode through its standard-input ACP transport.
public struct OpenCodeDriver: AgentDriver {
  public let provider = Mentor.Provider.opencode

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
    if let resume = configuration.resume, resume.provider != provider { throw .sessionNotFound }
    var environment = environment ?? ProcessInfo.processInfo.environment
    environment["OPENCODE_PERMISSION"] = configuration.permission == .ask ? #"{"*":"ask"}"# : #"{"*":"allow"}"#
    let program = try launcher.launch(
      .init(
        executable: executable, arguments: ["acp"] + arguments,
        workingDirectory: configuration.workingDirectory, environment: environment))
    let channel = OpenCodeChannel(program: program, clock: clock)
    do throws(AgentError) {
      let initialized = try await channel.request(
        "initialize",
        .object([
          "protocolVersion": .number(1), "clientCapabilities": .object([:]),
          "clientInfo": .object(["name": .string("Loci"), "version": .string("1.0")]),
        ]))
      guard initialized["protocolVersion"]?.int == 1 else { throw .rejected("Unsupported OpenCode ACP version") }
      var params: [String: JSONValue] = [
        "cwd": .string(configuration.workingDirectory.path), "mcpServers": .array([]),
      ]
      let handle: SessionHandle
      if let resume = configuration.resume {
        guard initialized["agentCapabilities"]?["loadSession"]?.bool == true else {
          throw .rejected("OpenCode cannot load sessions")
        }
        params["sessionId"] = .string(resume.value)
        do {
          _ = try await channel.request("session/load", .object(params))
        } catch {
          if case .rejected(let message) = error,
            message.lowercased().contains("not found") || message.lowercased().contains("notfound")
          {
            throw .sessionNotFound
          }
          throw error
        }
        handle = resume
      } else {
        let created = try await channel.request("session/new", .object(params))
        guard let id = created["sessionId"]?.string, !id.isEmpty else { throw .rejected("session/new") }
        handle = .init(provider: provider, value: id)
      }
      if let model = configuration.model {
        _ = try await channel.request(
          "session/set_model",
          .object([
            "sessionId": .string(handle.value), "modelId": .string(model),
          ]))
      }
      await channel.activate()
      return OpenCodeSession(handle: handle, channel: channel, clock: clock)
    } catch {
      await channel.shutDown(patience: .zero)
      throw error
    }
  }
}
