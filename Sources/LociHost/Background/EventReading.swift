import Foundation
import LociModel
import LociStore

/// What the worker reads of an event: whether it is still wanted, what it is called, and which panels its
/// run may save.
extension AgentContext {
  /// An event of an archived project, or one deleted that can still come back, waits until the project is open
  /// again, and a project's review until it is remembered again; otherwise it is wanted while what raised it is
  /// still there.
  func isWanted(_ event: Event) -> EventWant {
    guard isActive(event.source.home) else { return .later }
    if case .review(_, let project?) = event.source, !isRemembered(project) { return .later }
    return isStillThere(event) ? .now : .never
  }

  /// Whether the project's review may run and write its memory.
  func isRemembered(_ project: Project.ID) -> Bool {
    (try? store.project(project))?.remembered == true
  }

  private func isStillThere(_ event: Event) -> Bool {
    let home = event.source.home
    switch event.source {
    case .schedule(let id, _):
      guard let schedule = try? database.schedule(id) else { return false }
      return !schedule.paused
    case .panel(let name, _, _): return store.home(home).panel(named: name)?.panel != nil
    case .followUp, .watch: return true
    case .review: return true
    case .source(let name, _):
      guard store.dataSource(named: name, in: DataSourceFolder(home)) != nil else { return false }
      return ((try? database.sourceSnapshot(SourceKey(home, name))) ?? nil)?.isBroken == true
    }
  }

  /// Whether the worker runs an event now, keeps it for later, or drops it.
  enum EventWant {
    case now, later, never
  }

  /// The panels of the run's home that its run may save, by name: a watch finding's may save any of them.
  func panels(of kind: Run.Kind) -> Set<String> {
    guard case .timers(let timed) = kind else { return [] }
    if timed.first.isWatch { return Set(store.home(kind.home).panels().compactMap(\.panel?.name)) }
    return Set(
      timed.sources.compactMap { source in
        switch source {
        case .panel(let name, _, _): return name
        case .schedule(let id, _):
          guard case .panel(let name)? = (try? database.schedule(id))??.destination else { return nil }
          return name
        case .followUp, .review, .source, .watch: return nil
        }
      })
  }

  func title(of source: Event.Source) -> String {
    switch source {
    case .panel(let name, _, _): store.home(source.home).panel(named: name)?.panel?.title ?? name
    case .schedule(let id, _): ((try? database.schedule(id)) ?? nil)?.title ?? id.description
    case .watch(let finding, _): finding.summary
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
    case .watch(let finding, _): return "watch: \(finding.summary)"
    case .followUp: return "follow-up due \(due): \(title(of: event.source))"
    case .review(let day, nil): return "the review of \(day)"
    case .review(let day, _?): return "the review of this project's \(day)"
    case .source(let name, _): return "the repair of the source \(name), broken since \(due)"
    }
  }

  /// For a repair, the source it may save, as it is now.
  func repairGrant(of kind: Run.Kind, run: Run.ID) -> RepairGrant? {
    guard case .timers(let timed) = kind, let source = timed.first.repair,
      let broken = store.dataSource(named: source.name, in: DataSourceFolder(source.home))
    else { return nil }
    return RepairGrant(run: run, source: source, broken: broken)
  }
}

extension Event {
  var isAsked: Bool {
    if case .panel(_, asked: true, _) = source { true } else { false }
  }

  var isReview: Bool {
    if case .review = source { true } else { false }
  }

  /// A review, a repair or a follow-up, which shares its run with nothing: a follow-up's result is said in the
  /// conversation it was set in, and only its own.
  var runsAlone: Bool {
    if case .followUp = source { return true }
    return deadline != nil || isReview || source.repair != nil
  }
}

extension Event.Source {
  var isWatch: Bool {
    if case .watch = self { true } else { false }
  }
}
