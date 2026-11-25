import Foundation
import LociModel
import LociStore

/// Once a minute, and when the app opens, finds the timers that came due and puts an event for each into the
/// inbox: schedules, panels' refreshes, follow-ups, and the daily review. It starts nothing itself. A timer
/// missed while the app was closed is raised once, however many times it was missed.
struct Scheduler {
  let context: AgentContext

  /// Raises what came due; whether anything was.
  @discardableResult
  func look() async -> Bool {
    let database = context.database
    let now = context.environment.now()
    let open = (try? database.openEvents()) ?? []
    var raised = false
    func raise(_ source: Event.Source, due: Timestamp) {
      guard !open.contains(where: { $0.source.sameTimer(as: source) }) else { return }
      let event = Event(id: context.environment.newID(), source: source, due: due)
      if (try? database.raise(event)) == true { raised = true }
    }
    let homes = Set(context.homes())
    for schedule in (try? database.schedules()) ?? [] where !schedule.paused && homes.contains(schedule.home) {
      let last = ((try? database.runs(of: schedule.ref, limit: 1)) ?? []).first?.startedAt ?? schedule.createdAt
      if let due = schedule.every.due(last: last, now: now, in: context.environment.timeZone) {
        raise(.schedule(schedule.id, project: schedule.project), due: due)
      }
    }
    for home in context.homes() {
      let files = context.store.home(home)
      let state = files.panelState()
      for panel in files.panels().compactMap(\.panel) where !state.paused.contains(panel.name) {
        guard let refresh = panel.refresh,
          let due = PanelSchedule.due(
            refresh, last: state.refreshed[panel.name], now: now, timeZone: context.environment.timeZone)
        else { continue }
        raise(.panel(PanelRef(panel.name, in: home), asked: false), due: due)
      }
    }
    for followUp in (try? database.followUps()) ?? [] where followUp.due <= now && homes.contains(followUp.home) {
      raise(.followUp(followUp.id, project: followUp.home.project), due: followUp.due)
      _ = try? database.endFollowUp(followUp.id, at: now)
    }
    if let day = DailyReview.due(reviewSituation(now: now)) { raise(.review(day, project: nil), due: now) }
    for project in context.rememberedProjects() {
      if let day = DailyReview.due(reviewSituation(of: project.id, now: now)) {
        raise(.review(day, project: project.id), due: now)
      }
    }
    if raised { await context.follower.follow([.timers]) }
    return raised
  }

  /// A panel the person asked to refresh goes ahead of the rest and does not wait for quiet. Asked again
  /// while it waits or runs, nothing more is raised.
  func ask(toRefresh panel: PanelRef) async {
    let database = context.database
    let open = (try? database.openEvents()) ?? []
    let underWay = open.contains { event in
      guard event.source.sameTimer(as: .panel(panel, asked: true)) else { return false }
      if case .running = event.state { return true }
      return event.isAsked
    }
    guard !underWay else { return }
    for event in open where event.source == .panel(panel, asked: false) {
      if case .waiting = event.state { try? database.update(event.with(.dropped)) }
    }
    let event = Event(
      id: context.environment.newID(), source: .panel(panel, asked: true), due: context.environment.now())
    if (try? database.raise(event)) == true { await context.follower.follow([.timers]) }
  }

  private func reviewSituation(now: Timestamp) -> DailyReview.Situation {
    let database = context.database
    let store = context.store
    let timeZone = context.environment.timeZone
    return DailyReview.Situation(
      now: now, timeZone: timeZone, working: false,
      lastSaid: { (try? database.talk())?.latest },
      reviewed: { (try? database.review(of: $0)) != nil },
      active: { day in
        let start = day.start(in: timeZone)
        let end = day.adding(days: 1).start(in: timeZone)
        if ((try? database.typedMessages(from: start, to: end)) ?? 0) > 0 { return true }
        let notes = DayNotes(day: day, parsing: (try? store.home(.chat).dayNotes(of: day)) ?? "", title: { _ in nil })
        return !notes.notes.isEmpty
      })
  }

  /// A project's review is due as the chat's is, on a day something was said or noted in it; it is done once,
  /// as the inbox keeps one event for each day.
  private func reviewSituation(of project: Project.ID, now: Timestamp) -> DailyReview.Situation {
    let database = context.database
    let files = context.store.home(.project(project))
    return DailyReview.Situation(
      now: now, timeZone: context.environment.timeZone, working: false,
      lastSaid: { (try? database.talk())?.latest },
      reviewed: { day in
        let key = Event(id: project, source: .review(day, project: project), due: now).key
        return (try? database.hasEvent(withKey: key)) == true
      },
      active: { day in
        let notes = DayNotes(day: day, parsing: (try? files.dayNotes(of: day)) ?? "", title: { _ in nil })
        return !notes.notes.isEmpty || files.transcriptPaths().contains { $0.contains("/\(day)/") }
      })
  }
}

extension Event.Source {
  /// Whether the two come from the same timer, whenever they came due.
  func sameTimer(as other: Event.Source) -> Bool {
    if let panel { return panel == other.panel }
    return self == other
  }
}
