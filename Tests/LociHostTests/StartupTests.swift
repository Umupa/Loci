import Foundation
import GRDB
import LociModel
import Testing

@testable import LociHost
@testable import LociStore

struct StartupTests {
  /// α1-S7: with the database deleted, everything comes back from the files.
  @Test func deletingTheDatabaseLosesNoContent() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let mentor = try await first.run(CreateMentor(request: "Scheduling"))
    let item = try await first.run(AddTextItem(fileName: "borg.md", text: "# Borg\n"))
    let lesson = LessonRef(mentor: mentor.id, lesson: Lesson.Slug("intro")!)
    try place.store.save(LessonText(front: try Lesson.Front(sources: [.item(item.id)]), body: ""), as: lesson)
    await first.close()
    try FileManager.default.removeItem(at: place.database)

    let second = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let health = second.subscribe(HealthReport())

    let ready = await value(health) { $0.database == .ready }
    #expect(ready != nil)
    #expect(try await second.run(ListMentors()) == [mentor])
    #expect(try await second.run(ListItems()) == [item])
    #expect(try await second.run(ItemCitations(item: item.id)).map(\.citation.lesson) == [lesson])
    await second.close()
  }

  @Test func theOldDatabaseServesWhileTheRebuildRuns() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let gate = AsyncStream.makeStream(of: Void.self)
    let host = await LocalHost.begin(
      store: place.store, database: try StoreDatabase.open(at: place.database), environment: world.environment,
      readingStateLost: false
    ) { store, database in
      for await _ in gate.stream { break }
      return try database.rebuild(from: store)
    }
    let health = host.subscribe(HealthReport())

    let rebuilding = await value(health) { $0.database == .rebuilding }
    #expect(rebuilding != nil)
    #expect(try await host.run(ListMentors()).isEmpty)
    gate.continuation.yield()
    let ready = await value(health) { $0.database == .ready }
    #expect(ready != nil)
    await host.close()
  }

  /// A change made after the rebuild read the files, but before it wrote the database, must not be lost:
  /// the rebuild writes what it read, and the change is applied after it.
  @Test func aChangeDuringTheRebuildIsAppliedAfterIt() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let mentor = try Mentor(
      id: world.nextID(), name: "Before", avatar: "ember", color: MentorColor.palette[0], provider: .pi)
    try place.store.create(mentor)
    let file = try place.store.mentorFolder(mentor.id).appending(path: "mentor.json")

    let host = await LocalHost.begin(
      store: place.store, database: try StoreDatabase.open(at: place.database), environment: world.environment,
      readingStateLost: false
    ) { store, database in
      let read = database.readMirrors(from: store)
      try place.edit(file) { $0.replacing("\"Before\"", with: "\"After\"") }
      try await Task.sleep(for: .seconds(1.5))
      try database.replaceMirrors(with: read.updates)
      return read.problems
    }
    let rebuilt = await value(host.subscribe(HealthReport()), within: .seconds(8)) { $0.database == .ready }
    #expect(rebuilt != nil)

    let mentors = host.subscribe(AllMentors())
    let caughtUp = await value(mentors) { $0.map(\.name) == ["After"] }
    #expect(caughtUp != nil)
    #expect(try await host.run(ListMentors()).map(\.name) == ["After"])
    await host.close()
  }

  @Test func aDamagedDatabaseIsReportedAndLeftAlone() async throws {
    let place = Place()
    defer { place.remove() }
    try FileManager.default.createDirectory(at: place.root, withIntermediateDirectories: true)
    let garbage = Data(repeating: 0x5A, count: 8192)
    try garbage.write(to: place.database)

    await #expect {
      try await LocalHost.start(root: place.root, database: place.database, environment: TestWorld().environment)
    } throws: { error in
      guard case HostStartError.databaseUnreadable = error else { return false }
      return true
    }
    #expect(try Data(contentsOf: place.database) == garbage)

    let host = try await LocalHost.startReplacingDatabase(
      root: place.root, database: place.database, environment: TestWorld().environment)
    let health = host.subscribe(HealthReport())
    let replaced = await value(health) { $0.readingStateLost && $0.database == .ready }
    #expect(replaced != nil)
    await host.close()
  }

  @Test func aDatabaseFromANewerLociIsReported() async throws {
    let place = Place()
    defer { place.remove() }
    _ = try StoreDatabase.open(at: place.database)
    try await DatabaseQueue(path: place.database.path(percentEncoded: false)).write { db in
      try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('9 conversations')")
    }

    await #expect(throws: HostStartError.databaseFromNewerVersion(unknownMigrations: ["9 conversations"])) {
      try await LocalHost.start(root: place.root, database: place.database, environment: TestWorld().environment)
    }
  }

  @Test func aBrokenFileShowsUpInHealthAndGoesAwayWhenFixed() async throws {
    try await withHost { host, place, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let health = host.subscribe(HealthReport())
      let page = host.subscribe(OneMentor(mentor: mentor.id))
      let catalog = try place.store.mentorFolder(mentor.id).appending(path: "catalog.yaml")

      try Data("chapters: [".utf8).write(to: catalog)

      let broken = await value(health) { !$0.fileProblems.isEmpty }
      #expect(broken?.fileProblems.map(\.subject) == [.mentor(mentor.id)])
      let catalogLost = await value(page) { $0.catalog == nil }
      #expect(catalogLost != nil)

      try Data("chapters: []\n".utf8).write(to: catalog)

      let healed = await value(health) { $0.fileProblems.isEmpty }
      #expect(healed != nil)
      let restored = await value(page) { $0.catalog != nil }
      #expect(restored != nil)
    }
  }

  @Test func aMentorFileThatIsNotJSONShowsUpInHealthAndGoesAwayWhenFixed() async throws {
    try await withHost { host, place, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let health = host.subscribe(HealthReport())
      let file = try place.store.mentorFolder(mentor.id).appending(path: "mentor.json")
      let original = try Data(contentsOf: file)

      try Data(#"{"id": "\#(mentor.id)", "name": "#.utf8).write(to: file)

      let broken = await value(health) { !$0.fileProblems.isEmpty }
      #expect(broken?.fileProblems.map(\.subject) == [.mentor(mentor.id)])
      #expect(broken?.fileProblems.first?.path.hasSuffix("/mentor.json") == true)
      await #expect(throws: HostError.self) { try await host.run(ReadCatalog(mentor: mentor.id)) }

      try original.write(to: file)

      let healed = await value(health) { $0.fileProblems.isEmpty }
      #expect(healed != nil)
      #expect(try await host.run(ListMentors()) == [mentor])
    }
  }
}
