import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// RS-S2, RS-S3: resetting leaves a Loci that has never been used, on the runtime that was chosen.
@Suite(.timeLimit(.minutes(1)))
struct ResetScenarioTests {
  @Test func aHostStartedAfterAResetHasNoItemsNoConversationAndAFreshMemory() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    _ = try await first.run(AddTextItem(fileName: "borg.md", text: "# Borg"))
    _ = try await first.run(SendMessage(to: .main, text: "在吗"))
    _ = try #require(await settled(first))
    try place.store.home(.chat).setMemoryWritable(true)
    try place.edit(place.root.appending(path: "agent/MEMORY.md")) { $0 + "- 喜欢读论文\n" }

    try await first.reset()
    let next = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let items = try await next.run(ListItems())
    let main = try await next.conversation(.main)
    let memory = try place.store.agentText(.memory)
    await next.close()

    #expect(items.isEmpty)
    #expect(main.entries.isEmpty)
    #expect(memory == "# Memory\n")
  }

  @Test func theChosenRuntimeIsKept() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    _ = try await first.run(SetRuntime(Runtime(provider: .codex, model: "gpt-5", effort: .high)))

    try await first.reset()
    let next = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let runtime = try await next.run(ReadRuntime())
    await next.close()

    #expect(runtime == Runtime(provider: .codex, model: "gpt-5", effort: .high))
  }
}
