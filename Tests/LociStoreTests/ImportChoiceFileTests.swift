import Foundation
import LociModel
import Testing

@testable import LociStore

struct ImportChoiceFileTests {
  @Test func anItemTakenInBeforeChoicesWereKeptHasNone() throws {
    try withStore { store in
      let item = try MediaFilesTests.video()
      try store.addPending(item)

      #expect(try store.importChoice(of: item.id) == nil)
    }
  }

  @Test func theChoiceAnItemWasTakenInWithIsKeptBesideIt() throws {
    try withStore { store in
      let item = try MediaFilesTests.video()
      try store.addPending(item)
      let choice = ImportChoice(
        keeping: .online, quality: .hd1080, siteSubtitles: true, recognition: nil, translation: nil)

      try store.saveImportChoice(choice, of: item.id)

      #expect(try store.importChoice(of: item.id) == choice)
    }
  }

  @Test func aChoiceThatCannotBeReadCountsAsNone() throws {
    try withStore { store in
      let item = try MediaFilesTests.video()
      try store.addPending(item)
      try Data("{".utf8).write(to: try store.itemFolder(item.id).appending(path: "import.json"))

      #expect(try store.importChoice(of: item.id) == nil)
    }
  }

  @Test func theLastChoiceIsASetting() throws {
    try withStore { store in
      let choice = ImportChoice.first(readerLanguage: "en", speechModel: .base)

      try store.changeSettings { $0.importChoice = choice }

      #expect(try store.settings().importChoice == choice)
    }
  }
}
