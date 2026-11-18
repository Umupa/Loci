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
    let item = try await first.run(AddTextItem(fileName: "borg.md", text: "# Borg\n\nfeasibility\n"))
    let note = try await first.run(
      AddNote(locator: .item(item.id, .quote(try TextQuote("feasibility"))), excerpt: "feasibility"))
    await first.close()
    try FileManager.default.removeItem(at: place.database)

    let second = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let health = second.subscribe(HealthReport())

    let ready = await value(health) { $0.database == .ready }
    #expect(ready != nil)
    #expect(try await second.run(ListItems()) == [item])
    #expect(
      try await second.run(Search(text: "feasibility")).map(\.target).contains(.note(note.id, on: .item(item.id))))
    await second.close()
  }

  @Test func theOldDatabaseServesWhileTheRebuildRuns() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let gate = AsyncStream.makeStream(of: Void.self)
    let host = try await LocalHost.begin(
      store: place.store, database: try StoreDatabase.open(at: place.database), environment: world.environment,
      readingStateLost: false
    ) { store, database in
      for await _ in gate.stream { break }
      return try database.rebuild(from: store)
    }
    let health = host.subscribe(HealthReport())

    let rebuilding = await value(health) { $0.database == .rebuilding }
    #expect(rebuilding != nil)
    #expect(try await host.run(ListItems()).isEmpty)
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
    let item = try Item(id: world.nextID(), kind: .article, title: "Before")
    try place.store.add(item, content: "text")
    let file = try place.store.itemFolder(item.id).appending(path: "item.json")

    let host = try await LocalHost.begin(
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

    let items = host.subscribe(AllItems())
    let caughtUp = await value(items) { $0.map(\.title) == ["After"] }
    #expect(caughtUp != nil)
    #expect(try await host.run(ListItems()).map(\.title) == ["After"])
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
      let item = try await host.run(AddTextItem(fileName: "borg.md", text: "# Borg\n"))
      let health = host.subscribe(HealthReport())
      let file = try place.store.itemFolder(item.id).appending(path: "item.json")
      let original = try Data(contentsOf: file)

      try Data(#"{"id": "\#(item.id)", "title": "#.utf8).write(to: file)

      let broken = await value(health) { !$0.fileProblems.isEmpty }
      #expect(broken?.fileProblems.map(\.subject) == [.item(item.id)])
      #expect(broken?.fileProblems.first?.path.hasSuffix("/item.json") == true)

      try original.write(to: file)

      let healed = await value(health) { $0.fileProblems.isEmpty }
      #expect(healed != nil)
      #expect(try await host.run(ListItems()) == [item])
    }
  }
}
