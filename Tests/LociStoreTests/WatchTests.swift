import Foundation
import LociModel
import Testing

@testable import LociStore

struct WatchTests {
  /// The one test against real FSEvents. It checks that a change arrives, not how fast; the one-second
  /// promise of α1-S5 is checked in the running app.
  @Test func anOutsideEditToMentorJSONIsReported() async throws {
    let store = temporaryStore()
    defer { try? FileManager.default.removeItem(at: store.root) }
    let mentor = try Fixture.mentor()
    try store.create(mentor)
    let file = try store.mentorFolder(mentor.id).appending(path: Store.mentorFile)
    let changes = store.changes()

    let edited = try String(contentsOf: file, encoding: .utf8).replacing("调度", with: "排程")
    try Data(edited.utf8).write(to: file)

    let heard = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        for await batch in changes where batch.contains(.mentor(mentor.id)) { return true }
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
    #expect(try store.mentor(mentor.id).name == "排程")
  }
}
