import Foundation
import LociModel
import LociStore

/// The panels Loci keeps, and their refreshes in the background, one at a time, in a Loci session of their
/// own that the main conversation never shows.
///
/// Saving and removing a panel both go through here, one after the other, so a refresh whose panel was
/// removed cannot save it back: each refresh has an id its session's `loci` command carries, and removing
/// the panel stops accepting it.
actor PanelKeeper {
  private let context: AgentContext
  /// Whether Loci is answering anywhere or looking back on the day; a refresh that is merely due waits.
  private let busy: @Sendable () async -> Bool
  /// Panels the person asked to refresh, in the order they asked.
  private var asked: [String] = []
  private var refreshing: Refresh?
  /// The refresh whose saves are kept; `nil` once its panel was removed.
  private var accepting: EntityID?
  private var work: Task<Void, Never>?
  private var run: AgentRun?
  private var closing = false

  private struct Refresh {
    let panel: String
    let id: EntityID
  }

  static let stopped =
    "This refresh was stopped because the person removed the panel. Nothing was saved. Do not save it again "
    + "or under another name; reply in one line that the panel was removed."

  init(context: AgentContext, busy: @escaping @Sendable () async -> Bool) {
    self.context = context
    self.busy = busy
  }

  func entries() -> [PanelEntry] {
    context.store.panels()
  }

  var refreshingNames: Set<String> { refreshing.map { [$0.panel] } ?? [] }

  /// Writes the panel; a new one goes to the bottom of the column. From a refresh's session, only that
  /// refresh's panel, and only while it is still wanted. What Loci saves keeps what is the person's.
  func save(_ panel: Panel, by author: PanelItem.Author, from session: LocalSession?) async throws(HostError) {
    try allow(panel.name, from: session)
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
    try allow(name, from: session)
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

  /// A refresh's session may touch only its own panel, and only while the refresh is wanted.
  private func allow(_ name: String, from session: LocalSession?) throws(HostError) {
    guard case .panelRefresh(let id) = session else { return }
    guard let refreshing, refreshing.id == id, accepting == id else { throw .invalidRequest(Self.stopped) }
    guard refreshing.panel == name else {
      throw .invalidRequest("This refresh is of \(refreshing.panel); it can save only that panel.")
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
      }
    }
    asked.removeAll { $0 == name }
    if refreshing?.panel == name {
      accepting = nil
      if let run { Task { await run.stop() } }
    }
    await context.follower.follow([.loci(.panels)])
  }

  /// Puts the panel at the end of the line and starts it when no other is being refreshed.
  func refreshSoon(_ name: String) async throws(HostError) {
    guard entries().contains(where: { $0.name == name && $0.panel != nil }) else { throw .notFound(name) }
    if refreshing?.panel != name, !asked.contains(name) { asked.append(name) }
    await startNext(onlyAsked: true)
  }

  /// Once a minute: starts the next refresh, a panel the person asked for first, then one that is due
  /// while Loci is not busy.
  func consider() async {
    await startNext(onlyAsked: false)
  }

  /// Stops a refresh under way; the panel keeps what it had.
  func close() async {
    closing = true
    accepting = nil
    await run?.close()
    await work?.value
  }

  private func startNext(onlyAsked: Bool) async {
    guard refreshing == nil, !closing else { return }
    let panels = entries().compactMap(\.panel)
    let next: Panel?
    if let name = asked.first {
      asked.removeFirst()
      next = panels.first { $0.name == name }
    } else if onlyAsked {
      next = nil
    } else {
      next = await due(among: panels)
    }
    guard let next, refreshing == nil, !closing else { return }
    let refresh = Refresh(panel: next.name, id: context.environment.newID())
    refreshing = refresh
    accepting = refresh.id
    work = Task { await self.run(refresh, of: next) }
    await context.follower.follow([.loci(.panels)])
  }

  private func due(among panels: [Panel]) async -> Panel? {
    let state = context.store.panelState()
    let now = context.environment.now()
    let order = PanelOrder.places(state.order, panels: panels.map(\.name))
    let due = panels.filter { panel in
      guard let refresh = panel.refresh else { return false }
      return PanelSchedule.isDue(
        refresh, last: state.refreshed[panel.name], now: now, timeZone: context.environment.timeZone)
    }
    guard !due.isEmpty, !(await busy()) else { return nil }
    return order.lazy.compactMap { place in due.first { .panel($0.name) == place } }.first
  }

  private func run(_ refresh: Refresh, of panel: Panel) async {
    let now = context.environment.now()
    if accepting == refresh.id { _ = try? context.store.changePanelState { $0.refreshed[panel.name] = now } }
    do throws(HostError) {
      let run = try AgentRun(owner: .panel(panel.name), session: .panelRefresh(refresh.id), context: context)
      self.run = run
      try await run.startOver()
      let text = try context.prompts.panel(panel, hidden: context.store.panelState().marks[panel.name] ?? [:])
      if accepting == refresh.id {
        try await run.send(Prompt(text: text, purpose: .panel(panel.name)), saying: text)
        _ = await run.settle()
      }
      await run.close()
    } catch {
      await run?.close()
    }
    run = nil
    refreshing = nil
    accepting = nil
    work = nil
    await context.follower.follow([.loci(.panels)])
    await startNext(onlyAsked: true)
  }
}
