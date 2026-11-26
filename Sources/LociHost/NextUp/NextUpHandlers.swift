import Foundation
import LociConnect
import LociModel
import LociStore

/// The next-up cards: what the companion and the reminder conditions put on a home's deck, and what the
/// person does with them. Each action claims the card in one write of the database, so a card started or
/// approved from two Macs at once is acted on once.
extension LocalHost {
  /// The chat's deck has every open home's cards; a project's only its own, while it is open.
  public func nextUps(of home: Home) async throws(HostError) -> [NextUp] {
    let homes = home == .chat ? loci.context.homes() : loci.context.isActive(home) ? [home] : []
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

  /// The card keeps only the name the companion gave, if any: which calendar or list that is, the app finds once
  /// the person approves, and shows them before anything is written.
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

  /// Claims the card as it was shown with the message its question will be, says it, and only then lets it go.
  /// While the conversation is answering, the question waits for the answer to end, and is not said if the
  /// project was closed meanwhile; if it cannot be said, the card goes back where it was.
  public func startNextUp(_ command: StartNextUp) async throws(HostError) -> Done {
    let now = environment.now()
    let message = environment.newID()
    let claimed = try claim(command.card) { card in
      guard card.version == command.version, case .ask = card.kind, card.isShown(at: now) else { return nil }
      return card.with(place: .starting(from: card.place, message: message))
    }
    guard case .ask(let question) = claimed.kind, case .starting(let from, _) = claimed.place else { return Done() }
    let ticket = await loci.context.ticket(for: claimed.home)
    await follow([.nextUps])
    do throws(HostError) {
      let run = try await loci.run(of: claimed.home.conversation)
      if await !run.isIdle { _ = await run.settle() }
      let context = loci.context
      try await context.steadily { () async throws(HostError) in
        guard await context.holds(ticket) else { throw .invalidRequest(NextUp.closed) }
        try await run.send(Prompt(text: question, purpose: .chat), saying: question, as: message)
      }
    } catch {
      _ = try? attempt {
        try database.changeNextUp(claimed.id) { $0.place == claimed.place ? $0.with(place: from) : nil }
      }
      await follow([.nextUps])
      throw error
    }
    _ = try? attempt {
      try database.changeNextUp(claimed.id) { $0.place == claimed.place ? $0.with(place: .started) : nil }
    }
    await follow([.nextUps])
    return Done()
  }

  public func setNextUp(_ command: SetNextUp) async throws(HostError) -> NextUp {
    let now = environment.now()
    let place: NextUp.Place =
      switch command.choice {
      case .keep: .kept
      case .later(let time): .later(until: time.moment(now: now, in: environment.timeZone))
      case .decline: .declined
      case .restore: .new
      }
    let after = try claim(command.card) { card in
      guard card.version == command.version else { return nil }
      switch (card.place, command.choice) {
      case (.starting, _), (.started, _): return nil
      case (.declined, .restore), (.later, .restore): return card.with(place: place, shownAt: now)
      case (.kept, .restore): return card.with(place: place)
      case (_, .restore): return nil
      default: return card.with(place: place)
      }
    }
    await follow([.nextUps])
    return after
  }

  /// The first step asks macOS for access and finds where the approval goes, which the card shows for the person
  /// to confirm; the second writes it there.
  public func approveNextUp(_ command: ApproveNextUp) async throws(HostError) -> Done {
    switch command.step {
    case .find: try await findTargets(for: command, named: true)
    case .findDefault: try await findTargets(for: command, named: false)
    case .into(let target): try await write(command, into: target)
    }
    return Done()
  }

  /// Only once macOS allows looking: the calendars or lists of the card's name, or the default one. The card
  /// shows them, unless it changed or its project closed while macOS asked.
  private func findTargets(for command: ApproveNextUp, named: Bool) async throws(HostError) {
    let now = environment.now()
    guard let card = try attempt({ try database.nextUp(command.card) }) else { throw .notFound("card \(command.card)") }
    guard loci.context.isActive(card.home) else { throw .invalidRequest(NextUp.closed) }
    guard case .approval(let approval) = card.kind, card.version == command.version, card.isShown(at: now),
      card.execution == .waiting || (!named && card.isTargetGone)
    else { throw .invalidRequest(NextUp.changed) }
    let writes = environment.connect.writes
    guard await writes.allow(approval.personalKind) else { throw .invalidRequest(Self.notAllowed(approval)) }
    let name = named ? approval.target : nil
    let found = await writes.targets(named: name, of: approval.personalKind)
    guard !found.isEmpty || name != nil else { throw .invalidRequest(Self.noDefault(approval)) }
    let execution: NextUp.Execution = found.isEmpty ? .targetGone(name ?? "") : .choosing(found)
    _ = try claim(card.id) { now in
      now.version == card.version && now.execution == card.execution ? now.with(execution: execution) : nil
    }
    await follow([.nextUps])
  }

  /// Writes into the target the person confirmed, out of those the card showed. Writing it twice is not
  /// possible: only one claim moves it from choosing to writing. When the database cannot keep what was made, it
  /// is removed again; when even that fails, the card stays writing, for the app to find it when it next opens.
  private func write(_ command: ApproveNextUp, into id: String) async throws(HostError) {
    let now = environment.now()
    let marker = environment.newID().description
    let claimed = try claim(command.card) { card in
      guard card.version == command.version, card.isShown(at: now), case .choosing(let found) = card.execution,
        let target = found.first(where: { $0.id == id })
      else { return nil }
      return card.with(execution: .writing(marker: marker, into: target))
    }
    guard case .approval(let approval) = claimed.kind, case .writing(_, let target) = claimed.execution else { return }
    await follow([.nextUps])
    let writes = environment.connect.writes
    let identifier: String
    do throws(WriteFailure) {
      identifier = try await writes.make(approval, in: target, marker: marker)
    } catch {
      switch error {
      case .targetGone(let name):
        await settle(claimed, to: .targetGone(name))
        throw .invalidRequest("\(name) is no longer on this Mac; approve again to use the default one")
      case .failed(let reason):
        await settle(claimed, to: .waiting)
        throw .invalidRequest(reason)
      }
    }
    let made = Approved(identifier: identifier, marker: marker, into: target)
    let kept = Result { () throws(HostError) in
      try attempt {
        try database.changeNextUp(claimed.id) { card in
          card.execution == claimed.execution ? card.with(execution: .made(made)) : nil
        }
      }?.after
    }
    guard case .success(.some) = kept else {
      do throws(WriteFailure) {
        try await writes.remove(made, for: approval)
        await settle(claimed, to: .waiting)
      } catch {
        await follow([.nextUps])
      }
      if case .failure(let error) = kept { throw error }
      throw .invalidRequest(NextUp.changed)
    }
    await follow([.nextUps])
  }

  public func undoApproval(_ command: UndoApproval) async throws(HostError) -> Done {
    let claimed = try claim(command.card) { card in
      guard card.version == command.version, case .made(let made) = card.execution, made.identifier == command.made
      else { return nil }
      return card.with(execution: .undoing(made))
    }
    guard case .approval(let approval) = claimed.kind, case .undoing(let made) = claimed.execution else {
      return Done()
    }
    await follow([.nextUps])
    do {
      try await environment.connect.writes.remove(made, for: approval)
    } catch {
      await settle(claimed, to: .made(made))
      throw .invalidRequest(Self.reason(error))
    }
    await settle(claimed, to: .waiting)
    return Done()
  }

  /// What the app was doing to cards when it last stopped, settled where it can be told: a card being started
  /// is started when its message was kept and goes back where it was when not; an approval being written is
  /// approved when what it wrote is there and waits again when it is not; one being undone is removed again.
  /// What cannot be looked at now stays as it is, to be settled when the app next opens. A card of a project
  /// deleted for good goes once settled.
  func recoverNextUps() async {
    let writes = environment.connect.writes
    let projects = Set(store.projects().map(\.id) + store.setAsideProjects())
    for card in (try? database.allNextUps()) ?? [] {
      if case .starting(let from, let message) = card.place {
        let said = (try? database.hasMessage(message)) ?? false
        _ = try? database.changeNextUp(card.id) { $0.place == card.place ? $0.with(place: said ? .started : from) : nil }
      }
      var execution = card.execution
      if case .approval(let approval) = card.kind {
        switch card.execution {
        case .writing(let marker, let target):
          switch await writes.find(marker, for: approval, in: target) {
          case .found(let identifier):
            execution = .made(Approved(identifier: identifier, marker: marker, into: target))
          case .absent: execution = .waiting
          case .unknown: break
          }
        case .undoing:
          if case .undoing(let made) = card.execution,
            (try? await writes.remove(made, for: approval)) != nil
          {
            execution = .waiting
          }
        case .waiting, .choosing, .targetGone, .made: break
        }
        if execution != card.execution {
          _ = try? database.changeNextUp(card.id) { $0.execution == card.execution ? $0.with(execution: execution) : nil }
        }
      }
      if let project = card.home.project, !projects.contains(project), !execution.isUnderWay {
        try? database.forgetNextUp(card.id)
      }
    }
  }

  /// Changes the card in one write when its project is open and `change` allows it; refused otherwise, with
  /// the card as it is.
  private func claim(_ id: EntityID, _ change: (NextUp) -> NextUp?) throws(HostError) -> NextUp {
    guard let found = try attempt({ try database.nextUp(id) }) else { throw .notFound("card \(id)") }
    guard loci.context.isActive(found.home) else { throw .invalidRequest(NextUp.closed) }
    guard let result = try attempt({ try database.changeNextUp(id, change) }) else { throw .notFound("card \(id)") }
    guard let after = result.after else { throw .invalidRequest(NextUp.changed) }
    return after
  }

  /// Moves a claimed card's execution on, if no one else moved it meanwhile.
  private func settle(_ claimed: NextUp, to execution: NextUp.Execution) async {
    _ = try? database.changeNextUp(claimed.id) { card in
      card.execution == claimed.execution ? card.with(execution: execution) : nil
    }
    await follow([.nextUps])
  }

  private static func notAllowed(_ approval: Approval) -> String {
    approval.personalKind == .events
      ? "Loci may not add to your calendar; allow it in System Settings › Privacy & Security › Calendars"
      : "Loci may not add to your reminders; allow it in System Settings › Privacy & Security › Reminders"
  }

  private static func noDefault(_ approval: Approval) -> String {
    approval.personalKind == .events ? "This Mac has no default calendar" : "This Mac has no default reminders list"
  }

  private static func reason(_ failure: WriteFailure) -> String {
    switch failure {
    case .targetGone(let name): "\(name) is no longer on this Mac"
    case .failed(let reason): reason
    }
  }
}

extension AgentContext {
  /// Puts a card on the home's deck in one write. The same key again keeps where the person put it, unless they
  /// started it; one they declined stays declined, and the call is refused.
  func put(_ kind: NextUp.Kind, what: String, key: String, in home: Home) async throws(HostError) -> NextUp {
    let now = environment.now()
    let id = environment.newID()
    let result = try attempt {
      try database.putNextUp(withKey: key, in: home) { existing in
        guard let existing else { return NextUp(id: id, home: home, key: key, kind: kind, what: what, shownAt: now) }
        return existing.putAgain(kind, what: what, at: now)
      }
    }
    guard let card = result.after else { throw .invalidRequest(NextUp.declinedBefore) }
    await follower.follow([.nextUps])
    return card
  }
}

extension NextUp {
  static let declinedBefore = "The person declined this card before; it does not come back."
  static let changed = "This card changed or was dealt with since it was shown; look at it again."
  static let closed = "This card's project is archived or deleted."
}
