import Foundation
import LociModel
import LociStore

/// Once a minute, and when the app opens, finds the timers that came due and puts an event for each into the
/// inbox: schedules, panels' refreshes, follow-ups, and the daily review. It starts nothing itself. A timer
/// missed while the app was closed is raised once, however many times it was missed. Next-up cards put off
/// until now come back to the top of their deck, with no run.
struct Scheduler {
  let context: AgentContext

  /// Raises what came due; whether anything was.
  @discardableResult
  func look() async -> Bool {
    let database = context.database
    let now = context.environment.now()
    let open = (try? database.openEvents()) ?? []
    var raised = false
    func raise(_ source: Event.Source, due: Timestamp, deadline: Timestamp? = nil) {
      guard !open.contains(where: { $0.source.sameTimer(as: source) }) else { return }
      let event = Event(id: context.environment.newID(), source: source, due: due, deadline: deadline)
      if (try? database.raise(event)) == true { raised = true }
    }
    let homes = Set(context.homes())
    for schedule in (try? database.schedules()) ?? [] where !schedule.paused && homes.contains(schedule.home) {
      let last = ((try? database.runs(of: schedule.ref, limit: 1)) ?? []).first?.startedAt ?? schedule.createdAt
      if let due = schedule.every.due(
        last: last, now: now, in: context.environment.timeZone, trading: context.environment.trading)
      {
        raise(.schedule(schedule.id, project: schedule.project), due: due, deadline: schedule.deadline(for: due))
      }
    }
    for home in context.homes() {
      let files = context.store.home(home)
      let state = files.panelState()
      for panel in files.panels().compactMap(\.panel) where !state.paused.contains(panel.name) {
        guard let refresh = panel.refresh,
          let due = PanelSchedule.due(
            refresh, last: state.refreshed[panel.name], now: now, timeZone: context.environment.timeZone,
            trading: context.environment.trading)
        else { continue }
        raise(.panel(PanelRef(panel.name, in: home), asked: false), due: due)
      }
    }
    for followUp in (try? database.followUps()) ?? [] where followUp.due <= now && homes.contains(followUp.home) {
      if (try? database.raiseFollowUp(followUp, id: context.environment.newID(), at: now)) == true { raised = true }
    }
    var cameBack = false
    for card in (try? database.nextUpsDue(at: now)) ?? [] where homes.contains(card.home) {
      let back = try? database.changeNextUp(card.id) { stored in
        guard case .later(let until) = stored.place, until <= now, !stored.isExpired(at: now) else { return nil }
        return stored.with(place: .new, shownAt: until)
      }
      if let result = back.flatMap({ $0 }), result.after != nil { cameBack = true }
    }
    if cameBack { await context.follower.follow([.nextUps]) }
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
        if Self.hasFeedback(database, from: .chat, before: end) { return true }
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
    let timeZone = context.environment.timeZone
    return DailyReview.Situation(
      now: now, timeZone: context.environment.timeZone, working: false,
      lastSaid: { (try? database.talk())?.latest },
      reviewed: { day in
        let key = Event(id: project, source: .review(day, project: project), due: now).key
        return (try? database.hasEvent(withKey: key)) == true
      },
      active: { day in
        if Self.hasFeedback(database, from: .project(project), before: day.adding(days: 1).start(in: timeZone)) {
          return true
        }
        let notes = DayNotes(day: day, parsing: (try? files.dayNotes(of: day)) ?? "", title: { _ in nil })
        return !notes.notes.isEmpty || files.transcriptPaths().contains { $0.contains("/\(day)/") }
      })
  }
  private static func hasFeedback(_ database: StoreDatabase, from home: Home, before end: Timestamp) -> Bool {
    ((try? database.nextUps(of: [home])) ?? []).contains { card in
      card.feedback?.contains { $0.at < end } == true
    }
  }

}

extension Event.Source {
  /// Whether the two come from the same timer, whenever they came due.
  func sameTimer(as other: Event.Source) -> Bool {
    if let panel { return panel == other.panel }
    return self == other
  }
}
