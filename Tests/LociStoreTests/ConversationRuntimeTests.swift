import Foundation
import LociModel
import Testing

@testable import LociStore

/// L-S6: each conversation keeps what it runs on, and loses it with the conversation.
struct ConversationRuntimeTests {
  @Test func eachConversationKeepsItsOwnRuntime() throws {
    let database = try StoreDatabase.inMemory()
    let item = ConversationRef.item(Fixture.id(2))
    #expect(try database.runtime(of: .main) == nil)

    try database.setRuntime(Runtime(provider: .codex, model: "gpt-5", effort: .high), of: .main)
    try database.setRuntime(Runtime(provider: .antigravity, model: "gemini"), of: item)
    try database.setRuntime(Runtime(provider: .codex, effort: .low), of: .main)

    #expect(try database.runtime(of: .main) == Runtime(provider: .codex, effort: .low))
    #expect(try database.runtime(of: item) == Runtime(provider: .antigravity, model: "gemini"))
    #expect(try database.runtime(of: .project(Fixture.id(3))) == nil)
  }

  @Test func deletingAConversationForgetsItsRuntime() throws {
    let database = try StoreDatabase.inMemory()
    let item = ConversationRef.item(Fixture.id(2))
    try database.setRuntime(Runtime(provider: .codex), of: item)
    try database.setRuntime(Runtime(provider: .codex), of: .project(Fixture.id(3)))

    try database.deleteConversation(on: Fixture.id(2))
    try database.forgetProject(Fixture.id(3))

    #expect(try database.runtime(of: item) == nil)
    #expect(try database.runtime(of: .project(Fixture.id(3))) == nil)
  }
}
