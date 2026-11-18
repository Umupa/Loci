import Foundation
import LociModel
import Testing

@testable import LociStore

struct QueryTests {
  @Test func notesAreFoundByTheirContent() throws {
    try withStore { store in
      let library = try Library(store: store)
      let database = try StoreDatabase.inMemory()
      try database.rebuild(from: store)

      #expect(try database.notes(on: .item(library.article.id)) == [library.note])
      #expect(try database.notes(on: .item(library.video.id)).isEmpty)
    }
  }

  @Test func readingStateIsRememberedPerContent() throws {
    let database = try StoreDatabase.inMemory()
    let content = ContentRef.item(Fixture.id(3))
    let state = ReadingState(
      position: Locator("loci://library/\(Fixture.id(3))#quote=feasibility")!, finished: false,
      updatedAt: Fixture.instant)
    let finished = ReadingState(position: nil, finished: true, updatedAt: Fixture.instant)

    #expect(try database.readingState(of: content) == nil)
    try database.save(state, for: content)
    #expect(try database.readingState(of: content) == state)
    try database.save(finished, for: content)
    #expect(try database.readingState(of: content) == finished)
  }

  @Test func theLatestReadingIsTheOneUpdatedLast() throws {
    let database = try StoreDatabase.inMemory()
    let later = Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + 1)
    try database.save(ReadingState(position: nil, finished: false, updatedAt: later), for: .item(Fixture.id(4)))
    try database.save(
      ReadingState(position: nil, finished: true, updatedAt: Fixture.instant), for: .item(Fixture.id(3)))

    #expect(try database.latestReading()?.content == .item(Fixture.id(4)))
    #expect(try database.latestReading()?.at == later)
  }

  @Test func aPositionInOtherContentIsRefused() throws {
    let database = try StoreDatabase.inMemory()
    let elsewhere = Locator("loci://library/\(Fixture.id(4))#t=1")!

    #expect(throws: StoreDatabaseError.misplacedPosition(elsewhere)) {
      try database.save(
        ReadingState(position: elsewhere, finished: false, updatedAt: Fixture.instant), for: .item(Fixture.id(3)))
    }
  }
}
