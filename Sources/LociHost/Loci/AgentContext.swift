import LociModel
import LociStore

/// What every run shares: where things are kept, how to say something changed, and the texts Loci is given.
struct AgentContext: Sendable {
  let store: Store
  let database: StoreDatabase
  let environment: HostEnvironment
  let follower: Follower
  let prompts: Prompts
  let agents: HostAgents
  let feelings: FeelingsKeeper
  let life: HomeLife
  /// Where every fetch of a source is kept, and every repair's grant opened and closed.
  let commits = SourceCommits()

  /// What Loci runs on now.
  var runtime: Runtime { agents.provisionalRuntime }

  /// `AGENTS.md` of the home as it should be now. Refused for a project that is gone.
  func instructions(for home: Home) throws(HostError) -> String {
    let project: Project? =
      switch home {
      case .chat: nil
      case .project(let id): try attempt { try store.project(id) }
      }
    return try attempt {
      try prompts.instructions(
        soul: store.agentText(.soul), profile: store.agentText(.profile), name: store.companionName(),
        project: project)
    }
  }
}
