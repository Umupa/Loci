import Foundation
import LociModel
import LociStore
import Synchronization
import Testing

@testable import LociHost

/// UI-S8: a picker gets the models an agent listed last at once; old lists are asked for again in the background.
@Suite(.timeLimit(.minutes(1)))
struct AgentModelCatalogTests {
  private static let sol = AgentModel(id: "gpt-6.1-sol", name: "GPT-6.1-Sol")
  private static let luna = AgentModel(id: "gpt-6-luna", name: "GPT-6 Luna")

  /// What the program answers, how often it was asked, the clock, the version, and how often a change was told.
  private final class World: Sendable {
    let answer = Mutex<[AgentModel]>([sol])
    let asked = Mutex(0)
    let now = Mutex<Int64>(1_000)
    let version = Mutex<String?>("1.0.0")
    let told = Mutex(0)
    let database: StoreDatabase

    init() throws {
      database = try StoreDatabase.inMemory()
    }

    func catalog() -> AgentModelCatalog {
      AgentModelCatalog(
        database: database,
        list: { _ in
          self.asked.withLock { $0 += 1 }
          return self.answer.withLock { $0 }
        },
        version: { _ in self.version.withLock { $0 } },
        now: { Timestamp(millisecondsSince1970: self.now.withLock { $0 }) },
        changed: { self.told.withLock { $0 += 1 } })
    }

    func waitUntilAsked(_ count: Int) async {
      for _ in 0..<200 where asked.withLock({ $0 }) < count { try? await Task.sleep(for: .milliseconds(10)) }
    }
  }

  @Test func theFirstListIsAskedForAndThenAnsweredFromWhatWasKept() async throws {
    let world = try World()

    #expect(await world.catalog().models(of: .codex) == [Self.sol])
    #expect(await world.catalog().models(of: .codex) == [Self.sol])

    #expect(world.asked.withLock { $0 } == 1)
    #expect(world.told.withLock { $0 } == 1)
  }

  @Test func anOldListIsAnsweredAtOnceAndAskedForAgainInTheBackground() async throws {
    let world = try World()
    let catalog = world.catalog()
    _ = await catalog.models(of: .codex)
    world.answer.withLock { $0 = [Self.sol, Self.luna] }
    world.now.withLock { $0 += AgentModelCatalog.freshFor + 1 }

    #expect(await catalog.models(of: .codex) == [Self.sol])
    await world.waitUntilAsked(2)
    for _ in 0..<200 where world.told.withLock({ $0 }) < 2 { try? await Task.sleep(for: .milliseconds(10)) }

    #expect(await catalog.models(of: .codex) == [Self.sol, Self.luna])
    #expect(world.told.withLock { $0 } == 2)
  }

  @Test func anotherVersionOfTheProgramIsAskedAgain() async throws {
    let world = try World()
    let catalog = world.catalog()
    _ = await catalog.models(of: .codex)

    world.version.withLock { $0 = "1.1.0" }
    _ = await catalog.models(of: .codex)
    await world.waitUntilAsked(2)

    #expect(world.asked.withLock { $0 } == 2)
  }

  @Test func aProgramThatListsNothingKeepsItsLastList() async throws {
    let world = try World()
    let catalog = world.catalog()
    _ = await catalog.models(of: .codex)
    world.answer.withLock { $0 = [] }

    await catalog.refresh([.codex])

    #expect(await catalog.models(of: .codex) == [Self.sol])
    #expect(world.told.withLock { $0 } == 1)
  }

  @Test func aListThatDidNotChangeIsNotAnnounced() async throws {
    let world = try World()
    let catalog = world.catalog()
    _ = await catalog.models(of: .codex)

    await catalog.refresh([.codex])

    #expect(world.asked.withLock { $0 } == 2)
    #expect(world.told.withLock { $0 } == 1)
  }
}
