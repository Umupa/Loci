import Foundation
import LociModel
import Testing

@testable import LociStore

/// L-S6: a conversation that chose its own runtime keeps it, and loses it with the conversation.
struct ConversationRuntimeTests {
  private let at = Timestamp(millisecondsSince1970: 1_000)

  @Test func eachConversationKeepsItsOwnRuntime() throws {
    let database = try StoreDatabase.inMemory()
    let item = ConversationRef.item(Fixture.id(2))
    let course = ConversationRef.course(Fixture.id(4))
    #expect(try database.runtime(of: item) == nil)

    try database.setRuntime(Runtime(provider: .codex, model: "gpt-5", effort: .high), of: course, at: at)
    try database.setRuntime(Runtime(provider: .antigravity, model: "gemini"), of: item, at: at)
    try database.setRuntime(Runtime(provider: .codex, effort: .low), of: course, at: at)

    #expect(try database.runtime(of: course) == Runtime(provider: .codex, effort: .low))
    #expect(try database.runtime(of: item) == Runtime(provider: .antigravity, model: "gemini"))
    #expect(try database.runtime(of: .project(Fixture.id(3))) == nil)
  }

  @Test func ownRuntimesAreListedTheMostRecentlyChosenFirst() throws {
    let database = try StoreDatabase.inMemory()
    let item = ConversationRef.item(Fixture.id(2))
    let project = ConversationRef.project(Fixture.id(3))
    try database.setRuntime(Runtime(provider: .codex), of: item, at: Timestamp(millisecondsSince1970: 1))
    try database.setRuntime(Runtime(provider: .grok), of: project, at: Timestamp(millisecondsSince1970: 2))

    #expect(try database.ownRuntimes().map(\.conversation) == [project, item])
  }

  @Test func aConversationThatFollowsItsKindAgainHasNoRuntimeOfItsOwn() throws {
    let database = try StoreDatabase.inMemory()
    let item = ConversationRef.item(Fixture.id(2))
    try database.setRuntime(Runtime(provider: .codex), of: item, at: at)

    try database.clearRuntime(of: item)

    #expect(try database.runtime(of: item) == nil)
    #expect(try database.ownRuntimes().isEmpty)
  }

  @Test func onlyRuntimesEqualToTheirKindsDefaultAreDropped() throws {
    let database = try StoreDatabase.inMemory()
    let same = ConversationRef.item(Fixture.id(2))
    let other = ConversationRef.item(Fixture.id(5))
    let course = ConversationRef.course(Fixture.id(4))
    try database.setRuntime(Runtime(provider: .codex), of: same, at: at)
    try database.setRuntime(Runtime(provider: .grok), of: other, at: at)
    try database.setRuntime(Runtime(provider: .codex), of: course, at: at)

    try database.dropRuntimes(equalTo: [.item: Runtime(provider: .codex)])

    #expect(
      try database.ownRuntimes().map(\.conversation).sorted { "\($0)" < "\($1)" }
        == [course, other].sorted { "\($0)" < "\($1)" })
  }

  @Test func deletingAConversationForgetsItsRuntime() throws {
    let database = try StoreDatabase.inMemory()
    let item = ConversationRef.item(Fixture.id(2))
    try database.setRuntime(Runtime(provider: .codex), of: item, at: at)
    try database.setRuntime(Runtime(provider: .codex), of: .project(Fixture.id(3)), at: at)

    try database.deleteConversation(on: Fixture.id(2))
    try database.forgetProject(Fixture.id(3))

    #expect(try database.runtime(of: item) == nil)
    #expect(try database.runtime(of: .project(Fixture.id(3))) == nil)
  }

  @Test func theModelsAnAgentListedAreKeptWithItsVersion() throws {
    let database = try StoreDatabase.inMemory()
    #expect(try database.listedModels(of: .codex) == nil)
    let listed = StoreDatabase.ListedModels(
      models: [AgentModel(id: "gpt-6.1-sol", name: "GPT-6.1-Sol")], version: "0.80.0", listed: at)

    try database.keepListedModels(listed, of: .codex)

    #expect(try database.listedModels(of: .codex) == listed)
    #expect(try database.listedModels(of: .antigravity) == nil)
  }
}
