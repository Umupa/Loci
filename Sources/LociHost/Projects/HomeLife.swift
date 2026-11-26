import LociModel

/// How many times each project was archived, deleted, brought back or kept out of memory. Work that began in
/// a project holds a `HomeTicket`; once the project moves on, the ticket no longer holds, so a fetch or run that
/// returns late writes nothing into a project closed or opened again meanwhile.
actor HomeLife {
  private var ages: [Project.ID: Int] = [:]
  /// Projects being deleted: nothing starts in them and nothing that began in them writes, until they are set
  /// aside or the deletion fails.
  private var leaving: Set<Project.ID> = []
  /// Every change to a project's `project.json` goes through here one at a time.
  let edits = Gate(limit: 1)
  /// A project closes, opens again or has its folders moved only between the final writes of work in it, which
  /// check their ticket and write as one; so nothing is written into a project after it closed, nor into a
  /// folder after it moved. Taken before `edits` when both are.
  let moves = Gate(limit: 1)

  /// `nil` while the project is being deleted.
  func age(of home: Home) -> Int? {
    guard case .project(let id) = home else { return 0 }
    return leaving.contains(id) ? nil : ages[id] ?? 0
  }

  /// The project moved on: whatever began in it before may no longer write.
  func moved(_ project: Project.ID) {
    ages[project, default: 0] += 1
  }

  /// The project is being deleted: it moves on, and stays closed to new work until `stayed`.
  func leave(_ project: Project.ID) {
    moved(project)
    leaving.insert(project)
  }

  func stayed(_ project: Project.ID) {
    leaving.remove(project)
  }

  var projectsLeaving: Set<Project.ID> { leaving }
}

/// Work's hold on the home it began in.
struct HomeTicket: Hashable, Sendable {
  let home: Home
  let age: Int
}

extension AgentContext {
  /// Changes `project.json` one change at a time, each reading the project as it is on disk then.
  func changeProject(_ id: Project.ID, _ change: @escaping @Sendable (Project) -> Project) async throws(HostError)
    -> Project
  {
    let store = store
    return try await life.edits.through { () async throws(HostError) in
      try attempt { try store.changeProject(id, change) }
    }
  }

  func ticket(for home: Home) async -> HomeTicket {
    HomeTicket(home: home, age: await life.age(of: home) ?? -1)
  }

  /// Runs `body` with no project closing, opening again or moving meanwhile: see `HomeLife.moves`.
  func steadily<Value: Sendable, Failure: Error>(_ body: @Sendable () async throws(Failure) -> Value)
    async throws(Failure) -> Value
  {
    try await life.moves.through(body)
  }

  /// Whether work holding the ticket may still write: its home is open and has not moved on since.
  func holds(_ ticket: HomeTicket) async -> Bool {
    let age = await life.age(of: ticket.home)
    return isActive(ticket.home) && age == ticket.age
  }
}
