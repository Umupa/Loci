import Foundation
import LociAgents
import LociModel
import LociStore

struct HostAgents: Sendable {
  let store: Store
  let environment: HostEnvironment
  let library: LibraryContext

  struct Selection: Sendable {
    /// What is chosen; on the bundled Pi, the model is the companion's `ModelChoice`.
    let runtime: Runtime
    var credential: ModelServices.PiCredential?
    var configuration: PiConfiguration?

    /// The model the session is opened with, as the agent names it.
    var sessionModel: String? { configuration?.model ?? runtime.model }

    var instructionsScope: String {
      guard runtime.provider == .bundledPi else { return "" }
      guard let credential else { return "\nbundled-pi: unconfigured" }
      return "\nbundled-pi: \(credential.service.endpoint.absoluteString) \(credential.key != nil)"
    }
  }

  /// What the conversation chose, else its kind's default; `nil` before either.
  func chosenRuntime(of conversation: ConversationRef) -> Runtime? {
    if let own = try? library.database.runtime(of: conversation) { return own }
    return (try? store.settings())?.defaultRuntimes[conversation.kind]
  }

  /// What conversations of the kind run on: its default, else the first agent that can run.
  func kindDefault(_ kind: ConversationKind) async -> Runtime {
    if let set = (try? store.settings())?.defaultRuntimes[kind] { return set }
    return await detected()
  }

  /// What the conversation runs on: what it chose, else its kind's default, else the first agent that can run.
  func runtime(of conversation: ConversationRef) async -> Runtime {
    if let chosen = chosenRuntime(of: conversation) { return chosen }
    return await detected()
  }

  /// As `runtime(of:)` without looking for agents: what the host was started with stands in for the first that
  /// can run.
  func provisionalRuntime(of conversation: ConversationRef) -> Runtime {
    chosenRuntime(of: conversation) ?? environment.defaultRuntime
  }

  /// Gives the conversation `runtime` as its own, or lets it follow its kind's default when `runtime` is `nil` or
  /// the default. The main conversation is the only one of its kind, so what it chooses is its kind's default.
  func choose(_ runtime: Runtime?, for conversation: ConversationRef, at time: Timestamp) async throws(HostError) {
    if conversation == .main, let runtime { return try setDefault(runtime, for: .main) }
    let kindDefault = await kindDefault(conversation.kind)
    try attempt {
      if let runtime, runtime != kindDefault {
        try library.database.setRuntime(runtime, of: conversation, at: time)
      } else {
        try library.database.clearRuntime(of: conversation)
      }
    }
  }

  /// Makes `runtime` the kind's default. Conversations of the kind that chose the same follow the default from now.
  func setDefault(_ runtime: Runtime, for kind: ConversationKind) throws(HostError) {
    try attempt {
      try store.changeSettings { $0.defaultRuntimes[kind] = runtime }
      try library.database.dropRuntimes(equalTo: [kind: runtime])
    }
  }

  /// Up to 1.8.7 a conversation kept the runtime it first opened on. The ones still on their kind's latest choice
  /// follow it as their default from now; the others keep theirs as their own. The main conversation's is its
  /// kind's default.
  func settleUpgradedRuntimes() {
    guard let settings = try? store.settings(), settings.keptEveryRuntime else { return }
    var defaults = settings.defaultRuntimes
    if let main = try? library.database.runtime(of: .main) {
      defaults[.main] = main
      try? library.database.clearRuntime(of: .main)
    }
    try? library.database.dropRuntimes(equalTo: defaults)
    _ = try? store.changeSettings { $0.defaultRuntimes = defaults }
  }

  /// The first agent that can run: what the host was started with when it is installed, else the first installed
  /// CLI, else the bundled Pi.
  func detected() async -> Runtime {
    guard environment.bundledPi != nil else { return environment.defaultRuntime }
    let installed = await environment.detectAgents(false).compactMap { candidate -> Provider? in
      guard case .installed(let found) = candidate, found.provider != .fx else { return nil }
      return found.provider
    }
    if installed.contains(environment.defaultRuntime.provider) { return environment.defaultRuntime }
    return Runtime(provider: installed.first ?? .bundledPi)
  }

