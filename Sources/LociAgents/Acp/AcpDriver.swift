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
  var processDirectory: URL?
  var supportsConfigOptions = false
  var replyFailure: (@Sendable (String) -> String?)?
  var configureSession:
    (@Sendable (AcpChannel, JSONValue, String, SessionConfiguration) async throws(AgentError) -> Void)?
  private let resumeMethod: String
  private let mode: (@Sendable (SessionConfiguration) -> String)?
  private let setModel: Bool
  private let authenticationMethod: String?
  private let clientMetadata: [String: JSONValue]

  /// - Parameters:
  ///   - arguments: The program's arguments for a session with this configuration.
  ///   - environment: The program's whole environment; `nil` passes on this process's own.
  ///   - resumeMethod: The ACP request that reopens an existing session.
  ///   - setModel: Selects the configured model over ACP instead of through launch arguments.
  ///   - mode: The approval mode to select over ACP; `nil` leaves it to launch arguments.
  public init(
    provider: Mentor.Provider, executable: URL, arguments: @escaping @Sendable (SessionConfiguration) -> [String],
    environment: [String: String]? = nil, launcher: any ProgramLauncher = SystemLauncher(),
    clock: any Clock<Duration> = ContinuousClock(), setModel: Bool = false,
    resumeMethod: String = "session/resume", mode: (@Sendable (SessionConfiguration) -> String)? = nil,
    authenticationMethod: String? = nil, clientMetadata: [String: JSONValue] = [:]
  ) {
    self.provider = provider
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.launcher = launcher
    self.clock = clock
    self.resumeMethod = resumeMethod
    self.mode = mode
    self.setModel = setModel
    self.authenticationMethod = authenticationMethod
    self.clientMetadata = clientMetadata
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
        workingDirectory: processDirectory ?? configuration.workingDirectory, environment: environment))
    let channel = AcpChannel(program: program, clock: clock)
    do throws(AgentError) {
      let initialized = try await channel.request("initialize", initialize, within: .seconds(30))
      if let authenticationMethod {
        _ = try await channel.request(
          "authenticate", .object(["methodId": .string(authenticationMethod)]), within: .seconds(30))
      }
      let folder = JSONValue.string(configuration.workingDirectory.path(percentEncoded: false))
      var params: [String: JSONValue] = ["cwd": folder, "mcpServers": .array([])]
      let method: String
      if let resume = configuration.resume {
        method = resumeMethod
        params["sessionId"] = .string(resume.value)
      } else {
        method = "session/new"
      }
      let setup: JSONValue
      do {
        setup = try await channel.request(method, .object(params), within: .seconds(60))
      } catch {
        if case .rejected = error, let resume = configuration.resume,
          initialized["agentCapabilities"]?["sessionCapabilities"]?["list"] != nil,
          await Self.isMissing(resume, directory: configuration.workingDirectory, channel: channel)
        {
          throw .sessionNotFound
        }
        throw error
      }
      guard let id = setup["sessionId"]?.string ?? configuration.resume?.value else {
        throw AgentError.rejected(method)
      }
      if setModel, let model = configuration.model {
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
      if let mode {
        _ = try await channel.request(
          "session/set_mode", .object(["sessionId": .string(id), "modeId": .string(mode(configuration))]),
          within: .seconds(20))
      }
      try await configureSession?(channel, setup, id, configuration)
      await channel.beginSession()
      return AcpSession(
        handle: SessionHandle(provider: provider, value: id), channel: channel,
        window: Self.window(in: setup, model: setModel ? configuration.model : nil),
        permission: configuration.permission, replyFailure: replyFailure)
    } catch {
      await channel.shutDown(patience: .zero)
      throw error
    }
  }

  private static func isMissing(_ handle: SessionHandle, directory: URL, channel: AcpChannel) async -> Bool {
    var params: [String: JSONValue] = ["cwd": .string(directory.path)]
    while let page = try? await channel.request("session/list", .object(params), within: .seconds(30)) {
      guard let sessions = page["sessions"]?.array else { return false }
      if sessions.contains(where: { $0["sessionId"]?.string == handle.value }) { return false }
      guard let cursor = page["nextCursor"]?.string else { return true }
      params["cursor"] = .string(cursor)
    }
    return false
  }

  private var initialize: JSONValue {
    var capabilities: [String: JSONValue] = [
      "fs": .object(["readTextFile": .bool(false), "writeTextFile": .bool(false)]), "terminal": .bool(false),
    ]
    if supportsConfigOptions {
      capabilities["session"] = .object(["configOptions": .object(["boolean": .object([:])])])
    }
    if !clientMetadata.isEmpty { capabilities["_meta"] = .object(clientMetadata) }
    return .object([
      "protocolVersion": .number(1),
      "clientCapabilities": .object(capabilities),
      "clientInfo": .object(["name": .string("loci"), "version": .string("1")]),
    ])
  }

  /// The context window of the session's model, when the agent lists its models.
  private static func window(in setup: JSONValue, model selected: String?) -> Int? {
    let current = selected ?? setup["models"]?["currentModelId"]?.string
    let models = setup["models"]?["availableModels"]?.array ?? []
    let model = models.first { $0["modelId"]?.string == current } ?? (current == nil ? models.first : nil)
    return model?["_meta"]?["totalContextTokens"]?.int
  }
}
