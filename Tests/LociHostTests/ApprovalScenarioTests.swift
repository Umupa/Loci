import Foundation
import LociModel
import Testing

@testable import LociHost

/// NX-S6, NX-S7, NX-S9: an approval card writes to the calendar or reminders only once the person approves the
/// version they saw and confirms where the app found it goes, once however many Macs approve it, and can be
/// undone; the companion's session has no way to approve, nor to say which calendar it is.
@Suite(.timeLimit(.minutes(1)))
struct ApprovalScenarioTests {
  static let start = Timestamp(millisecondsSince1970: 1_764_504_000_000)
  static let review = Approval.event(EventDraft(title: "投资复盘", start: start, calendar: "家庭"))
  static let family = ApprovalTarget(id: "cal-2", name: "家庭", source: "iCloud")

  static func propose(
    _ approval: Approval = review, in session: LocalSession = .conversation(.main), on host: LocalHost
  ) async throws -> NextUp {
    let reply = await Background.call(ProposeApproval(approval), from: session, on: host)
    guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
    return try JSONDecoder().decode(NextUp.self, from: data)
  }

  /// The first step: the card as it then shows where it goes.
  @discardableResult
  static func find(_ card: NextUp, _ step: ApproveNextUp.Step = .find, on host: LocalHost) async throws -> NextUp {
    _ = try await host.run(ApproveNextUp(card.id, version: card.version, step))
    return try #require(try Self.card(card.id, on: host))
  }

  /// Both steps, confirming the one target found.
  static func approve(_ card: NextUp, on host: LocalHost) async throws {
    let shown = try await find(card, on: host)
    guard case .choosing(let found) = shown.execution, found.count == 1 else {
      throw HostError.invalidRequest("\(shown.execution)")
    }
    _ = try await host.run(ApproveNextUp(shown.id, version: shown.version, .into(found[0].id)))
  }

  static func card(_ id: EntityID, on host: LocalHost) throws -> NextUp? {
    try host.database.nextUp(id)
  }

  static func made(_ card: NextUp?) throws -> Approved {
    guard case .made(let made)? = card?.execution else { throw HostError.invalidRequest("not made") }
    return made
  }

  @Test func nothingIsWrittenUntilThePersonConfirmsWhereItGoesAndUndoingRemovesIt() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let card = try await Self.propose(on: host)
      #expect(try await host.nextUps(of: .chat).map(\.id) == [card.id])

      let shown = try await Self.find(card, on: host)
      #expect(shown.execution == .choosing([Self.family]))
      #expect(world.writes.made.isEmpty)

      _ = try await host.run(ApproveNextUp(shown.id, version: shown.version, .into("cal-2")))
      #expect(world.writes.made.map(\.title) == ["投资复盘"])
      #expect(world.writes.madeIn == ["cal-2"])
      let approved = try #require(try Self.card(card.id, on: host))
      let made = try Self.made(approved)
      #expect(made.into == Self.family)

