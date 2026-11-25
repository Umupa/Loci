import Foundation
import LociModel
import LociStore

/// Loci: one run per conversation, made the first time each is needed. Runs keep going with no window open.
actor LociAgent {
  let context: AgentContext
  private var runs: [ConversationRef: AgentRun] = [:]
  /// Items being deleted. Their files are still on disk for a moment, so without this a refresh in that
  /// moment would make them a new run that outlives the deletion.
  private var leaving: Set<ConversationRef> = []

  init(context: AgentContext) {
    self.context = context
  }

  func run(of conversation: ConversationRef) throws(HostError) -> AgentRun {
    let tool: LocalSession
    switch conversation {
    case .main:
      tool = .conversation(conversation)
    case .item(let item):
      guard !leaving.contains(conversation) else { throw .notFound(item.description) }
      _ = try attempt { try context.store.item(item) }
      tool = .conversation(conversation)
    case .course(let course):
      guard !leaving.contains(conversation) else { throw .notFound(course.description) }
      _ = try attempt { try context.store.course(course) }
      if let run = runs[conversation] { return run }
      tool = .conversation(conversation)
    case .project(let project):
      guard !leaving.contains(conversation) else { throw .notFound(project.description) }
      _ = try attempt { try context.store.project(project) }
      tool = .conversation(conversation)
    }
    if let run = runs[conversation] { return run }
    let run = try AgentRun(
      owner: .conversation(conversation), home: conversation.home, session: tool, context: context)
    runs[conversation] = run
    return run
  }

  /// A conversation's run if it was made; asking does not make one.
  func existingRun(of conversation: ConversationRef) -> AgentRun? {
    runs[conversation]
  }

  /// Whether a turn is running in any conversation.
  var isWorking: Bool {
    get async { await work != nil }
  }

  /// A turn running in the main conversation, else in any other. The tool is told without what it printed,
  /// which the status does not show.
  var work: LociWork? {
    get async {
      let main = runs[.main].map { [$0] } ?? []
      for run in main + runs.filter({ $0.key != .main }).map(\.value) {
        if let turn = await run.snapshot.turn {
          return .answering(
            turn.latestTool.map {
              ToolActivity(id: $0.id, name: $0.name, kind: $0.kind, subject: $0.subject, output: "", state: $0.state)
            })
        }
      }
      return nil
    }
  }

  /// Says in the conversation's running turn that Loci put an item into the library.
  func saved(_ item: EntityID, in conversation: ConversationRef) async {
    await runs[conversation]?.saved(item)
  }

  /// Stops Loci answering on an item, course or project that is being deleted. Until `forgotten(_:)`, its
  /// conversation gets no run. The conversation itself stays until the deletion can no longer be undone.
  func forget(_ conversation: ConversationRef) async {
    leaving.insert(conversation)
    if let run = runs.removeValue(forKey: conversation) { await run.close() }
  }

  func forgotten(_ conversation: ConversationRef) {
    leaving.remove(conversation)
  }

  /// Stops every run.
  func close() async {
    for run in runs.values { await run.close() }
    runs = [:]
  }
}
