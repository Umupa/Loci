import LociModel

public enum AgentEvent: Hashable, Sendable {
  /// More of the reply.
  case text(String)
  /// More of the reasoning behind the reply.
  case thinking(String)
  /// A tool call seen for the first time.
  case toolCall(ToolCall)
  case toolCallChanged(ToolCall.ID, ToolCall.Change)
  case permission(PermissionRequest)
  /// The request no longer needs an answer: the turn was interrupted or the agent withdrew it.
  case permissionClosed(PermissionRequest.ID)
  case notice(Notice)
  case context(ContextUsage)
  case ended(TurnEnd)
}

public enum TurnEnd: Hashable, Sendable {
  case completed
  case interrupted
  case failed(AgentError)
}

/// Something the agent is doing that is not part of the reply.
public enum Notice: Hashable, Sendable {
  case retrying(attempt: Int, of: Int)
  case compacting
  /// The provider's or an extension's own words.
  case message(String)
}
