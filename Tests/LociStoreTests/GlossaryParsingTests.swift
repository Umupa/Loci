import LociModel
import Testing

@testable import LociStore

struct GlossaryParsingTests {
  @Test(arguments: [
    "terms: [",
    "terms:\n- term: node\n  definition: machine\n- term: Node\n  definition: duplicate\n",
    "terms:\n- term: node\n  aliases: [Node]\n  definition: duplicate\n",
    "terms:\n- term: node\n  definition: machine\n  lesson: ../escape\n",
    "terms:\n- term: node\n  aliases: [{nested: value}]\n  definition: machine\n",
    "terms:\n- term: node\n  definition: |\n    first line\n    second line\n",
  ])
  func anInvalidGlossaryIsReportedWithoutHidingTheMentor(_ text: String) throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)
      let folder = try store.folderName(ofMentor: mentor.id)
      let path = "mentors/\(folder)/glossary.yaml"
      try store.writeFile(path, text)

      #expect(throws: (any Error).self) { try store.glossary(of: mentor.id) }
      let loaded = store.loadMentor(mentor.id)
      #expect(loaded.value?.mentor == mentor)
      #expect(loaded.problems.map(\.path) == [path])
      #expect(loaded.problems.map(\.subject) == [.mentor(mentor.id)])
    }
  }

  @Test func optionalGlossaryFieldsDefaultAndUnicodeTextIsTrimmed() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)
      let folder = try store.folderName(ofMentor: mentor.id)
      try store.writeFile("mentors/\(folder)/glossary.yaml", "terms:\n- term: ' 节点 '\n  definition: ' 一台机器。 '\n")
      let term = try #require(store.glossary(of: mentor.id).terms.first)
      #expect(term.term == "节点")
      #expect(term.definition == "一台机器。")
      #expect(term.aliases.isEmpty)
      #expect(term.lesson == nil)
    }
  }
}
