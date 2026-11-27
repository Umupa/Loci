import Foundation
import LociModel
import Testing

@testable import LociHost

/// CH-S1, CH-S4: how tired the companion is and the last thing it said in the main conversation, for its dot
/// and the line under its name.
@Suite(.timeLimit(.minutes(1)))
struct LociPresenceTests {
  @Test func aCompanionThatHasSaidNothingIsAwakeWithNothingToShow() async throws {
    try await withHost { host, _, _ in
      let presence = try await host.lociPresence()
      #expect(presence == LociPresence(tiredness: .awake, lastSaid: nil))
    }
  }

  @Test func theLastThingSaidIsTheLatestReplyInTheMainConversationOnly() async throws {
    let agent = FakeAgent { prompt in .reply(prompt.contains("Raft") ? "Read it." : "Morning.\n\nTea first.") }
    try await withHost(agent: agent) { host, _, _ in
      let presence = host.subscribe(CompanionPresence())
      _ = try await host.run(SendMessage(to: .main, text: "早"))
      _ = try #require(await settled(host))
      #expect(await value(presence) { $0.lastSaid == "Morning.\n\nTea first." } != nil)

      let item = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n\nterm and index\n"))
      _ = try await host.run(SendMessage(to: .item(item.id), text: "Raft?"))
      _ = try #require(await settled(host, .item(item.id)))

      let after = try await host.lociPresence()
      #expect(after.lastSaid == "Morning.\n\nTea first.")
    }
  }

  @Test func subscriptionsFollowFeelingsAndEndedTurnsButNotEveryStreamedWord() {
    #expect(CompanionPresence().isAffected(by: [.loci(.feelings)]))
    #expect(CompanionPresence().isAffected(by: [.turnEnded(.main)]))
    #expect(!CompanionPresence().isAffected(by: [.conversation(.main)]))
    #expect(!CompanionPresence().isAffected(by: [.loci(.soul)]))
  }
}
