import Foundation
import LociModel
import Testing

@testable import LociHost

/// NX-S6, NX-S7: an approval card writes to the calendar or reminders only once the person approves it, and
/// can be undone; the companion's session has no way to approve.
@Suite(.timeLimit(.minutes(1)))
struct ApprovalScenarioTests {
  static let review = Approval.event(
    EventDraft(title: "投资复盘", start: Timestamp(millisecondsSince1970: 1_764_504_000_000), calendar: "家庭"))

  static func propose(_ approval: Approval = review, on host: LocalHost) async throws -> NextUp {
    let reply = await Background.call(ProposeApproval(approval), from: .conversation(.main), on: host)
    guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
    return try JSONDecoder().decode(NextUp.self, from: data)
  }

  @Test func nothingIsWrittenUntilTheCardIsApprovedAndUndoingRemovesIt() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let card = try await Self.propose(on: host)
      #expect(world.writes.made.isEmpty)
      #expect(try await host.nextUps(of: .chat).map(\.id) == [card.id])

      _ = try await host.run(ApproveNextUp(card.id))
      #expect(world.writes.made == [Self.review])
      guard case .approved = try await host.nextUps(of: .chat).first?.state else {
        throw HostError.invalidRequest("not approved")
      }

      _ = try await host.run(UndoApproval(card.id))
      #expect(world.writes.made.isEmpty)
      #expect(try await host.nextUps(of: .chat).first?.state == .new)
    }
  }

  @Test func aDeclinedApprovalWritesNothing() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let card = try await Self.propose(.reminder(ReminderDraft(title: "交房租")), on: host)

      _ = try await host.run(SetNextUp(card.id, .decline))

      #expect(world.writes.made.isEmpty)
      #expect(try await host.nextUps(of: .chat).isEmpty)
    }
  }

  @Test func anApprovalMacOSRefusesLeavesTheCardWaiting() async throws {
    let world = ConnectWorld()
    world.writes.refuse()
    try await withHost(connect: world.environment) { host, _, _ in
      let card = try await Self.propose(on: host)

      await #expect(throws: HostError.self) { try await host.run(ApproveNextUp(card.id)) }

      #expect(world.writes.made.isEmpty)
      #expect(try await host.nextUps(of: .chat).first?.state == .new)
    }
  }

  @Test func theCompanionCannotApproveOrUndo() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      let card = try await Self.propose(on: host)

      let approved = await Background.call(ApproveNextUp(card.id), from: .conversation(.main), on: host)
      let undone = await Background.call(UndoApproval(card.id), from: .conversation(.main), on: host)

      #expect(RunToolScenarioTests.refused(approved) == "loci cannot run \(ApproveNextUp.name)")
      #expect(RunToolScenarioTests.refused(undone) == "loci cannot run \(UndoApproval.name)")
      #expect(world.writes.made.isEmpty)
    }
  }
}
