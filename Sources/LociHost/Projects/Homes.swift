import LociModel
import LociStore

extension AgentContext {
  /// The chat, and every project there is that is not archived: the homes whose timers come due.
  func homes() -> [Home] {
    [.chat] + store.projects().filter { !$0.archived }.map { .project($0.id) }
  }

  /// Whether the home's timers may come due and its runs may start: the chat's always, a project's while it is
  /// there and not archived.
  func isActive(_ home: Home) -> Bool {
    guard case .project(let id) = home else { return true }
    guard let project = try? store.project(id) else { return false }
    return !project.archived
  }

  /// The projects the chat and the daily review may know of: named, remembered and not archived.
  func rememberedProjects() -> [Project] {
    store.projects().filter { $0.name != nil && $0.remembered && !$0.archived }
  }

  /// The homes `loci recall` leaves out when asked from `home`: every project kept out of memory but this one,
  /// and a project deleted a moment ago.
  func hiddenFromRecall(in home: Home) -> Set<Home> {
    let unremembered = store.projects().filter { !$0.remembered && .project($0.id) != home }.map(\.id)
    return Set((unremembered + store.setAsideProjects()).map(Home.project))
  }
}
