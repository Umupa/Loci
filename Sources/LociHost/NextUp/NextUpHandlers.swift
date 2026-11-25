import Foundation
import LociModel
import LociStore

/// The next-up cards: what the companion and the reminder conditions put on a home's deck, and what the
/// person does with them.
extension LocalHost {
  /// The chat's deck has every open home's cards; a project's only its own.
  public func nextUps(of home: Home) async throws(HostError) -> [NextUp] {
    let homes = home == .chat ? loci.context.homes() : [home]
    let cards = try attempt { try database.nextUps(of: homes) }
    return NextUp.deck(cards, at: environment.now())
  }

  public func addNextUp(_ command: AddNextUp) async throws(HostError) -> NextUp {
    let what = command.what.trimmingCharacters(in: .whitespacesAndNewlines)
    let question = command.question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !what.isEmpty, !question.isEmpty else { throw .invalidRequest("a card needs what happened and a question") }
    let key = command.key ?? NextUp.key(of: what)
    return try await loci.context.put(.ask(question: question), what: what, key: key, in: command.home)
  }

  public func proposeApproval(_ command: ProposeApproval) async throws(HostError) -> NextUp {
    let approval = command.approval
    guard !approval.title.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw .invalidRequest("an approval needs a title")
    }
    if case .event(let event) = approval, event.end < event.start {
      throw .invalidRequest("the event ends before it starts")
    }
    return try await loci.context.put(
      .approval(approval), what: command.why ?? approval.title, key: approval.key, in: command.home)
  }

  public func startNextUp(_ command: StartNextUp) async throws(HostError) -> Done {
    let card = try card(command.card)
    guard case .ask(let question) = card.kind else { throw .invalidRequest("an approval is approved, not started") }
    try attempt { try database.saveNextUp(card.with(state: .started)) }
    await follow([.nextUps])
    return try await sendMessage(SendMessage(to: card.home.conversation, text: question))
  }

  public func setNextUp(_ command: SetNextUp) async throws(HostError) -> Done {
    let card = try card(command.card)
    let now = environment.now()
    let state: NextUp.State =
      switch command.choice {
      case .keep: .kept
      case .later(let time): .later(until: time.moment(now: now, in: environment.timeZone))
      case .decline: .declined
      case .restore: .new
      }
    if case .approved = card.state, command.choice == .restore { return Done() }
    try attempt { try database.saveNextUp(card.with(state: state)) }
    await follow([.nextUps])
    return Done()
  }

  /// Makes what the card asks for, once macOS lets it; refused, the card stays as it was.
  public func approveNextUp(_ command: ApproveNextUp) async throws(HostError) -> Done {
    let card = try card(command.card)
    guard case .approval(let approval) = card.kind else { throw .invalidRequest("only an approval is approved") }
    if case .approved = card.state { return Done() }
    let writes = environment.connect.writes
    guard await writes.allow(approval.personalKind) else {
      throw .invalidRequest(
        approval.personalKind == .events
          ? "Loci may not add to your calendar; allow it in System Settings › Privacy & Security › Calendars"
          : "Loci may not add to your reminders; allow it in System Settings › Privacy & Security › Reminders")
    }
    let identifier: String
    do {
      identifier = try await writes.make(approval)
    } catch {
      throw .invalidRequest(error.reason)
    }
    try attempt { try database.saveNextUp(card.with(state: .approved(Approved(identifier: identifier)))) }
    await follow([.nextUps])
    return Done()
  }

  public func undoApproval(_ command: UndoApproval) async throws(HostError) -> Done {
    let card = try card(command.card)
    guard case .approval(let approval) = card.kind, case .approved(let made) = card.state else { return Done() }
    do {
      try await environment.connect.writes.remove(made.identifier, of: approval.personalKind)
    } catch {
      throw .invalidRequest(error.reason)
    }
    try attempt { try database.saveNextUp(card.with(state: .new)) }
    await follow([.nextUps])
    return Done()
  }

  private func card(_ id: EntityID) throws(HostError) -> NextUp {
    guard let card = try attempt({ try database.nextUp(id) }) else { throw .notFound("card \(id)") }
    return card
  }
}

extension AgentContext {
  /// Puts a card on the home's deck. An open card with the key comes back to the top with the new words; one
  /// the person declined stays declined, and the call is refused.
  func put(_ kind: NextUp.Kind, what: String, key: String, in home: Home) async throws(HostError) -> NextUp {
    let now = environment.now()
    let card: NextUp
    if let existing = try attempt({ try database.nextUp(withKey: key, in: home) }) {
      if existing.state == .declined { throw .invalidRequest(NextUp.declinedBefore) }
      card = existing.with(kind: kind, what: what, state: .new, shownAt: now)
    } else {
      card = NextUp(id: environment.newID(), home: home, key: key, kind: kind, what: what, shownAt: now)
    }
    try attempt { try database.saveNextUp(card) }
    await follower.follow([.nextUps])
    return card
  }
}

extension NextUp {
  static let declinedBefore = "The person declined this card before; it does not come back."
}
