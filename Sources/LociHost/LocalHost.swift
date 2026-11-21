import Foundation
import LociMedia
import LociModel
import LociStore

/// The host in this process, over the Loci folder and its database.
///
/// Commands run concurrently: the store and the database are values, and the database serializes its
/// own writes. All mutable state lives in the `Hub`.
public final class LocalHost: LociModel.Host, CommandHandler {
  let store: Store
  let database: StoreDatabase
  let environment: HostEnvironment
  let hub: Hub
  let loci: LociAgent
  let panels: PanelKeeper
  let library: LibraryRuntime
  /// Previews of the links Loci's replies show as cards.
  let links: LinkPreviewReader

  private init(
    store: Store, database: StoreDatabase, environment: HostEnvironment, prompts: Prompts, readingStateLost: Bool
  ) {
    self.store = store
    self.database = database
    self.environment = environment
    let hub = Hub(health: Health(database: .rebuilding, readingStateLost: readingStateLost, fileProblems: []))
    self.hub = hub
    let context = AgentContext(
      store: store, database: database, environment: environment,
      follower: Follower(store: store, database: database, hub: hub), prompts: prompts)
    let loci = LociAgent(context: context)
    self.loci = loci
    panels = PanelKeeper(context: context) { await loci.isWorking }
    library = LibraryRuntime(
      store: store, database: database, environment: environment,
      follower: Follower(store: store, database: database, hub: hub))
    links = LinkPreviewReader(network: environment.media.network)
  }

  /// Opens the database and starts serving from it at once, while the mirrors are rebuilt from the files
  /// in the background. A database that cannot be used is reported, not repaired.
  public static func start(root: URL, database url: URL, environment: HostEnvironment)
    async throws(HostStartError) -> LocalHost
  {
    let database: StoreDatabase
    do throws(DatabaseOpenError) {
      database = try StoreDatabase.open(at: url)
    } catch {
      switch error {
      case .unreadable(let reason): throw .databaseUnreadable(reason)
      case .newerVersion(let unknown): throw .databaseFromNewerVersion(unknownMigrations: unknown)
      }
    }
    return try await begin(
      store: Store(root: root, discard: environment.discard), database: database, environment: environment,
      readingStateLost: false)
  }

  /// Starts with a new database, setting the unusable one aside. Reading positions are lost, and `Health`
  /// says so.
  public static func startReplacingDatabase(root: URL, database url: URL, environment: HostEnvironment)
    async throws(HostStartError) -> LocalHost
  {
    let database: StoreDatabase
    do {
      database = try StoreDatabase.replace(at: url, now: environment.now()).database
    } catch {
      throw .storage(String(describing: error))
    }
    return try await begin(
      store: Store(root: root, discard: environment.discard), database: database, environment: environment,
      readingStateLost: true)
  }

  /// Gives Loci its folder before anything else, so the first turn finds its soul. Watching starts before
  /// the rebuild, and changes wait in order until it is done: a change made while the rebuild was reading is
  /// applied after the rebuild has written, never overwritten by it.
  static func begin(
    store: Store, database: StoreDatabase, environment: HostEnvironment, readingStateLost: Bool,
    rebuild: @escaping @Sendable (Store, StoreDatabase) async throws -> [FileProblem] = { store, database in
      try database.rebuild(from: store)
    }
  ) async throws(HostStartError) -> LocalHost {
    let prompts: Prompts
    do {
      prompts = try Prompts.bundled()
      try store.prepareAgent(soul: prompts.soul)
    } catch {
      throw .storage(String(describing: error))
    }
    let host = LocalHost(
      store: store, database: database, environment: environment, prompts: prompts, readingStateLost: readingStateLost)
    let changes = store.changes()
    let work = Task {
      await host.rebuild(using: rebuild)
      for await batch in changes { await host.follow(batch) }
    }
    let ticks = environment.ticks()
    let reviews = Task {
      for await _ in ticks {
        await host.loci.considerReview()
        await host.panels.consider()
      }
    }
    await host.hub.hold(work)
    await host.hub.hold(reviews)
    if let tool = environment.tool {
      try? store.writeSkill(named: "loci", ToolGuide.skill)
      await host.hub.hold(Task { await ToolGateway.serve(host, at: tool.socket) })
    }
    await host.discardSetAside()
    await host.library.queue.resume()
    return host
  }

  /// Stops watching the folder and stops Loci. Subscriptions stay open but receive nothing more.
  public func close() async {
    await library.queue.close()
    await library.translator.close()
    await library.picker.close()
    await discardSetAside()
    await panels.close()
    await loci.close()
    await hub.stop()
  }

  public func run<C: Command>(_ command: C) async throws(HostError) -> C.Reply {
    try await command.run(on: self)
  }

  public func subscribe<S: Subscription>(_ subscription: S) -> AsyncStream<Feed<S.Value>> {
    let (feed, continuation) = AsyncStream.makeStream(of: Feed<S.Value>.self)
    let watcher = Watcher(subscription, handler: self, continuation: continuation)
    let hub = hub
    let registration = Task {
      let id = await hub.add(watcher)
      await watcher.refresh()
      return id
    }
    continuation.onTermination = { _ in
      Task { await hub.remove(await registration.value) }
    }
    return feed
  }

  public func upload(_ file: LocalFile) async throws(HostError) -> Upload {
    let upload = Upload(id: environment.newID())
    await hub.keep(file.url, as: upload.id)
    return upload
  }

  public func localFile(_ place: LocalPlace) async -> LocalFile? {
    let url: URL?
    switch place {
    case .dataFolder: url = store.root
    case .agentFolder: url = store.agentFolder
    case .media(let item): url = try? store.mediaFile(of: item)
    case .item(let item): url = try? store.itemFolder(item)
    }
    return url.map(LocalFile.init)
  }

  public func health() async -> Health {
    await hub.current()
  }

  private func rebuild(using rebuild: @Sendable (Store, StoreDatabase) async throws -> [FileProblem]) async {
    do {
      await hub.rebuilt(problems: try await rebuild(store, database))
    } catch {
      await hub.failed(String(describing: error))
    }
    await hub.refresh([.everything])
  }

  /// Brings the database up to date with changed files, then tells the subscriptions they affect.
  func follow(_ changes: Set<ContentChange>) async {
    await Follower(store: store, database: database, hub: hub).follow(changes)
  }
}