  /// What a session for `engine` opens on.
  func selection(for engine: SessionEngine) async -> Selection {
    switch engine {
    case .conversation(let conversation):
      return await selection(await runtime(of: conversation))
    case .toolModel:
      if let tool = await toolRuntime() { return await selection(tool) }
      return await selection(await runtime(of: .main))
    }
  }

  /// As `selection(for:)` without looking for agents.
  func provisionalRuntime(for engine: SessionEngine) -> Runtime {
    switch engine {
    case .conversation(let conversation): provisionalRuntime(of: conversation)
    case .toolModel: provisionalRuntime(of: .main)
    }
  }

  /// The bundled Pi on the tool model; `nil` while there is no tool model, or the bundled Pi is not on this Mac,
  /// when it starts downloading.
  private func toolRuntime() async -> Runtime? {
    guard environment.bundledPi != nil, let options = try? await library.models.options(),
      options.offers(options.toolModel), let tool = options.toolModel
    else { return nil }
    guard library.equipment.support.activePi() != nil else {
      let equipment = library.equipment
      Task { await equipment.install(.bundledPi, retry: false) }
      return nil
    }
    return Runtime(provider: .bundledPi, model: tool.runtimeModel)
  }

  func selection(_ runtime: Runtime) async -> Selection {
    guard runtime.provider == .bundledPi, let credential = try? await library.models.piCredential(for: runtime)
    else {
      return Selection(runtime: runtime)
    }
    let model = credential.service.choice.runtimeModel
    return Selection(
      runtime: Runtime(provider: .bundledPi, model: model, effort: runtime.effort), credential: credential,
      configuration: try? library.equipment.support.preparePiConfiguration(for: credential.service))
  }

  func driver(for selection: Selection) async -> (any AgentDriver)? {
    if selection.runtime.provider != .bundledPi {
      return await environment.agents(selection.runtime.provider)
    }
    return bundledDriver(selection)
  }

  func failure(for provider: Provider) async -> AgentStartFailure {
    if provider == .bundledPi {
      return library.equipment.support.activePi() == nil ? .notInstalled : .wouldNotStart
    }
    return await environment.unavailability(provider)
  }

  func installations(again: Bool) async -> [AgentInstallation] {
    let external = await environment.detectAgents(again)
    guard environment.bundledPi != nil else { return external }
    let bundled: AgentInstallation
    if let active = library.equipment.support.activePi() {
      let credential = try? await library.models.piCredential(for: Runtime(provider: .bundledPi))
      bundled = .installed(
        .init(
          provider: .bundledPi, executable: HostPath(active.executable), version: active.version,
          signIn: credential?.key == nil ? .signedOut : .signedIn))
    } else {
      bundled = .missing(.bundledPi)
    }
    let order = Provider.allCases
    return ([bundled] + external).sorted {
      (order.firstIndex(of: $0.provider) ?? order.count) < (order.firstIndex(of: $1.provider) ?? order.count)
    }
  }

  /// Every model the model services offer, as `ModelChoice.runtimeModel`, for the bundled Pi.
  func models(of provider: Provider) async -> [AgentModel] {
    guard provider == .bundledPi else { return await environment.models(provider) }
    let groups = (try? await library.models.options().groups) ?? []
    return groups.flatMap { $0.choices() }.map { AgentModel(id: $0.runtimeModel, name: $0.model) }
  }

  private func bundledDriver(_ selection: Selection) -> PiDriver? {
    guard let environment = environment.bundledPi, let credential = selection.credential, credential.key != nil,
      let configuration = selection.configuration, let active = library.equipment.support.activePi()
    else { return nil }
    return environment.driver(
      executable: active.executable, configuration: configuration, tool: self.environment.tool,
      key: credential.key)
  }
}
