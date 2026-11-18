import LociModel
import LociStore

/// Every mentor's runs, made the first time each is needed: one for its course and one for each item it
/// reads along on. Runs keep going with no window open.
actor MentorRuntime {
  private struct Key: Hashable {
    let mentor: EntityID
    let scope: RunScope
  }

  private let context: RunContext
  private var runs: [Key: MentorRun] = [:]
  /// Mentors being deleted. Their files are still on disk for a moment, so without this a refresh in that
  /// moment would make them a new run that outlives the deletion.
  private var leaving: Set<EntityID> = []
  /// Items a question is being started on, so two questions sent at once cannot both start.
  private var asking: Set<EntityID> = []

  init(store: Store, database: StoreDatabase, environment: HostEnvironment, follower: Follower) {
    context = RunContext(store: store, database: database, environment: environment, follower: follower)
  }

  func run(of mentor: EntityID, scope: RunScope = .course) throws(HostError) -> MentorRun {
    guard !leaving.contains(mentor) else { throw .notFound(mentor.description) }
    let key = Key(mentor: mentor, scope: scope)
    if let run = runs[key] { return run }
    let run = try MentorRun(mentor: mentor, scope: scope, context: context)
    runs[key] = run
    return run
  }

  /// The runs that have been made on the item.
  func runs(on item: EntityID) -> [MentorRun] {
    runs.filter { $0.key.scope == .item(item) }.map(\.value)
  }

  /// Whether some mentor is answering on the item now.
  func isBusy(on item: EntityID) async -> Bool {
    if asking.contains(item) { return true }
    for run in runs(on: item) where !(await run.isIdle) { return true }
    return false
  }

  /// Starts a turn of the mentor's on the item, unless one is running there already.
  func ask(_ mentor: EntityID, on item: EntityID, _ prompt: Prompt, saying text: String?) async throws(HostError) {
    guard !asking.contains(item) else { throw .invalidRequest(MentorRun.busyOnItem) }
    asking.insert(item)
    defer { asking.remove(item) }
    for run in runs(on: item) where !(await run.isIdle) { throw .invalidRequest(MentorRun.busyOnItem) }
    try await run(of: mentor, scope: .item(item)).send(prompt, saying: text)
  }

  /// Stops the mentor's agents and deletes its own conversation, for a mentor that is being deleted. What
  /// it said on items stays. Until `forgotten(_:)`, the mentor has no run and gets none.
  func forget(_ mentor: EntityID) async {
    leaving.insert(mentor)
    let leavingRuns = runs.filter { $0.key.mentor == mentor }
    for key in leavingRuns.keys { runs[key] = nil }
    for run in leavingRuns.values { await run.close(forget: true) }
    if leavingRuns.keys.allSatisfy({ $0.scope != .course }) {
      try? context.database.deleteConversations(of: mentor)
    }
  }

  /// Stops every mentor answering on an item that is being deleted, and deletes its conversation.
  func forget(item: EntityID) async {
    let leavingRuns = runs.filter { $0.key.scope == .item(item) }
    for key in leavingRuns.keys { runs[key] = nil }
    for run in leavingRuns.values { await run.close(forget: false) }
    try? context.database.deleteConversations(on: item)
  }

  /// Applies a mentor's new agent settings to its live sessions. A mentor with no run has nothing open.
  func settingsChanged(_ mentor: Mentor) async {
    for (key, run) in runs where key.mentor == mentor.id { await run.settingsChanged(to: mentor) }
  }

  /// The deletion is over: the files are gone, or deleting them failed and the mentor stays.
  func forgotten(_ mentor: EntityID) {
    leaving.remove(mentor)
  }

  func close() async {
    for run in runs.values { await run.close(forget: false) }
    runs = [:]
  }
}
