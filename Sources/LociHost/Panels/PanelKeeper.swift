import Foundation
import LociModel
import LociStore

/// The panels Loci keeps. Saving and removing a panel both go through here, one after the other, so a run
/// whose panel was removed cannot save it back. Refreshing them is the worker's: a refresh is a run.
actor PanelKeeper {
  private let context: AgentContext
  private let worker: Worker
  private let scheduler: Scheduler

  static let stopped =
    "This refresh was stopped because the person removed the panel. Nothing was saved. Do not save it again "
    + "or under another name; reply in one line that the panel was removed."

  init(context: AgentContext, worker: Worker, scheduler: Scheduler) {
    self.context = context
    self.worker = worker
    self.scheduler = scheduler
  }

  func entries() -> [PanelEntry] {
    context.store.panels()
  }

  var refreshingNames: Set<String> {
    get async { await worker.refreshingPanels }
  }

  /// Writes the panel; a new one goes to the bottom of the column. From a refresh's session, only that
  /// refresh's panel, and only while it is still wanted. What Loci saves keeps what is the person's.
  func save(_ panel: Panel, by author: PanelItem.Author, from session: LocalSession?) async throws(HostError) {
    try await allow(panel.name, from: session)
    let store = context.store
    let saved: Panel
    switch author {
    case .you: saved = panel
    case .loci:
      let removed = store.panelState().removed(from: panel.name, now: context.environment.now())
      saved = try checked { () throws(PanelProblems) in
        try PanelMerge.loci(panel, onto: store.panel(named: panel.name)?.panel, removed: removed)
      }
    }
    let problems = PanelCheck.problems(in: saved)
    guard problems.isEmpty else { throw .invalidRequest(problems.map(\.description).joined(separator: "\n")) }
    let now = context.environment.now()
    try attempt {
      try store.savePanel(saved)
      _ = try store.changePanelState { state in
        if !state.order.contains(.panel(saved.name)) {
          let others = store.panels().map(\.name).filter { $0 != saved.name }
          state.order = PanelOrder.places(state.order, panels: others) + [.panel(saved.name)]
        }
        state.refreshed[saved.name] = now
      }
    }
    await context.follower.follow([.loci(.panels)])
  }

  /// Makes one edit on the panel as its file is now. Loci's edits keep what is the person's.
  func edit(_ edit: PanelEdit, of name: String, by author: PanelItem.Author, from session: LocalSession?)
    async throws(HostError)
  {
    try await allow(name, from: session)
    let store = context.store
    guard let current = store.panel(named: name)?.panel else { throw .notFound(name) }
    let edited = try checked { () throws(PanelProblems) in
      let made = author == .loci ? try PanelMerge.loci(edit, on: current) : edit
      let edited = try current.applying(made)
      let problems = PanelCheck.problems(in: edited)
      guard problems.isEmpty else { throw PanelProblems(all: problems) }
      return edited
    }
    let now = context.environment.now()
    try attempt {
      try store.savePanel(edited)
      if author == .you, case .remove(let id) = edit {
        _ = try store.changePanelState { $0.remember(removed: id, from: name, at: now) }
      }
    }
    await context.follower.follow([.loci(.panels)])
  }

  /// Keeps the person's take on a line of a panel's list.
  func mark(_ command: MarkPanelLine) async throws(HostError) {
    let store = context.store
    guard store.panel(named: command.panel) != nil else { throw .notFound(command.panel) }
    try attempt {
      _ = try store.changePanelState { state in
        var marks = state.marks[command.panel] ?? [:]
        marks[command.line] = command.mark.isEmpty ? nil : command.mark
        state.marks[command.panel] = marks.isEmpty ? nil : marks
      }
    }
    await context.follower.follow([.loci(.panels)])
  }

  /// A run's session may touch only the panels it is for, and only while it runs.
  private func allow(_ name: String, from session: LocalSession?) async throws(HostError) {
    guard case .run(let run) = session else { return }
    switch await worker.permission(toSave: name, from: run) {
    case .allowed: return
    case .stopped: throw .invalidRequest(Self.stopped)
    case .only(let panels) where panels.count == 1:
      throw .invalidRequest("This refresh is of \(panels[0]); it can save only that panel.")
    case .only(let panels):
      throw .invalidRequest("This run can save only these panels: \(panels.joined(separator: ", ")).")
    case .none: throw .invalidRequest("This run cannot save panels.")
    }
  }

  private func checked<Value>(_ body: () throws(PanelProblems) -> Value) throws(HostError) -> Value {
    do {
      return try body()
    } catch {
      throw .invalidRequest(error.all.map(\.description).joined(separator: "\n"))
    }
  }

  /// Deletes the panel's file and stops its refresh, if one is under way.
  func remove(_ name: String) async throws(HostError) {
    let store = context.store
    try attempt {
      try store.removePanel(named: name)
      _ = try store.changePanelState { state in
        state.order.removeAll { $0 == .panel(name) }
        state.refreshed[name] = nil
        state.marks[name] = nil
        state.removals[name] = nil
        state.paused.remove(name)
      }
    }
    await worker.panelRemoved(name)
    await context.follower.follow([.loci(.panels), .timers])
  }

  /// Puts the panel ahead of everything else in the background, whether it is due or not.
  func refreshSoon(_ name: String) async throws(HostError) {
    guard entries().contains(where: { $0.name == name && $0.panel != nil }) else { throw .notFound(name) }
    await scheduler.ask(toRefresh: name)
    await worker.consider()
  }
}
