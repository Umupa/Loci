import Foundation
import LociMedia
import LociModel
import LociStore

/// What happens after a source's fetch has written its snapshot: by default the reminder conditions on it are
/// checked (`NextUpConditions`). Fetches of a source are handed on one at a time, in the order they were kept.
protocol SourceRefreshed: Sendable {
  func refreshed(_ source: SourceKey, _ snapshot: SourceSnapshot) async
}

/// Fetches sources and keeps what each fetch got, for `loci source save` and the fetching line alike. Every
/// fetch of a source is numbered when it starts and kept only through `SourceCommits`: one that started
/// before a fetch already kept is dropped, and the line's fetch is dropped too when the definition it ran
/// is no longer the saved one, so an old fetch never writes over a new definition's records, failures or
/// repair. A fetch that is kept writes the snapshot and series, wakes the panels that follow its entries
/// when some wait for them, and is handed to `refreshed`. One whose script fails often enough in a row
/// puts a repair in the inbox, once for each time it breaks.
struct SourceKeeper: Sendable {
  let context: AgentContext
  let connectors: ConnectorKeeper
  let refreshed: any SourceRefreshed
  var commits: SourceCommits { context.commits }

  private var database: StoreDatabase { context.database }

  /// One fetch, kept or not.
  func fetch(_ source: DataSource, in home: Home, at now: Timestamp) async -> Result<SourceResult, SourceFailure> {
    let key = SourceKey(home, source.name)
    let state = ((try? database.sourceSnapshot(key)) ?? nil)?.state
    let reader = SourceReader(source: key, connectors: connectors, pages: context.environment.media.sourcePages)
    do throws(SourceFailure) {
      return .success(
        try await context.environment.media.dataSources.fetch(source, state: state, now: now, elsewhere: reader))
    } catch {
      return .failure(error)
    }
  }

  /// Fetches the source as it is saved and keeps whatever came of it, unless it was changed meanwhile.
  func refresh(_ source: DataSource, in home: Home) async {
    let key = SourceKey(home, source.name)
    let ticket = await commits.ticket(for: key)
    let now = context.environment.now()
    let held = await context.ticket(for: home)
    switch await fetch(source, in: home, at: now) {
    case .success(let result):
      _ = try? await keep(result, of: source, in: home, ticket: ticket, held: held, saving: nil)
    case .failure(let failure): await keep(failure, of: source, in: home, at: now, ticket: ticket, held: held)
    }
  }

  /// Fetches a new definition once for real and saves it with what it got, or says why it was not saved.
  /// Refused when the home was archived, deleted or brought back before it could be kept.
  func save(_ source: DataSource, in home: Home, saving: Saving = Saving()) async throws(HostError) -> SourceOutcome {
    let key = SourceKey(home, source.name)
    let ticket = await commits.ticket(for: key)
    let held = await context.ticket(for: home)
    guard await context.holds(held) else { throw .invalidRequest(Self.closed) }
    let result: SourceResult
    switch await fetch(source, in: home, at: context.environment.now()) {
    case .success(let got): result = got
    case .failure(let failure): return .failed(failure.problems)
    }
    if let problems = await saving.check(result) { return .failed(problems) }
    guard try await keep(result, of: source, in: home, ticket: ticket, held: held, saving: saving) else {
      guard await context.holds(held) else { throw .invalidRequest(Self.closed) }
      if let grant = saving.grant, await !commits.isOpen(grant) { throw .invalidRequest(RepairGrant.over) }
      throw .invalidRequest(saving.refusal)
    }
    return .records(result.records)
  }

  /// How a save is checked: `check` on what came, before anything is kept, and `still` again as the
  /// definition is written; nothing is kept when either says no, or when the save is a repair's and its
  /// `grant` was closed first.
  struct Saving: Sendable {
    var check: @Sendable (SourceResult) async -> SourceProblems? = { _ in nil }
    var still: @Sendable () -> Bool = { true }
    var grant: RepairGrant?
    var refusal = "A newer fetch of this source was kept first; save it again."
  }

  /// Keeps what a fetch got: its sample, the snapshot and series, and the entries not seen before. Whether it
  /// was kept: nothing is when the home was archived, deleted or brought back since the fetch began, and the
  /// check and the writes are one, with no project closing or moving between them.
  private func keep(
    _ result: SourceResult, of source: DataSource, in home: Home, ticket: Int, held: HomeTicket, saving: Saving?
  ) async throws(HostError) -> Bool {
    let key = SourceKey(home, source.name)
    let folder = DataSourceFolder(home)
    let context = context
    let store = context.store
    let database = database
    let commits = commits
    let refreshed = refreshed
    let kept = try await context.steadily { () async throws(HostError) -> (SourceSnapshot, Task<Void, Never>)? in
      guard await context.holds(held) else { return nil }
      return try await attemptAsync {
        try await commits.commit(key, ticket: ticket, under: saving?.grant) { () throws -> SourceSnapshot? in
          if let saving {
            guard saving.still() else { return nil }
            try store.saveDataSource(source, in: folder)
          } else {
            guard store.dataSource(named: source.name, in: folder) == source else { return nil }
          }
          try store.keepSample(result.sample, of: source.name, in: folder)
          let snapshot = try database.recordFetch(
            key, records: result.records, state: result.state, at: result.sample.at)
          _ = try database.recordEntries(key, result.entries, at: result.sample.at)
          return snapshot
        } then: { snapshot in
          await refreshed.refreshed(key, snapshot)
        }
      }
    }
    guard let (_, handed) = kept else { return false }
    context.wakeFeeds(following: source.name, in: home, at: result.sample.at)
    await handed.value
    await context.follower.follow([.source(key), .timers])
    return true
  }

