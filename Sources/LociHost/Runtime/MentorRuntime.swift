import LociModel
import LociStore

/// Every mentor's run, made the first time it is needed. Runs keep going with no window open.
actor MentorRuntime {
  private let context: RunContext
  private var runs: [EntityID: MentorRun] = [:]
  /// Mentors being deleted. Their files are still on disk for a moment, so without this a refresh in that
  /// moment would make them a new run that outlives the deletion.
  private var leaving: Set<EntityID> = []
  let questions: PassageQuestions

  init(store: Store, database: StoreDatabase, environment: HostEnvironment, follower: Follower) {
    context = RunContext(store: store, database: database, environment: environment, follower: follower)
    questions = PassageQuestions(context: context)
  }

  func run(of mentor: EntityID) throws(HostError) -> MentorRun {
    guard !leaving.contains(mentor) else { throw .notFound(mentor.description) }
    if let run = runs[mentor] { return run }
    let run = try MentorRun(mentor: mentor, context: context)
    runs[mentor] = run
    return run
  }

  /// Stops the mentor's agents and deletes its conversation, for a mentor that is being deleted. Until
  /// `forgotten(_:)`, the mentor has no run and gets none.
  func forget(_ mentor: EntityID) async {
    leaving.insert(mentor)
    let run = runs.removeValue(forKey: mentor)
    await run?.close(forget: true)
    if run == nil { try? context.database.deleteConversations(of: mentor) }
    await questions.close(mentor)
  }

  /// The deletion is over: the files are gone, or deleting them failed and the mentor stays.
  func forgotten(_ mentor: EntityID) {
    leaving.remove(mentor)
  }

  func close() async {
    for run in runs.values { await run.close(forget: false) }
    runs = [:]
    await questions.close()
  }
}
