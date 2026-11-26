import Foundation
import LociAgents
import LociMedia
import LociModel
import LociStore

/// What a host takes from the outside world, so tests can choose it.
public struct HostEnvironment: Sendable {
  public let newID: @Sendable () -> EntityID
  public let now: @Sendable () -> Timestamp
  /// Where the person is, which decides what day it is for notes, diaries and the daily review.
  public let timeZone: TimeZone
  /// What Loci runs on until one is chosen in the settings.
  public let defaultRuntime: Runtime
  /// How deleted items leave the disk.
  public let discard: Discard
  /// The driver for a provider's program, or `nil` when it cannot be run here.
  public let agents: @Sendable (Provider) async -> (any AgentDriver)?
  /// Why a provider has no driver: its program is not installed, or it is there and cannot be run.
  public let unavailability: @Sendable (Provider) async -> AgentStartFailure
  /// What each provider is on this Mac. `again` looks afresh, so a program installed since is found and
  /// can be driven; otherwise what was found last may be given.
  public let detectAgents: @Sendable (_ again: Bool) async -> [AgentInstallation]
  /// The models a provider's program offers, in the names it takes.
  public let models: @Sendable (Provider) async -> [String]
  /// When to see whether the daily review is due: every minute in the app.
  public let ticks: @Sendable () -> AsyncStream<Void>
  /// The programs, network and recognizer the library uses to fetch and transcribe.
  public let media: MediaEnvironment
  public let modelKeys: (any ModelKeyStore)?
  public let modelClient: ModelClient
  public let modelParallelism: Int
  /// What writes translations, chapters and key points with a model service; `nil` asks the service itself
  /// through `modelClient`.
  public let modelWriter: (@Sendable (ModelService) -> any TranscriptAgent)?
  public let bundledPi: BundledPiEnvironment?
  /// Waits a moment: how long a running turn holds what it said before showing it, so that the words
  /// streaming in are shown a few at a time.
  public let wait: @Sendable (Duration) async -> Void
  /// The `loci` command Loci puts things in the library with, and the socket the host answers it on;
  /// `nil` when the app has none, such as outside its bundle.
  public let tool: AgentTool?
  public let sourceCache: URL?
  public let gitExecutable: URL
  /// Tells macOS the app is doing work no window shows, so it does not nap while a run goes on; the
  /// activity ends when the run does.
  public let activity: @Sendable (_ reason: String) -> Activity
  public let connect: ConnectEnvironment
  /// Where the CLIs keep their session files, which the usage page reads.
  public let sessionFiles: SessionFolders
  /// Whether a window of the app is in front, which decides how often sources are fetched.
  public let inFront: @Sendable () async -> Bool

