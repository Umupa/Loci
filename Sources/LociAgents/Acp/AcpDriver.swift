import Foundation
import LociModel

/// Drives an agent that speaks the Agent Client Protocol over standard input and output.
public struct AcpDriver: AgentDriver {
  public let provider: Provider

  private let executable: URL
  private let arguments: @Sendable (SessionConfiguration) -> [String]
  private let environment: @Sendable (SessionConfiguration) -> [String: String]?
  private let launcher: any ProgramLauncher
  private let clock: any Clock<Duration>
  private let processDirectory: URL?
  private let replyFailure: (@Sendable (String) -> String?)?
  private let resumeMethod: String
  /// The session mode that lets the agent work without asking, when it has modes.
  private let mode: String?
  private let setModel: ModelSelection?
  private let authenticationMethod: String?
  private let clientMetadata: [String: JSONValue]

  enum ModelSelection {
    case preferConfigOption, requireConfigOption

    func selector(in setup: JSONValue) throws(AgentError) -> String? {
      let options = setup["configOptions"]?.array ?? []
      switch self {
      case .preferConfigOption:
        return options.first { $0["category"]?.string == "model" || $0["id"]?.string == "model" }?["id"]?.string
      case .requireConfigOption:
        guard
          let id =
            (options.first { $0["id"]?.string == "model" && $0["type"]?.string != "boolean" }
            ?? options.first {
              $0["category"]?.string == "model" && $0["id"]?.string != "provider" && $0["type"]?.string != "boolean"
            })?["id"]?.string
        else { throw .rejected("Antigravity did not advertise a model selector") }
        return id
      }
    }
  }

  init(
    provider: Provider, executable: URL, arguments: @escaping @Sendable (SessionConfiguration) -> [String],
    environment: @escaping @Sendable (SessionConfiguration) -> [String: String]? = { _ in nil },
    launcher: any ProgramLauncher = SystemLauncher(),
    clock: any Clock<Duration> = ContinuousClock(), setModel: ModelSelection? = nil,
    resumeMethod: String = "session/resume", mode: String? = nil,
    authenticationMethod: String? = nil, clientMetadata: [String: JSONValue] = [:],
    processDirectory: URL? = nil, replyFailure: (@Sendable (String) -> String?)? = nil
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
    self.processDirectory = processDirectory
    self.replyFailure = replyFailure
  }

  /// Grok Build through `grok agent stdio`. `arguments` goes before the subcommand, after the driver's own.
  public static func grok(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) -> AcpDriver {
    AcpDriver(
      provider: .grok, executable: executable,
      arguments: { configuration in
        var all = ["--no-auto-update", "--always-approve"]
        all += arguments + ["agent", "--no-leader"]
        if let model = configuration.model { all += ["--model", model] }
        return all + ["stdio"]
      },
      environment: { _ in environment }, launcher: launcher, clock: clock)
  }

  public func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession {
    if let resume = configuration.resume, resume.provider != provider { throw .sessionNotFound }
    let program = try launcher.launch(
      Invocation(
        executable: executable, arguments: arguments(configuration),
        workingDirectory: processDirectory ?? configuration.workingDirectory,
        environment: configuration.environment(over: environment(configuration))))
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
      if setModel == .preferConfigOption {
        try await selectModel(configuration, setup: setup, session: id, channel: channel)
      }
      if let mode {
        _ = try await channel.request(
          "session/set_mode", .object(["sessionId": .string(id), "modeId": .string(mode)]),
          within: .seconds(20))
      }
      if setModel == .requireConfigOption {
        let options = try await selectModel(configuration, setup: setup, session: id, channel: channel)
        try await selectEffort(configuration, among: options ?? setup, session: id, channel: channel)
      }
      await channel.beginSession()
      return AcpSession(
        handle: SessionHandle(provider: provider, value: id), channel: channel,
        window: Self.window(in: setup, model: setModel == .preferConfigOption ? configuration.model : nil),
        clock: clock, replyFailure: replyFailure)
    } catch {
      await channel.connection.shutDown(patience: .zero)
      throw error
    }
  }

  /// What the agent answered with when the model was set through its configuration options: the options as they
  /// are for that model. `nil` when no model was set or it was set another way.
  @discardableResult
  private func selectModel(
    _ configuration: SessionConfiguration, setup: JSONValue, session: String, channel: AcpChannel
  ) async throws(AgentError) -> JSONValue? {
    guard let setModel, let model = configuration.model else { return nil }
    if let config = try setModel.selector(in: setup) {
      return try await channel.request(
        "session/set_config_option",
        .object(["sessionId": .string(session), "configId": .string(config), "value": .string(model)]),
        within: setModel == .requireConfigOption ? .seconds(15) : .seconds(30))
    }
    _ = try await channel.request(
      "session/set_model", .object(["sessionId": .string(session), "modelId": .string(model)]),
      within: .seconds(30))
    return nil
  }

  /// Sets the thinking level when the model offers the one asked for; a model that offers none, or not that one,
  /// thinks as it does by default.
  private func selectEffort(
    _ configuration: SessionConfiguration, among answer: JSONValue, session: String, channel: AcpChannel
  ) async throws(AgentError) {
    guard let effort = configuration.effort?.rawValue,
      let option = (answer["configOptions"]?.array ?? []).first(where: { $0["category"]?.string == "thought_level" }),
      let config = option["id"]?.string,
      (option["options"]?.array ?? []).contains(where: { $0["value"]?.string == effort })
    else { return }
    _ = try await channel.request(
      "session/set_config_option",
      .object(["sessionId": .string(session), "configId": .string(config), "value": .string(effort)]),
      within: .seconds(15))
  }

  private static func isMissing(_ handle: SessionHandle, directory: URL, channel: AcpChannel) async -> Bool {
    var params: [String: JSONValue] = ["cwd": .string(directory.path(percentEncoded: false))]
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
    if setModel == .requireConfigOption {
      capabilities["session"] = .object(["configOptions": .object(["boolean": .object([:])])])
    }
    if !clientMetadata.isEmpty { capabilities["_meta"] = .object(clientMetadata) }
    return .object([
      "protocolVersion": .integer(1),
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
