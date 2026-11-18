import Foundation
import LociModel
import Testing

@testable import LociStore

struct WatchTests {
  /// The one test against real FSEvents. It checks that a change arrives, not how fast; the one-second
  /// promise of α1-S5 is checked in the running app.
  @Test func anOutsideEditToSoulIsReported() async throws {
    let store = temporaryStore()
    defer { try? FileManager.default.removeItem(at: store.root) }
    try store.prepareAgent(soul: "You are Loci.\n")
    let changes = store.changes()

    try Data("You are someone else.\n".utf8).write(to: store.agentFolder.appending(path: "SOUL.md"))

    let heard = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        for await batch in changes where batch.contains(.loci(.soul)) { return true }
        return false
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(5))
        return false
      }
      let first = await group.next() ?? false
      group.cancelAll()
      return first
    }

    #expect(heard)
    #expect(try store.agentText(.soul) == "You are someone else.\n")
  }
}
