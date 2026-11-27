import Foundation

/// The deck of a page, kept current: the chat's has the cards of the chat and of every project still open; a
/// project's only its own.
public struct WatchNextUps: Subscription {
  public static let name = "nextUps.watch"
  public let project: Project.ID?

  public init(of home: Home) {
    project = home.project
  }

  public var home: Home { Home(project) }

  public func value(from handler: any CommandHandler) async throws(HostError) -> [NextUp] {
    try await handler.nextUps(of: home)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .nextUps, .projects, .everything: true
      case .item, .course, .courseActivity, .notes, .reading, .job, .media, .conversation, .turnEnded, .review, .loci,
        .runtime, .agentModels, .timers, .connectors, .source:
        false
      }
    }
  }
}

/// Puts a card on the deck of the home the session works in. The same key brings an open card back to the top
/// with the new words; refused when the person declined it before.
public struct AddNextUp: LocalToolCommand {
  public static let name = "nextUps.add"
  public let what: String
  public let question: String
  public let key: String?
  public let deadline: Timestamp?
  /// The app fills it in from the session the command came from.
  public let project: Project.ID?

  public init(
    _ what: String, asking question: String, key: String? = nil, in home: Home = .chat, deadline: Timestamp? = nil
  ) {
    self.what = what
    self.question = question
    self.key = key
    self.deadline = deadline
    project = home.project
  }

  public var home: Home { Home(project) }

  public func run(on handler: any CommandHandler) async throws(HostError) -> NextUp {
    try await handler.addNextUp(self)
  }
}

/// Puts an approval card on the deck: nothing is done until the person approves it.
public struct ProposeApproval: LocalToolCommand {
  public static let name = "nextUps.propose"
  public let approval: Approval
  public let why: String?
  public let deadline: Timestamp?
  public let project: Project.ID?

  public init(_ approval: Approval, why: String? = nil, in home: Home = .chat, deadline: Timestamp? = nil) {
    self.approval = approval
    self.why = why
    self.deadline = deadline
    project = home.project
  }

  public var home: Home { Home(project) }

  public func run(on handler: any CommandHandler) async throws(HostError) -> NextUp {
    try await handler.proposeApproval(self)
  }
}

public struct StartNextUp: RemoteCommand {
  public static let name = "nextUps.start"
  public let card: EntityID
  public let version: Int

  public init(_ card: EntityID, version: Int) {
    self.card = card
    self.version = version
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.startNextUp(self)
  }
}

/// What the person does with a card other than starting it, to the card as it was at `version`. Refused when
/// it changed since. Gives the card as it is after, for undoing `later` or `decline` with `restore`.
public struct SetNextUp: RemoteCommand {
  public static let name = "nextUps.set"
  public let card: EntityID
  public let choice: Choice
  public let version: Int

  public enum Choice: Hashable, Codable, Sendable {
    case keep
    case later(FollowUpTime)
    case decline
    /// Back on the deck as new, to undo `keep`, `later` or `decline`.
    case restore
  }

  public init(_ card: EntityID, _ choice: Choice, version: Int) {
    self.card = card
    self.choice = choice
    self.version = version
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> NextUp {
    try await handler.setNextUp(self)
  }
}

/// Approves an approval card as it was at `version`, in two steps; only the person can. The first asks macOS
/// for access and finds where it goes, which the card then shows; the second, once the person confirmed one of
/// those, writes it there. Refused when the card changed, is done or under way, or its project is not open.
public struct ApproveNextUp: RemoteCommand {
  public static let name = "nextUps.approve"
  public let card: EntityID
  public let version: Int
  public let step: Step

  public enum Step: Hashable, Codable, Sendable {
    /// Finds the calendars or lists of the name the card gives, or the default one.
    case find
    /// Finds the default one, once none has the name the card gave.
    case findDefault
    /// Writes it into the one with this identifier, out of those found.
    case into(String)
  }

  public init(_ card: EntityID, version: Int, _ step: Step = .find) {
    self.card = card
    self.version = version
    self.step = step
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.approveNextUp(self)
  }
}

/// Removes `made`, what the card's approval wrote, and leaves the card waiting to be approved again; the card
/// stays where it is on the deck. Refused when the card changed since `version`, so it never removes what a
/// later approval wrote.
public struct UndoApproval: RemoteCommand {
  public static let name = "nextUps.undoApproval"
  public let card: EntityID
  public let version: Int
  public let made: String

  public init(_ card: EntityID, version: Int, made: String) {
    self.card = card
    self.version = version
    self.made = made
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.undoApproval(self)
  }
}
