import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func timers() async throws(HostError) -> Timers {
    let schedules = try attempt { try database.schedules() }.map(entry)
    let refreshes = loci.context.homes().flatMap { home in
      let files = store.home(home)
      let state = files.panelState()
      return files.panels().compactMap(\.panel).compactMap { panel in
        entry(of: PanelRef(panel.name, in: home), panel, state: state)
      }
    }
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
    case .panel(let name, let project):
      let ref = PanelRef(name, in: Home(project))
      _ = try existingRefresh(of: ref)
      try attempt {
        _ = try store.home(ref.home).changePanelState { state in
          if command.paused { state.paused.insert(name) } else { state.paused.remove(name) }
        }
      }
    }
    await follow([.timers, .loci(.panels)])
    return Done()
  }

  public func changeSchedule(_ command: ChangeSchedule) async throws(HostError) -> ScheduleEntry {
    let change = command.change
    guard !change.isEmpty else { throw .invalidRequest("Say what to change: title, follow, every or panel.") }
    for text in [change.title, change.follow].compactMap(\.self)
    where text.trimmingCharacters(in: .whitespaces).isEmpty {
      throw .invalidRequest("A schedule's title and follow cannot be blank.")
    }
    switch command.schedule {
    case .schedule(let id):
      let schedule = try existing(id)
      if case .panel(let panel) = change.destination, store.home(schedule.home).panel(named: panel)?.panel == nil {
        throw .invalidRequest("There is no panel \(panel). Save it first with `loci panel save \(panel)`.")
      }
      let changed = Schedule(
        id: id, name: schedule.name, title: change.title ?? schedule.title, follow: change.follow ?? schedule.follow,
        every: change.every ?? schedule.every, destination: change.destination ?? schedule.destination,
        paused: schedule.paused, createdAt: schedule.createdAt, in: schedule.home)
      try attempt { try database.saveSchedule(changed) }
      await follow([.timers])
      return entry(changed)
    case .panel(let name, let project):
      let ref = PanelRef(name, in: Home(project))
      let panel = try existingRefresh(of: ref)
      if let destination = change.destination, destination != .panel(name) {
        throw .invalidRequest("A panel's refresh always goes to that panel; make a schedule to send it elsewhere.")
      }
      let changed = Panel(
        name: name, title: change.title ?? panel.title, sources: panel.sources, follow: change.follow ?? panel.follow,
        refresh: change.every?.refresh ?? panel.refresh, body: panel.body)
      try attempt { try store.home(ref.home).savePanel(changed) }
      await follow([.timers, .loci(.panels)])
      guard let entry = entry(of: ref, changed, state: store.home(ref.home).panelState()) else { throw .notFound(name) }
      return entry
    }
  }

  public func removeSchedule(_ command: RemoveSchedule) async throws(HostError) -> Done {
    switch command.schedule {
    case .schedule(let id):
      _ = try existing(id)
      try attempt { try database.removeSchedule(id) }
    case .panel(let name, let project):
      let ref = PanelRef(name, in: Home(project))
      let panel = try existingRefresh(of: ref)
      try attempt {
        try store.home(ref.home).savePanel(panel.with(refresh: nil))
        _ = try store.home(ref.home).changePanelState { $0.paused.remove(name) }
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
    if case .panel(let panel) = draft.destination, store.home(command.home).panel(named: panel)?.panel == nil {
      throw .invalidRequest("There is no panel \(panel). Save it first with `loci panel save \(panel)`.")
    }
    guard try attempt({ try database.schedules() }).allSatisfy({ $0.name != name }) else {
      throw .invalidRequest("There is a schedule \(name) already. Remove it first, or choose another name.")
    }
    let schedule = Schedule(
      id: environment.newID(), name: name, title: draft.title, follow: draft.follow, every: draft.every,
      destination: draft.destination, createdAt: environment.now(), in: command.home)
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

  private func existingRefresh(of ref: PanelRef) throws(HostError) -> Panel {
    guard let panel = store.home(ref.home).panel(named: ref.name)?.panel, panel.refresh != nil else {
      throw .notFound(ref.name)
    }
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
      lastSummary: runs.lazy.compactMap(\.summary).first, lastRun: runs.first { $0.summary != nil }?.startedAt)
  }

  private func entry(of ref: PanelRef, _ panel: Panel, state: PanelState) -> ScheduleEntry? {
    guard let every = panel.refresh.flatMap(Every.init) else { return nil }
    let paused = state.paused.contains(panel.name)
    let runs = (try? database.runs(of: .panel(ref), limit: 10)) ?? []
    let next =
      paused ? nil : every.next(last: state.refreshed[panel.name], now: environment.now(), in: environment.timeZone)
    return ScheduleEntry(
      ref: .panel(ref), name: panel.name, title: panel.title, every: every, destination: .panel(panel.name),
      paused: paused, next: next, lastSummary: runs.lazy.compactMap(\.summary).first,
      lastRun: runs.first { $0.summary != nil }?.startedAt)
  }
}

extension Schedule {
  func with(paused: Bool) -> Schedule {
    Schedule(
      id: id, name: name, title: title, follow: follow, every: every, destination: destination, paused: paused,
      createdAt: createdAt, in: home)
  }
}

extension Panel {
  func with(refresh: PanelRefresh?) -> Panel {
    Panel(name: name, title: title, sources: sources, follow: follow, refresh: refresh, body: body)
  }
}
