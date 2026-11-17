import LociModel
import LociStore

/// Every mentor's run, made the first time it is needed. Runs keep going with no window open.
actor MentorRuntime {
  private let context: RunContext
  private var runs: [EntityID: MentorRun] = [:]
  let questions: PassageQuestions

  init(store: Store, database: StoreDatabase, environment: HostEnvironment, follower: Follower) {
    context = RunContext(store: store, database: database, environment: environment, follower: follower)
    questions = PassageQuestions(context: context)
  }

  func run(of mentor: EntityID) throws(HostError) -> MentorRun {
    if let run = runs[mentor] { return run }
    let run = try MentorRun(mentor: mentor, context: context)
    runs[mentor] = run
    return run
  }

  /// Stops the mentor's agents and deletes its conversation, for a mentor that is being deleted.
  func forget(_ mentor: EntityID) async {
    let run = runs.removeValue(forKey: mentor)
    await run?.close(forget: true)
    if run == nil { try? context.database.deleteConversations(of: mentor) }
    await questions.close(mentor)
  }

  func close() async {
    for run in runs.values { await run.close(forget: false) }
    runs = [:]
    await questions.close()
  }
}
