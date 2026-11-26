import Foundation
import LociModel
import LociStore

/// The reminder conditions: checked by the app each time a source gets new records, with no model in the way.
struct NextUpConditions: SourceRefreshed {
  let context: AgentContext

  /// Checks the conditions on the source against what it has now, and brings up a card for each that turned
  /// true. A home that is archived or gone is not checked.
  func refreshed(_ key: SourceKey, _ snapshot: SourceSnapshot) async {
    guard context.isActive(key.home) else { return }
    let now = context.environment.now()
    for condition in (try? context.database.nextUpConditions(on: key)) ?? [] {
      let (next, fired) = condition.step(snapshot, at: now)
      let declined = (try? context.database.nextUp(withKey: condition.key, in: condition.home))?.place == .declined
      guard !declined else { continue }
      if next != condition { try? context.database.saveNextUpCondition(next) }
      if let fired {
        _ = try? await context.put(.ask(question: condition.ask), what: fired, key: condition.key, in: condition.home)
      }
    }
  }
}

extension LocalHost {
  var nextUpConditions: NextUpConditions { NextUpConditions(context: loci.context) }

  /// The condition notes whether it holds now, so a source already past the threshold brings up no card.
  public func addNextUpCondition(_ command: AddNextUpCondition) async throws(HostError) -> NextUpCondition {
    let home = command.home
    guard store.dataSource(named: command.field.source, in: DataSourceFolder(home)) != nil else {
      throw .notFound("source \(command.field.source); save it with loci source save first")
    }
    let say = command.say.trimmingCharacters(in: .whitespacesAndNewlines)
    let question = command.question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !say.isEmpty, !question.isEmpty else { throw .invalidRequest("a condition needs --say and --ask") }
    let now = environment.now()
    var condition = NextUpCondition(
      id: environment.newID(), home: home, field: command.field, comparison: command.comparison,
      threshold: command.threshold, say: say, ask: question, createdAt: now)
    if let snapshot = try attempt({ try database.sourceSnapshot(condition.source) }) {
      condition = condition.step(snapshot, at: now).0
    }
    try attempt { try database.saveNextUpCondition(condition) }
    await follow([.nextUps])
    return condition
  }

  public func nextUpConditions(of home: Home) async throws(HostError) -> [NextUpCondition] {
    try attempt { try database.nextUpConditions(of: home) }
  }

  public func removeNextUpCondition(_ command: RemoveNextUpCondition) async throws(HostError) -> Done {
    guard try attempt({ try database.removeNextUpCondition(command.condition) }) else {
      throw .notFound("condition \(command.condition)")
    }
    await follow([.nextUps])
    return Done()
  }
}
