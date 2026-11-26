import Foundation
import LociAgents
import LociModel
import LociStore
import os

/// What a run answers the agent on its own and how it copies the conversation to files.
extension AgentRun {
  /// Every session runs with full access, so a request the agent still makes is allowed.
  static func allowing(_ request: PermissionRequest) -> PermissionAnswer {
    let roles: [PermissionRequest.Option.Role] = [.allow, .allowAlways]
    let option = roles.lazy.compactMap { role in request.options.first { $0.role == role } }.first
    return option.map { .chosen($0.id) } ?? .dismissed
  }

  /// A copy that cannot be written loses nothing the app needs; it is logged and the turn stands. None is
  /// written for a project deleted meanwhile, so its folder is not made again.
  static func mirror(_ messages: [Message], of session: SessionRecord, in home: Home, context: AgentContext) {
    guard context.isThere(home) else { return }
    do {
      for path in try context.store.home(home).mirror(messages, of: session, in: context.environment.timeZone) {
        try context.database.indexTranscript(path, from: context.store)
      }
    } catch {
      Logger(subsystem: "Loci", category: "agent").error(
        "could not copy the conversation: \(String(describing: error), privacy: .public)")
    }
  }
}

extension SessionRecord {
  func with(sent: [String: String]) -> SessionRecord {
    SessionRecord(
      id: id, owner: owner, runtime: runtime, handle: handle, instructions: instructions, sent: sent,
      startedAt: startedAt)
  }
}
