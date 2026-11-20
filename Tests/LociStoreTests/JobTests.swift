import Foundation
import GRDB
import LociModel
import Testing

@testable import LociStore

struct JobTests {
  @Test func whereAJobStandsSurvivesReopeningTheDatabase() throws {
    try DatabaseOpenTests.withFolder { folder in
      let url = folder.appending(path: "loci.sqlite")
      let waiting = Job(item: Fixture.id(2), stage: .transcribe, state: .waiting(.speechModel(.base)))
      let failed = Job(
        item: Fixture.id(3), stage: .resolve,
        state: .failed(.init(reason: "Sign in to confirm", remedy: .chooseBrowserLogin)))
      do {
        let database = try StoreDatabase.open(at: url)
        try database.save(waiting, at: Fixture.instant)
        try database.save(failed, at: Fixture.instant)
        try database.save(
          Job(item: Fixture.id(2), stage: .transcribe, state: .paused(progress: Fraction(0.41))), at: Fixture.instant)
      }

      let reopened = try StoreDatabase.open(at: url)

      #expect(try reopened.job(of: Fixture.id(2))?.state == .paused(progress: Fraction(0.41)))
      #expect(try reopened.jobs().count == 2)
      try reopened.deleteJob(of: Fixture.id(3))
      #expect(try reopened.job(of: Fixture.id(3)) == nil)
    }
  }

  @Test func aJobStoppedBeforeThisVersionReadsAsPaused() throws {
    try DatabaseOpenTests.withFolder { folder in
      let url = folder.appending(path: "loci.sqlite")
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = try DatabaseQueue(path: url.path(percentEncoded: false))
        try Schema.migrator.migrate(old, upTo: "6 loci")
        try old.write { db in
          try db.execute(
            sql: "INSERT INTO job (item_id, stage, state, updated_at) VALUES (?, 'download', ?, ?)",
            arguments: [Fixture.id(2).description, #"{"stopped":{}}"#, Fixture.instant.description])
        }
      }

      let reopened = try StoreDatabase.open(at: url)

      #expect(try reopened.job(of: Fixture.id(2))?.state == .paused(progress: nil))
    }
  }

  @Test func mediaChoicesAreKeptInTheSettings() throws {
    try withStore { store in
      try store.changeSettings {
        $0.speechModel = .base
        $0.browserLogin = .safari
      }

      let settings = try store.settings()
      #expect(settings.speechModel == .base)
      #expect(settings.browserLogin == .safari)
      #expect(try store.readFile("settings.json").contains("\"browserLogin\" : \"safari\""))
    }
  }
}
