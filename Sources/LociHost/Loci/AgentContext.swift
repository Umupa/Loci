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

  /// What Loci runs on now.
  var runtime: Runtime { agents.provisionalRuntime }

  /// `AGENTS.md` as it should be now.
  func instructions() throws(HostError) -> String {
    try attempt {
      try prompts.instructions(
        soul: store.agentText(.soul), profile: store.agentText(.profile), name: store.companionName())
    }
  }
}
