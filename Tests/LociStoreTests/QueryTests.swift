import Foundation
import LociModel
import Testing

@testable import LociStore

struct QueryTests {
  @Test func aLessonsCitationsComeInTheOrderItMakesThem() throws {
    try withStore { store in
      let library = try Library(store: store)
      let database = try StoreDatabase.inMemory()
      try database.rebuild(from: store)

      #expect(
        try database.citations(in: library.firstLesson) == [
          Citation(lesson: library.firstLesson, item: library.article.id, anchor: nil),
          Citation(
            lesson: library.firstLesson, item: library.article.id,
            anchor: .quote(try TextQuote("feasibility checking"))),
          Citation(
            lesson: library.firstLesson, item: library.video.id,
            anchor: .time(try TimeSpan(start: .seconds(60), end: .seconds(90)))),
        ])
    }
  }

  @Test func anItemShowsEveryLessonThatCitesItAcrossMentors() throws {
    try withStore { store in
      let library = try Library(store: store)
      let database = try StoreDatabase.inMemory()
      try database.rebuild(from: store)

      #expect(
        Set(try database.citations(of: library.article.id).map(\.lesson)) == [
          library.firstLesson, library.secondLesson,
        ])
      #expect(try database.citations(of: library.video.id).map(\.lesson) == [library.firstLesson])
      #expect(try database.citations(of: Fixture.id(99)).isEmpty)
    }
  }

  @Test func notesAreFoundByTheirContent() throws {
    try withStore { store in
      let library = try Library(store: store)
      let database = try StoreDatabase.inMemory()
      try database.rebuild(from: store)

      #expect(try database.notes(on: .item(library.article.id)) == [library.note])
      #expect(try database.notes(on: .lesson(library.firstLesson)).isEmpty)
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

  @Test func aPositionInOtherContentIsRefused() throws {
    let database = try StoreDatabase.inMemory()
    let elsewhere = Locator("loci://library/\(Fixture.id(4))#t=1")!

    #expect(throws: StoreDatabaseError.misplacedPosition(elsewhere)) {
      try database.save(
        ReadingState(position: elsewhere, finished: false, updatedAt: Fixture.instant), for: .item(Fixture.id(3)))
    }
  }
}
