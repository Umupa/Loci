import Foundation
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
        try database.save(Job(item: Fixture.id(2), stage: .transcribe, state: .stopped), at: Fixture.instant)
      }

      let reopened = try StoreDatabase.open(at: url)

      #expect(try reopened.job(of: Fixture.id(2))?.state == .stopped)
      #expect(try reopened.jobs().count == 2)
      try reopened.deleteJob(of: Fixture.id(3))
      #expect(try reopened.job(of: Fixture.id(3)) == nil)
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