  public init(
    newID: @escaping @Sendable () -> EntityID, now: @escaping @Sendable () -> Timestamp, timeZone: TimeZone = .gmt,
    defaultRuntime: Runtime, discard: Discard, agents: @escaping @Sendable (Provider) async -> (any AgentDriver)?,
    unavailability: @escaping @Sendable (Provider) async -> AgentStartFailure = { _ in .notInstalled },
    detectAgents: @escaping @Sendable (_ again: Bool) async -> [AgentInstallation] = { _ in [] },
    models: @escaping @Sendable (Provider) async -> [String] = { _ in [] },
    ticks: @escaping @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } },
    media: MediaEnvironment = .disconnected,
    wait: (@Sendable (Duration) async -> Void)? = nil,
    tool: AgentTool? = nil,
    modelKeys: (any ModelKeyStore)? = nil, modelClient: ModelClient = ModelClient(), modelParallelism: Int = 3,
    modelWriter: (@Sendable (ModelService) -> any TranscriptAgent)? = nil,
    bundledPi: BundledPiEnvironment? = nil, sourceCache: URL? = nil, gitExecutable: URL = URL(filePath: "/usr/bin/git"),
    activity: @escaping @Sendable (_ reason: String) -> Activity = { _ in Activity {} },
    connect: ConnectEnvironment = .disconnected, sessionFiles: SessionFolders = .none,
    inFront: @escaping @Sendable () async -> Bool = { true }
  ) {
    self.newID = newID
    self.now = now
    self.timeZone = timeZone
    self.defaultRuntime = defaultRuntime
    self.discard = discard
    self.agents = agents
    self.unavailability = unavailability
    self.detectAgents = detectAgents
    self.models = models
    self.ticks = ticks
    self.media = media
    self.wait = wait ?? { duration in try? await Task.sleep(for: duration) }
    self.tool = tool
    self.modelKeys = modelKeys
    self.modelClient = modelClient
    self.modelWriter = modelWriter
    self.modelParallelism = max(1, modelParallelism)
    self.bundledPi = bundledPi
    self.sourceCache = sourceCache
    self.gitExecutable = gitExecutable
    self.activity = activity
    self.connect = connect
    self.sessionFiles = sessionFiles
    self.inFront = inFront
  }

  /// The real clock and time zone, fresh identifiers, the Trash, and the agent programs installed on this Mac.
  /// The app comes to the front on a connector's page through `browserReturned`.
  public static func system(
    defaultRuntime: Runtime, tool: AgentTool? = nil, sourceCache: URL? = nil,
    browserReturned: @escaping @Sendable (ConnectorID) async -> Void = { _ in },
    inFront: @escaping @Sendable () async -> Bool = { true }
  ) -> HostEnvironment {
    let installed = InstalledAgents(tool: tool)
    return HostEnvironment(
      newID: { EntityID() }, now: { Timestamp(.now) }, timeZone: .current, defaultRuntime: defaultRuntime,
      discard: .toTrash, agents: { await installed.driver(for: $0) },
      unavailability: { await installed.unavailability(of: $0) },
      detectAgents: { await installed.detect(again: $0) }, models: { await installed.models(of: $0) },
      ticks: { everyMinute() }, media: .system(agents: { await installed.driver(for: $0) }), tool: tool,
      modelKeys: ModelKeychain(serviceName: "com.loci.native.dev.model-service"), bundledPi: BundledPiEnvironment(),
      sourceCache: sourceCache, activity: ProcessActivity.begin,
      connect: .system(
        githubLogin: { await installed.githubLogin() }, githubRead: { await installed.githubRead($0) },
        browserReturned: browserReturned),
      sessionFiles: .home(URL.homeDirectory, environment: ProcessInfo.processInfo.environment), inFront: inFront)
  }

  private static func everyMinute() -> AsyncStream<Void> {
    AsyncStream { continuation in
      let task = Task {
        while !Task.isCancelled {
          continuation.yield()
          try? await Task.sleep(for: .seconds(60))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

/// Looks for the agent programs the first time one is needed, which takes a moment: the login shell is asked
/// for its PATH. Looking again replaces what was found, so the drivers see a program installed since.
actor InstalledAgents {
  private let tool: AgentTool?
  private var search: Task<AgentSearch, Never>?
  private var found: [AgentInstallation]?
  private var listed: [Provider: [String]] = [:]

  init(tool: AgentTool?) {
    self.tool = tool
  }

  /// Asked once per provider; a program that listed nothing is asked again next time.
  func models(of provider: Provider) async -> [String] {
    if let models = listed[provider] { return models }
    let models = await ModelList(search: await currentSearch()).models(of: provider)
    if !models.isEmpty { listed[provider] = models }
    return models
  }

  func driver(for provider: Provider) async -> (any AgentDriver)? {
    AgentPrograms(search: await currentSearch(), tool: tool).driver(for: provider)
  }

  func unavailability(of provider: Provider) async -> AgentStartFailure {
    AgentPrograms(search: await currentSearch(), tool: tool).unavailability(of: provider)
  }

  func githubLogin() async -> GitHubLogin? {
    await GitHubCLI(search: await currentSearch()).login()
  }

  func githubRead(_ read: GitHubRead) async -> GitHubReply {
    await GitHubCLI(search: await currentSearch()).read(read)
  }

  func detect(again: Bool) async -> [AgentInstallation] {
    if !again, let found { return found }
    if again {
      search = nil
      listed = [:]
    }
    let probe = AgentProbe(search: await currentSearch())
    let installations = await probe.installations()
    found = installations
    return installations
  }

  private func currentSearch() async -> AgentSearch {
    let search = self.search ?? Task { await AgentSearch.forThisMac() }
    self.search = search
    return await search.value
  }
}
