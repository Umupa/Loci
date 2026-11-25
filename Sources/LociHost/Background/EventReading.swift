import Foundation
import LociModel
import LociStore

/// What the worker reads of an event: whether it is still wanted, what it is called, and which panels its
/// run may save.
extension AgentContext {
  /// An event is wanted while its home is active and what raised it is still there; a project's review only
  /// while the project is remembered.
  func isWanted(_ event: Event) -> Bool {
    let home = event.source.home
    guard isActive(home) else { return false }
    switch event.source {
    case .schedule(let id, _):
      guard let schedule = try? database.schedule(id) else { return false }
      return !schedule.paused
    case .panel(let name, _, _): return store.home(home).panel(named: name)?.panel != nil
    case .followUp: return true
    case .review(_, nil): return true
    case .review(_, let project?): return (try? store.project(project))?.remembered == true
    case .source(let name, _):
      guard store.dataSource(named: name, in: DataSourceFolder(home)) != nil else { return false }
      return ((try? database.sourceSnapshot(SourceKey(home, name))) ?? nil)?.isBroken == true
    }
  }

  /// The panels of the run's home that its run may save, by name.
  func panels(of kind: Run.Kind) -> Set<String> {
    guard case .timers(let timed) = kind else { return [] }
    return Set(
      timed.sources.compactMap { source in
        switch source {
        case .panel(let name, _, _): return name
        case .schedule(let id, _):
          guard case .panel(let name)? = (try? database.schedule(id))??.destination else { return nil }
          return name
        case .followUp, .review, .source: return nil
        }
      })
  }

  func title(of source: Event.Source) -> String {
    switch source {
    case .panel(let name, _, _): store.home(source.home).panel(named: name)?.panel?.title ?? name
    case .schedule(let id, _): ((try? database.schedule(id)) ?? nil)?.title ?? id.description
    case .followUp(let id, _): ((try? database.followUp(id)) ?? nil)?.what ?? id.description
    case .review(let day, _): "\(day)"
    case .source(let name, _): store.dataSource(named: name, in: DataSourceFolder(source.home))?.title ?? name
    }
  }

  func describe(_ event: Event) -> String {
    let due = TimeOfDay(of: event.due, in: environment.timeZone)
    switch event.source {
    case .panel(let name, let asked, _): return "panel \(name)" + (asked ? ", asked for" : ", due \(due)")
    case .schedule(let id, _):
      let name = ((try? database.schedule(id)) ?? nil)?.name ?? id.description
      return "schedule \(name), due \(due): \(title(of: event.source))"
    case .followUp: return "follow-up due \(due): \(title(of: event.source))"
    case .review(let day, nil): return "the review of \(day)"
    case .review(let day, _?): return "the review of this project's \(day)"
    case .source(let name, _): return "the repair of the source \(name), broken since \(due)"
    }
  }
}
