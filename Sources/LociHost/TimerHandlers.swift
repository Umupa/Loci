import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func timers() async throws(HostError) -> Timers {
    let schedules = try attempt { try database.schedules() }.map(entry)
    let state = store.panelState()
    let refreshes = store.panels().compactMap(\.panel).compactMap { panel in entry(of: panel, state: state) }
    let followUps = try attempt { try database.followUps() }
    let entries = schedules + refreshes
    let next = (entries.compactMap(\.next) + followUps.map(\.due)).min()
    return Timers(schedules: entries, followUps: followUps, next: next)
  }

  public func runs(of schedule: ScheduleRef, limit: Int) async throws(HostError) -> [Run] {
    try attempt { try database.runs(of: schedule, limit: max(1, limit)) }
  }

  public func pauseSchedule(_ command: PauseSchedule) async throws(HostError) -> Done {
    switch command.schedule {
    case .schedule(let id):
      let schedule = try existing(id)
      try attempt { try database.saveSchedule(schedule.with(paused: command.paused)) }
    case .panel(let name):
      _ = try existingRefresh(of: name)
      try attempt {
        _ = try store.changePanelState { state in
          if command.paused { state.paused.insert(name) } else { state.paused.remove(name) }
        }
      }
    }
    await follow([.timers, .loci(.panels)])
    return Done()
  }

  public func changeScheduleEvery(_ command: ChangeScheduleEvery) async throws(HostError) -> ScheduleEntry {
    switch command.schedule {
    case .schedule(let id):
      let changed = try existing(id).with(every: command.every)
      try attempt { try database.saveSchedule(changed) }
      await follow([.timers])
      return entry(changed)
    case .panel(let name):
      let panel = try existingRefresh(of: name)
      let changed = panel.with(refresh: command.every.refresh)
      try attempt { try store.savePanel(changed) }
      await follow([.timers, .loci(.panels)])
      guard let entry = entry(of: changed, state: store.panelState()) else { throw .notFound(name) }
      return entry
    }
  }

  public func removeSchedule(_ command: RemoveSchedule) async throws(HostError) -> Done {
    switch command.schedule {
    case .schedule(let id):
      _ = try existing(id)
      try attempt { try database.removeSchedule(id) }
    case .panel(let name):
      let panel = try existingRefresh(of: name)
      try attempt {
        try store.savePanel(panel.with(refresh: nil))
        _ = try store.changePanelState { $0.paused.remove(name) }
      }
    }
    await follow([.timers, .loci(.panels)])
    return Done()
  }

  public func addSchedule(_ command: AddSchedule) async throws(HostError) -> ScheduleEntry {
    let name = command.scheduleName
    if let problem = PanelCheck.problems(ofName: name).first { throw .invalidRequest(problem.reason) }
    let draft = command.draft
    guard !draft.title.trimmingCharacters(in: .whitespaces).isEmpty,
      !draft.follow.trimmingCharacters(in: .whitespaces).isEmpty
    else { throw .invalidRequest("A schedule needs a \"title\" and a \"follow\" saying what to look at.") }
    if case .panel(let panel) = draft.destination, store.panel(named: panel)?.panel == nil {
      throw .invalidRequest("There is no panel \(panel). Save it first with `loci panel save \(panel)`.")
    }
    guard try attempt({ try database.schedules() }).allSatisfy({ $0.name != name }) else {
      throw .invalidRequest("There is a schedule \(name) already. Remove it first, or choose another name.")
    }
    let schedule = Schedule(
      id: environment.newID(), name: name, title: draft.title, follow: draft.follow, every: draft.every,
      destination: draft.destination, createdAt: environment.now())
    try attempt { try database.saveSchedule(schedule) }
    await follow([.timers])
    return entry(schedule)
  }

  public func addFollowUp(_ command: AddFollowUp) async throws(HostError) -> FollowUp {
    let now = environment.now()
    let due = command.time.moment(now: now, in: environment.timeZone)
    let what = command.what.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !what.isEmpty else { throw .invalidRequest("Say what to follow up on.") }
    guard due > now else { throw .invalidRequest("That time has passed; give one still to come.") }
    let followUp = FollowUp(
      id: environment.newID(), due: due, what: what, conversation: command.conversation, createdAt: now)
    try attempt { try database.addFollowUp(followUp) }
    await follow([.timers])
    return followUp
  }

  public func cancelFollowUp(_ command: CancelFollowUp) async throws(HostError) -> Done {
    guard try attempt({ try database.endFollowUp(command.followUp, at: environment.now()) }) else {
      throw .notFound(command.followUp.description)
    }
    await follow([.timers])
    return Done()
  }

  private func existing(_ id: EntityID) throws(HostError) -> Schedule {
    guard let schedule = try attempt({ try database.schedule(id) }) else { throw .notFound(id.description) }
    return schedule
  }

  private func existingRefresh(of name: String) throws(HostError) -> Panel {
    guard let panel = store.panel(named: name)?.panel, panel.refresh != nil else { throw .notFound(name) }
    return panel
  }

  private func entry(_ schedule: Schedule) -> ScheduleEntry {
    let runs = (try? database.runs(of: schedule.ref, limit: 10)) ?? []
    let next =
      schedule.paused
      ? nil
      : schedule.every.next(
        last: runs.first?.startedAt ?? schedule.createdAt, now: environment.now(), in: environment.timeZone)
    return ScheduleEntry(
      ref: schedule.ref, name: schedule.name, title: schedule.title, every: schedule.every,
      destination: schedule.destination, paused: schedule.paused, next: next,
      lastSummary: runs.lazy.compactMap(\.summary).first)
  }

  private func entry(of panel: Panel, state: PanelState) -> ScheduleEntry? {
    guard let every = panel.refresh.flatMap(Every.init) else { return nil }
    let paused = state.paused.contains(panel.name)
    let runs = (try? database.runs(of: .panel(panel.name), limit: 10)) ?? []
    let next =
      paused ? nil : every.next(last: state.refreshed[panel.name], now: environment.now(), in: environment.timeZone)
    return ScheduleEntry(
      ref: .panel(panel.name), name: panel.name, title: panel.title, every: every, destination: .panel(panel.name),
      paused: paused, next: next, lastSummary: runs.lazy.compactMap(\.summary).first)
  }
}

extension Schedule {
  func with(paused: Bool) -> Schedule {
    Schedule(
      id: id, name: name, title: title, follow: follow, every: every, destination: destination, paused: paused,
      createdAt: createdAt)
  }

  func with(every: Every) -> Schedule {
    Schedule(
      id: id, name: name, title: title, follow: follow, every: every, destination: destination, paused: paused,
      createdAt: createdAt)
  }
}

extension Panel {
  func with(refresh: PanelRefresh?) -> Panel {
    Panel(name: name, title: title, sources: sources, follow: follow, refresh: refresh, body: body)
  }
}
