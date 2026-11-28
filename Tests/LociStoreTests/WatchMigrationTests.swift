import Foundation
import GRDB
import LociModel
import Testing

@testable import LociStore

struct WatchMigrationTests {
  @Test func aWatchMigrationKeepsThePersonsTextAndImportsLegacyPreferencesOnlyOnce() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = Store(root: root, discard: Discard { _ in })
    let database = try StoreDatabase.inMemory()
    let files = store.home(.chat)
    try files.prepare()
    try files.saveWatch("# Watch\nKeep policy news.\n")
    let panel = files.panelsFolderURL.appending(path: "flash.json")
    try store.write(Data(#"{"feed":{"source":"news","skip":["龙虎榜","喊单"]},"future":"keep me"}"#.utf8), to: panel)
    let body = #"{"field":"prem.513870.premium","comparison":"<","threshold":0.03,"say":"溢价低了","ask":"看看吗"}"#
    try database.queue.write { db in
      try db.execute(
        sql: "INSERT INTO next_up_condition (id, home, source, body) VALUES (?, ?, ?, ?)",
        arguments: [Fixture.id(12).description, "chat", "home/prem", body])
    }

    try store.migrateWatch(in: database)
    let migrated = try files.watch()
    try store.migrateWatch(in: database)

    #expect(migrated == (try files.watch()))
    #expect(migrated.contains("Keep policy news."))
    #expect(migrated.contains("prem.513870.premium < 0.03"))
    #expect(migrated.components(separatedBy: "龙虎榜").count == 2)
    #expect(migrated.contains("喊单"))
    #expect(try store.readText(panel).contains("keep me"))
    #expect(try !store.readText(panel).contains("skip"))
    #expect(try database.queue.read { try !$0.tableExists("next_up_condition") })
  }
}