      _ = try await host.run(UndoApproval(card.id, version: approved.version, made: made.identifier))
      #expect(world.writes.made.isEmpty)
      #expect(try Self.card(card.id, on: host)?.execution == .waiting)
    }
  }

  @Test func aCalendarIsLookedForOnlyOnceMacOSLetsTheAppSoOneThatIsThereIsFound() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let card = try await Self.propose(on: host)
      #expect(world.writes.looked == 0)
      #expect(card.execution == .waiting)

      let shown = try await Self.find(card, on: host)

      #expect(shown.execution == .choosing([Self.family]))
    }
  }

  @Test func twoCalendarsOfOneNameAreShownWithTheirAccountsAndOnlyThePickedOneIsWritten() async throws {
    let world = ConnectWorld()
    world.writes.set(targets: [
      ApprovalTarget(id: "cal-1", name: "个人", source: "iCloud"), Self.family,
      ApprovalTarget(id: "cal-3", name: "家庭", source: "Google"),
    ])
    try await withHost(connect: world.environment) { host, _, _ in
      let shown = try await Self.find(try await Self.propose(on: host), on: host)
      guard case .choosing(let found) = shown.execution else { throw HostError.invalidRequest("nothing found") }
      #expect(found.map(\.source) == ["iCloud", "Google"])

      _ = try await host.run(ApproveNextUp(shown.id, version: shown.version, .into("cal-3")))

      #expect(world.writes.madeIn == ["cal-3"])
    }
  }

  @Test func aTargetTheCardDidNotShowIsNeverWritten() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let shown = try await Self.find(try await Self.propose(on: host), on: host)

      await #expect(throws: HostError.invalidRequest(NextUp.changed)) {
        try await host.run(ApproveNextUp(shown.id, version: shown.version, .into("cal-1")))
      }
      await #expect(throws: HostError.invalidRequest(NextUp.changed)) {
        try await host.run(ApproveNextUp(shown.id, version: shown.version - 1, .into("cal-2")))
      }

      #expect(world.writes.made.isEmpty)
    }
  }

  @Test func anApprovalOfAnOlderVersionWritesNothing() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let shown = try await Self.propose(on: host)
      let later = EventDraft(
        title: "投资复盘", start: Self.start, end: Timestamp(millisecondsSince1970: 1_764_515_000_000), calendar: "个人")
      let changed = try await Self.propose(.event(later), on: host)
      #expect(changed.id == shown.id && changed.version > shown.version)

      await #expect(throws: HostError.invalidRequest(NextUp.changed)) { try await Self.find(shown, on: host) }

      #expect(world.writes.made.isEmpty)
      try await Self.approve(changed, on: host)
      #expect(world.writes.madeIn == ["cal-1"])
    }
  }

  @Test func twoMacsApprovingAtOnceWriteOnce() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let shown = try await Self.find(try await Self.propose(on: host), on: host)
      world.writes.hold()
      let confirm = ApproveNextUp(shown.id, version: shown.version, .into("cal-2"))

      let first = Task { try await host.run(confirm) }
      while true {
        if case .writing = try Self.card(shown.id, on: host)?.execution { break }
        try await Task.sleep(for: .milliseconds(5))
      }
      await #expect(throws: HostError.invalidRequest(NextUp.changed)) { try await host.run(confirm) }
      world.writes.release()
      _ = try await first.value

      #expect(world.writes.made.count == 1)
      _ = try Self.made(try Self.card(shown.id, on: host))
    }
  }

  @Test func whatWasMadeIsRemovedWhenTheCardCannotKeepIt() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let shown = try await Self.find(try await Self.propose(on: host), on: host)
      let database = host.database
      world.writes.afterMake { _ = try? database.changeNextUp(shown.id) { $0.with(execution: .waiting) } }

      await #expect(throws: HostError.self) {
        try await host.run(ApproveNextUp(shown.id, version: shown.version, .into("cal-2")))
      }

      #expect(world.writes.made.isEmpty)
    }
  }

  @Test func aDoneApprovalPutAwayAndBroughtBackIsStillDoneAndCannotBeWrittenAgain() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let card = try await Self.propose(on: host)
      try await Self.approve(card, on: host)
      let approved = try #require(try Self.card(card.id, on: host))

      let declined = try await host.run(SetNextUp(card.id, .decline, version: approved.version))
      _ = try await host.run(SetNextUp(card.id, .restore, version: declined.version))
      let back = try #require(try Self.card(card.id, on: host))
      _ = try await Self.propose(on: host)

      let made = try Self.made(back)
      await #expect(throws: HostError.self) { try await Self.find(back, on: host) }
      #expect(world.writes.made.count == 1)
      _ = try await host.run(UndoApproval(card.id, version: back.version, made: made.identifier))
      #expect(world.writes.made.isEmpty)
    }
  }

  @Test func anUndoFromAMacThatSawAnEarlierApprovalLeavesWhatALaterOneMade() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let card = try await Self.propose(on: host)
      try await Self.approve(card, on: host)
      let seen = try #require(try Self.card(card.id, on: host))
      let first = try Self.made(seen)
      _ = try await host.run(UndoApproval(card.id, version: seen.version, made: first.identifier))
      try await Self.approve(try #require(try Self.card(card.id, on: host)), on: host)

      await #expect(throws: HostError.invalidRequest(NextUp.changed)) {
        try await host.run(UndoApproval(card.id, version: seen.version, made: first.identifier))
      }

      #expect(world.writes.made.count == 1)
      #expect(try Self.made(try Self.card(card.id, on: host)).identifier != first.identifier)
    }
  }

  @Test func undoingRemovesWhatWasMadeEvenAfterASyncGaveItANewIdentifier() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let card = try await Self.propose(on: host)
      try await Self.approve(card, on: host)
      let approved = try #require(try Self.card(card.id, on: host))
      world.writes.resync()

      _ = try await host.run(UndoApproval(card.id, version: approved.version, made: try Self.made(approved).identifier))

      #expect(world.writes.made.isEmpty)
      #expect(try Self.card(card.id, on: host)?.execution == .waiting)
    }
  }

  @Test func whatCannotBeRemovedStaysApprovedToUndoAgain() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let card = try await Self.propose(on: host)
      try await Self.approve(card, on: host)
      let approved = try #require(try Self.card(card.id, on: host))
      world.writes.jam()

      await #expect(throws: HostError.self) {
        try await host.run(UndoApproval(card.id, version: approved.version, made: try Self.made(approved).identifier))
      }

      #expect(world.writes.made.count == 1)
      _ = try Self.made(try Self.card(card.id, on: host))
    }
  }

  @Test func aCalendarThatIsGoneIsNotSwappedForAnotherOrTheDefaultUntilThePersonSaysSo() async throws {
    let world = ConnectWorld()
    world.writes.set(targets: [ApprovalTarget(id: "cal-1", name: "个人", source: "iCloud")])
    try await withHost(connect: world.environment) { host, _, _ in
      let gone = try await Self.find(try await Self.propose(on: host), on: host)
      #expect(gone.execution == .targetGone("家庭"))
      #expect(world.writes.made.isEmpty)

      let fallback = try await Self.find(gone, .findDefault, on: host)
      #expect(fallback.execution == .choosing([ApprovalTarget(id: "cal-1", name: "个人", source: "iCloud")]))
      _ = try await host.run(ApproveNextUp(fallback.id, version: fallback.version, .into("cal-1")))

      #expect(world.writes.madeIn == ["cal-1"])
    }
  }

  @Test func anArchivedProjectsApprovalIsNotWritten() async throws {
    let world = ConnectWorld()
    try await withHost(agent: FakeAgent(provider: .codex), connect: world.environment) { host, _, _ in
      let project = try await ProjectScenarioTests.start(host)
      let card = try await Self.propose(in: .conversation(.project(project)), on: host)
      let shown = try await Self.find(card, on: host)
      _ = try await host.run(ArchiveProject(project, archived: true))

      await #expect(throws: HostError.invalidRequest(NextUp.closed)) {
        try await host.run(ApproveNextUp(shown.id, version: shown.version, .into("cal-2")))
      }

      #expect(world.writes.made.isEmpty)
    }
  }

  @Test func aProjectArchivedWhileMacOSAsksForAccessShowsNoTarget() async throws {
    let world = ConnectWorld()
    try await withHost(agent: FakeAgent(provider: .codex), connect: world.environment) { host, _, _ in
      let project = try await ProjectScenarioTests.start(host)
      let card = try await Self.propose(in: .conversation(.project(project)), on: host)
      world.writes.whileAsking { _ = try? await host.run(ArchiveProject(project, archived: true)) }

      await #expect(throws: HostError.invalidRequest(NextUp.closed)) { try await Self.find(card, on: host) }

      #expect(try Self.card(card.id, on: host)?.execution == .waiting)
    }
  }

  @Test func aDeclinedApprovalWritesNothing() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let card = try await Self.propose(.reminder(ReminderDraft(title: "交房租")), on: host)

      _ = try await host.run(SetNextUp(card.id, .decline, version: card.version))

      await #expect(throws: HostError.self) { try await Self.find(card, on: host) }
      #expect(world.writes.made.isEmpty)
      #expect(try await host.nextUps(of: .chat).isEmpty)
    }
  }

  @Test func anApprovalMacOSRefusesLeavesTheCardWaiting() async throws {
    let world = ConnectWorld()
    world.writes.refuse()
    try await withHost(connect: world.environment) { host, _, _ in
      let card = try await Self.propose(on: host)

      await #expect(throws: HostError.self) { try await Self.find(card, on: host) }

      #expect(world.writes.made.isEmpty)
      #expect(try Self.card(card.id, on: host)?.execution == .waiting)
    }
  }

  @Test func theCompanionCannotApproveOrUndo() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let card = try await Self.propose(on: host)

      let approved = await Background.call(
        ApproveNextUp(card.id, version: card.version), from: .conversation(.main), on: host)
      let undone = await Background.call(
        UndoApproval(card.id, version: card.version, made: "item-1"), from: .conversation(.main), on: host)

      #expect(RunToolScenarioTests.refused(approved) == "loci cannot run \(ApproveNextUp.name)")
      #expect(RunToolScenarioTests.refused(undone) == "loci cannot run \(UndoApproval.name)")
      #expect(world.writes.made.isEmpty)
    }
  }

  @Test func whatTheAppWasDoingToCardsWhenItStoppedIsSettledOnlyWhereItCanBeTold() async throws {
    let place = Place()
    defer { place.remove() }
    let connect = ConnectWorld()
    connect.writes.grant()
    let world = TestWorld(agent: FakeAgent(provider: .codex), connect: connect.environment)
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let written = try await Self.propose(on: first)
    let lost = try await Self.propose(.reminder(ReminderDraft(title: "交房租")), on: first)
    let undoing = try await Self.propose(.reminder(ReminderDraft(title: "交水费")), on: first)
    let asked = try await NextUpScenarioTests.add("纳指回撤", asking: "还定投吗", on: first)
    let unsaid = try await NextUpScenarioTests.add("JR Pass 涨价", asking: "要买吗", on: first)
    guard case .approval(let approval) = written.kind, case .approval(let bill) = undoing.kind else {
      throw HostError.invalidRequest("not an approval")
    }
    let identifier = connect.writes.keep(approval, in: "cal-2", marker: "m-1")
    let stuck = connect.writes.keep(bill, in: "cal-1", marker: "m-3")
    _ = try await first.run(StartNextUp(asked.id, version: asked.version))
    _ = try #require(await settled(first))
    let said = try #require(try first.database.messages(of: .conversation(.main)).first { $0.isTyped })
    _ = try first.database.changeNextUp(written.id) {
      $0.with(execution: .writing(marker: "m-1", into: Self.family))
    }
    _ = try first.database.changeNextUp(lost.id) { $0.with(execution: .writing(marker: "m-2", into: Self.family)) }
    _ = try first.database.changeNextUp(undoing.id) {
      $0.with(execution: .undoing(Approved(identifier: stuck, marker: "m-3", into: Self.family)))
    }
    _ = try first.database.changeNextUp(asked.id) { $0.with(place: .starting(from: .kept, message: said.id)) }
    _ = try first.database.changeNextUp(unsaid.id) { $0.with(place: .starting(from: .kept, message: EntityID())) }
    await first.close()
    connect.writes.jam()

    let second = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let cards = try [written.id, lost.id, undoing.id, asked.id, unsaid.id].map { try Self.card($0, on: second) }
    await second.close()

    #expect(cards[0]?.execution == .made(Approved(identifier: identifier, marker: "m-1", into: Self.family)))
    #expect(cards[1]?.execution == .waiting)
    #expect(cards[2]?.execution == .undoing(Approved(identifier: stuck, marker: "m-3", into: Self.family)))
    #expect(cards[3]?.place == .started)
    #expect(cards[4]?.place == .kept)
  }

  @Test func aWriteThatCannotBeLookedAtWhenTheAppOpensIsNotOfferedAgain() async throws {
    let place = Place()
    defer { place.remove() }
    let connect = ConnectWorld()
    connect.writes.grant()
    let world = TestWorld(agent: FakeAgent(provider: .codex), connect: connect.environment)
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let card = try await Self.propose(on: first)
    _ = try first.database.changeNextUp(card.id) { $0.with(execution: .writing(marker: "m-1", into: Self.family)) }
    await first.close()
    connect.writes.blindfold()

    let second = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let after = try Self.card(card.id, on: second)
    await second.close()

    #expect(after?.execution == .writing(marker: "m-1", into: Self.family))
  }

  @Test func aDeletedProjectsCardIsKeptUntilWhatItWasWritingIsSettled() async throws {
    let place = Place()
    defer { place.remove() }
    let connect = ConnectWorld()
    connect.writes.grant()
    let world = TestWorld(agent: FakeAgent(provider: .codex), connect: connect.environment)
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let project = try await ProjectScenarioTests.start(first)
    let card = try await Self.propose(in: .conversation(.project(project)), on: first)
    _ = try first.database.changeNextUp(card.id) { $0.with(execution: .writing(marker: "m-1", into: Self.family)) }
    _ = try await first.run(DeleteProject(project))
    await first.discardSetAsideProjects()
    #expect(try Self.card(card.id, on: first) != nil)
    await first.close()

    let second = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let after = try Self.card(card.id, on: second)
    await second.close()

    #expect(after == nil)
  }
}
