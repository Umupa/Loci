import Foundation
import LociModel

/// Drives an agent that speaks the Agent Client Protocol over standard input and output.
public struct AcpDriver: AgentDriver {
  public let provider: Mentor.Provider

  private let executable: URL
  private let arguments: @Sendable (SessionConfiguration) -> [String]
  private let environment: [String: String]?
  private let launcher: any ProgramLauncher
  private let clock: any Clock<Duration>

  /// - Parameters:
  ///   - arguments: The program's arguments for a session with this configuration.
  ///   - environment: The program's whole environment; `nil` passes on this process's own.
  public init(
    provider: Mentor.Provider, executable: URL, arguments: @escaping @Sendable (SessionConfiguration) -> [String],
    environment: [String: String]? = nil, launcher: any ProgramLauncher = SystemLauncher(),
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.provider = provider
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.launcher = launcher
    self.clock = clock
  }

  /// Grok Build through `grok agent stdio`. `extra` goes before the subcommand, after the driver's own.
  public static func grok(
    executable: URL, extra: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) -> AcpDriver {
    AcpDriver(
      provider: .grok, executable: executable,
      arguments: { configuration in
        var all = ["--no-auto-update"]
        switch configuration.permission {
        case .ask: all += ["--permission-mode", "default"]
        case .full: all += ["--always-approve"]
        }
        all += extra + ["agent", "--no-leader"]
        if let model = configuration.model { all += ["--model", model] }
        return all + ["stdio"]
      },
      environment: environment, launcher: launcher, clock: clock)
  }

  public func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession {
    if let resume = configuration.resume, resume.provider != provider { throw .sessionNotFound }
    let program = try launcher.launch(
      Invocation(
        executable: executable, arguments: arguments(configuration),
        workingDirectory: configuration.workingDirectory, environment: environment))
    let channel = AcpChannel(program: program, clock: clock)
    do throws(AgentError) {
      _ = try await channel.request("initialize", Self.initialize(for: provider), within: .seconds(30))
      if provider == .cursor {
        _ = try await channel.request(
          "authenticate", .object(["methodId": .string("cursor_login")]), within: .seconds(30))
      }
      let folder = JSONValue.string(configuration.workingDirectory.path(percentEncoded: false))
      var params: [String: JSONValue] = ["cwd": folder, "mcpServers": .array([])]
      let method: String
      if let resume = configuration.resume {
        method = provider == .cursor ? "session/load" : "session/resume"
        params["sessionId"] = .string(resume.value)
      } else {
        method = "session/new"
      }
      let setup = try await channel.request(method, .object(params), within: .seconds(60))
      guard let id = setup["sessionId"]?.string ?? configuration.resume?.value else {
        throw AgentError.rejected(method)
      }
      if provider == .cursor, let model = configuration.model {
        let option = setup["configOptions"]?.array?.first {
          $0["category"]?.string == "model" || $0["id"]?.string == "model"
        }
        if let config = option?["id"]?.string {
          _ = try await channel.request(
            "session/set_config_option",
            .object(["sessionId": .string(id), "configId": .string(config), "value": .string(model)]),
            within: .seconds(30))
        } else {
          _ = try await channel.request(
            "session/set_model", .object(["sessionId": .string(id), "modelId": .string(model)]),
            within: .seconds(30))
        }
      }
      await channel.acceptUpdates()
      return AcpSession(
        handle: SessionHandle(provider: provider, value: id), channel: channel, window: Self.window(in: setup),
        permission: configuration.permission)
    } catch {
      await channel.shutDown(patience: .zero)
      throw error
    }
  }

  private static func initialize(for provider: Mentor.Provider) -> JSONValue {
    var capabilities: [String: JSONValue] = [
      "fs": .object(["readTextFile": .bool(false), "writeTextFile": .bool(false)]), "terminal": .bool(false),
    ]
    if provider == .cursor {
      capabilities["_meta"] = .object(["parameterizedModelPicker": .bool(true)])
    }
    return .object([
      "protocolVersion": .number(1), "clientCapabilities": .object(capabilities),
      "clientInfo": .object(["name": .string("loci"), "version": .string("1")]),
    ])
  }

  /// The context window of the session's model, when the agent lists its models.
  private static func window(in setup: JSONValue) -> Int? {
    let current = setup["models"]?["currentModelId"]?.string
    let models = setup["models"]?["availableModels"]?.array ?? []
    let model = models.first { $0["modelId"]?.string == current } ?? models.first
    return model?["_meta"]?["totalContextTokens"]?.int
  }
}
