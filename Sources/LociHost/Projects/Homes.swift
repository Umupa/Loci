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

  /// Whether the home's folders are where they belong: the chat's always, a project's until it is deleted.
  func isThere(_ home: Home) -> Bool {
    guard case .project(let id) = home else { return true }
    return (try? store.project(id)) != nil
  }

  /// The projects kept out of the chat's memory, as part of what its session is opened with: when one is kept
  /// out, the chat's next turn opens a new session that was never told of it.
  func knownProjects(from home: Home) -> String {
    guard home == .chat else { return "" }
    return store.projects().filter { !$0.remembered }.map(\.id.description).sorted().joined(separator: ",")
  }

  /// The projects the chat and the daily review may know of: named, remembered and not archived.
  func rememberedProjects() -> [Project] {
    store.projects().filter { $0.name != nil && $0.remembered && !$0.archived }
  }

}
