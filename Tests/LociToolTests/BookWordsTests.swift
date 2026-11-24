import Foundation
import LociModel
import Testing

@testable import LociTool

/// BK-S13: the companion sees a book's title and authors, and that it is a book.
struct BookWordsTests {
  @Test func aBookIsDescribedByItsTitleAuthorsAndKind() throws {
    var entropy = SystemRandomNumberGenerator()
    let id = EntityID(at: Date(timeIntervalSince1970: 1_763_337_600), entropy: &entropy)
    let book = try Item(id: id, kind: .book, title: "吶喊", authors: ["魯迅"])

    let words = Words.item(book, job: nil, folder: "../library/nahan/")

    #expect(words.hasPrefix("吶喊\nid: \(id)\nkind: book\nauthors: 魯迅\n"))
  }
}