  /// Keeps a fetch that got nothing: the snapshot goes stale, and a script that failed counts toward the
  /// source's being broken. The sample a failed `parse` was given is kept until the source is broken, so
  /// its repair has the responses that broke it.
  private func keep(
    _ failure: SourceFailure, of source: DataSource, in home: Home, at now: Timestamp, ticket: Int, held: HomeTicket
  ) async {
    let key = SourceKey(home, source.name)
    let folder = DataSourceFolder(home)
    let context = context
    let store = context.store
    let database = database
    let commits = commits
    let committed = await context.steadily { () async -> (SourceSnapshot, Task<Void, Never>)? in
      guard await context.holds(held) else { return nil }
      return
        (try? await commits.commit(key, ticket: ticket) { () throws -> SourceSnapshot? in
          guard store.dataSource(named: source.name, in: folder) == source else { return nil }
          var script: SourceProblems?
          if case .script(let problems, let sample) = failure {
            script = problems
            let before = (try database.sourceSnapshot(key))?.isBroken ?? false
            if let sample, !before { try store.keepSample(sample, of: source.name, in: folder) }
          }
          return try database.recordFailure(key, script: script, at: now)
        }) ?? nil
    }
    guard let (snapshot, _) = committed else { return }
    if snapshot.isBroken, let since = snapshot.breakage?.since { raiseRepair(of: source.name, in: home, since: since) }
    await context.follower.follow([.source(key), .timers])
  }

  static let closed = "The project was archived or deleted while its source was fetched; nothing was kept."

  private func raiseRepair(of name: String, in home: Home, since: Timestamp) {
    let source = Event.Source.source(name, project: home.project)
    let open = (try? database.openEvents()) ?? []
    guard !open.contains(where: { $0.source == source }) else { return }
    _ = try? database.raise(Event(id: context.environment.newID(), source: source, due: since))
  }

  private func attemptAsync<Value>(_ body: () async throws -> Value) async throws(HostError) -> Value {
    do {
      return try await body()
    } catch {
      throw HostError(error)
    }
  }
}

/// The one place a fetch of a source is kept: numbered as it starts, kept only when no fetch that started
/// later was kept first, one at a time. What is done after a fetch is kept runs in the order fetches were
/// kept, each once the one before is through. A repair's grant is opened and closed here too, so a save
/// under it is kept only while it is open, and closing it says whether its repair kept one.
actor SourceCommits {
  private var started: [SourceKey: Int] = [:]
  private var kept: [SourceKey: Int] = [:]
  private var after: [SourceKey: Task<Void, Never>] = [:]
  /// Each open grant, with the fetch its repair kept, once it kept one.
  private var grants: [RepairGrant: Int?] = [:]

  func ticket(for source: SourceKey) -> Int {
    let ticket = started[source, default: 0] + 1
    started[source] = ticket
    return ticket
  }

  /// Runs `body` when the ticket is newer than any kept, and under `grant` only while it is open; `nil` when
  /// it is not, or `body` keeps nothing. What was kept is then handed to `then`, after what came of every
  /// fetch kept before; the task it runs in is given back.
  func commit<Value: Sendable>(
    _ source: SourceKey, ticket: Int, under grant: RepairGrant? = nil, _ body: @Sendable () throws -> Value?,
    then: @escaping @Sendable (Value) async -> Void = { _ in }
  ) throws -> (Value, Task<Void, Never>)? {
    guard ticket > kept[source, default: 0] else { return nil }
    if let grant, grants[grant] == nil { return nil }
    guard let value = try body() else { return nil }
    kept[source] = ticket
    if let grant { grants[grant] = ticket }
    let before = after[source]
    let handed = Task {
      await before?.value
      await then(value)
    }
    after[source] = handed
    return (value, handed)
  }

  func open(_ grant: RepairGrant) {
    grants[grant] = .some(nil)
  }

  func isOpen(_ grant: RepairGrant) -> Bool {
    grants[grant] != nil
  }

  /// Closes the grant: nothing more is kept under it. Whether its repair kept a fetch while it was open.
  func close(_ grant: RepairGrant) -> Bool {
    guard let mended = grants.removeValue(forKey: grant) else { return false }
    return mended != nil
  }
}
