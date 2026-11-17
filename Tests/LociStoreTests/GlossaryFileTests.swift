import Foundation
import LociModel
import Testing

@testable import LociStore

struct GlossaryFileTests {
  @Test func aMentorWithoutAGlossaryHasAnEmptyOne() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)

      #expect(try store.glossary(of: mentor.id) == .empty)
    }
  }

  @Test func aGlossaryWrittenByTheMentorReadsBack() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)
      let folder = try store.folderName(ofMentor: mentor.id)
      try store.writeFile(
        "mentors/\(folder)/glossary.yaml",
        """
        terms:
        - term: watch
          aliases: [watches]
          definition: A client's subscription to changes of one kind of object.
          lesson: watch-and-list
        """)

      let glossary = try store.glossary(of: mentor.id)

      #expect(glossary.terms.map(\.term) == ["watch"])
      #expect(glossary.terms.first?.aliases == ["watches"])
      #expect(glossary.terms.first?.lesson == Lesson.Slug("watch-and-list"))
    }
  }

  @Test func aGlossaryThatCannotBeReadIsReportedAsTheMentorsProblem() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)
      let folder = try store.folderName(ofMentor: mentor.id)
      try store.writeFile("mentors/\(folder)/glossary.yaml", "terms:\n- term: watch\n")

      let loaded = store.loadMentor(mentor.id)

      #expect(loaded.value?.mentor == mentor)
      #expect(loaded.problems.map(\.path) == ["mentors/\(folder)/glossary.yaml"])
      #expect(loaded.problems.first?.subject == .mentor(mentor.id))
    }
  }
}

struct SeenLessonTests {
  @Test func onlyARevisionSinceTheLastLookGivesBackTheOldText() throws {
    let database = try StoreDatabase.inMemory()
    let lesson = LessonRef(mentor: Fixture.id(1), lesson: Fixture.slug("intro"))

    #expect(try database.see("第一版", of: lesson) == nil)
    #expect(try database.see("第一版", of: lesson) == nil)
    #expect(try database.see("第二版", of: lesson) == "第一版")
    #expect(try database.see("第二版", of: lesson) == nil)
    #expect(try database.readingRecord(of: Fixture.id(1)).seen == [Fixture.slug("intro"): "第二版"])
  }
}
