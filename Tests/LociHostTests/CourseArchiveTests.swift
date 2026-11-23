import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct CourseArchiveTests {
  @Test("A broken course file shows its problem in the gallery and repairing it brings the course back")
  func repairsGalleryEntry() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, place, _ in
      let course = try await host.run(StartCourse(topic: "Quorums"))
      let gallery = host.subscribe(WatchCourses())
      let file = place.root.appending(path: "courses/\(course.id)/course.json")
      let valid = try Data(contentsOf: file)
      try Data("{ broken".utf8).write(to: file, options: .atomic)

      #expect(
        await value(gallery) { entries in
          entries.contains {
            if case .invalid(let id, let problem) = $0 {
              return id == course.id && problem.path == "courses/\(id)/course.json"
            }
            return false
          }
        } != nil)
      try valid.write(to: file, options: .atomic)
      #expect(
        await value(gallery) { entries in
          entries.contains { if case .course(let card) = $0 { card.id == course.id } else { false } }
        } != nil)
    }
  }

  @Test("Deleting something else commits the previous course deletion and removes its stored conversation")
  func finishesEarlierDeletion() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, _, _ in
      let course = try await host.run(StartCourse(topic: "Quorums"))
      let ref = ConversationRef.course(course.id)
      let said = await value(host.subscribe(OneConversation(ref))) {
        $0.turn == nil && $0.entries.count >= 2
      }
      #expect(said != nil)
      _ = try await host.run(DeleteCourse(course.id))
      let item = try await host.run(AddTextItem(fileName: "another.md", text: "# Another"))
      _ = try await host.run(DeleteItems([item.id]))

      #expect(try await host.run(RestoreDeletedCourse()) == nil)
      #expect(try host.database.messages(of: .conversation(ref)).isEmpty)
      #expect(try await host.run(RestoreDeleted()).map(\.id) == [item.id])
    }
  }
}

extension CourseArchiveTests {
  @Test("An unsuccessful replacement deletion leaves the previous course and its conversation undoable")
  func failedReplacementKeepsUndo() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, _, _ in
      let course = try await host.run(StartCourse(topic: "Quorums"))
      let ref = ConversationRef.course(course.id)
      let said = try #require(
        await value(host.subscribe(OneConversation(ref))) {
          $0.turn == nil && $0.entries.count >= 2
        })
      _ = try await host.run(DeleteCourse(course.id))
      await #expect(throws: HostError.self) { try await host.run(DeleteItems([EntityID()])) }
      #expect(try await host.run(RestoreDeletedCourse())?.id == course.id)
      #expect(try await host.conversation(ref).entries == said.entries)
    }
  }

  @Test("A failed trip to the Trash preserves the course data and conversation for cleanup")
  func retainsConversationUntilTrashSucceeds() async throws {
    let place = Place()
    defer { place.remove() }
    let agent = FakeAgent(provider: .codex)
    let world = TestWorld(agent: agent)
    let discard = Discard { file in
      if file.pathComponents.contains("courses") || file.pathComponents.contains("course-cleanup") {
        throw CocoaError(.fileWriteNoPermission)
      }
      try FileManager.default.removeItem(at: file)
    }
    let environment = HostEnvironment(
      newID: { world.nextID() }, now: { world.now }, defaultRuntime: Runtime(provider: .codex),
      discard: discard, agents: { _ in agent })
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: environment)
    let course = try await host.run(StartCourse(topic: "Quorums"))
    let ref = ConversationRef.course(course.id)
    let said = try #require(
      await value(host.subscribe(OneConversation(ref))) {
        $0.turn == nil && $0.entries.count >= 2
      })
    _ = try await host.run(DeleteCourse(course.id))
    let item = try await host.run(AddTextItem(fileName: "next.md", text: "# Next"))
    _ = try await host.run(DeleteItems([item.id]))
    #expect(try await host.run(RestoreDeletedCourse()) == nil)
    #expect(
      try host.database.messages(of: .conversation(ref))
        == said.entries.compactMap {
          if case .message(let message) = $0 { message } else { nil }
        })
    await host.close()
  }
}
