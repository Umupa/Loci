import Foundation
import LociModel
import Testing

@testable import LociStore

struct TextBookTests {
  static func gb18030(_ text: String) -> Data {
    let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    return text.data(using: String.Encoding(rawValue: encoding))!
  }

  @Test func aGB18030NovelIsCutIntoChaptersAtItsHeadings() throws {
    let text = """
      　　楔子的一段話。
      第一章　風雪山神廟
      　　林沖踏着那瑞雪。
      　　迎着北風。
      第二回 智取生辰綱
      　　楊志押送金銀擔。
      """
    let book = try TextBook(Self.gb18030(text), title: "水滸")

    #expect(book.chapters.map(\.title) == ["水滸", "第一章　風雪山神廟", "第二回 智取生辰綱"])
    #expect(book.chapters[1].paragraphs == ["林沖踏着那瑞雪。", "迎着北風。"])
    #expect(book.language == "zh")
  }

  @Test func linesThatOnlyWrapAParagraphAreJoinedBack() throws {
    let wrapped = """
      CHAPTER I

      It was the best of times, it was the worst
      of times, it was the age of wisdom.

      There were a king with a large jaw
      and a queen with a plain face.
      """
    let book = try TextBook(Data(wrapped.utf8), title: "Two Cities")

    #expect(book.chapters.map(\.title) == ["CHAPTER I"])
    #expect(
      book.chapters[0].paragraphs == [
        "It was the best of times, it was the worst of times, it was the age of wisdom.",
        "There were a king with a large jaw and a queen with a plain face.",
      ])
    #expect(book.language == nil)
  }

  @Test func chineseLinesAreJoinedWithoutASpaceAndIndentedLinesStartParagraphs() throws {
    let wrapped = """
      第一章
      　　我從鄉下跑到京城裏，
      一轉眼已經六年了。
      其間耳聞目睹的所謂國家大事，
      算起來也很不少。
      　　但在我心裏，都不留什麼痕跡，
      倘要我尋出這些事的影響來說，
      便只是增長了我的壞脾氣。
      """
    let book = try TextBook(Data(wrapped.utf8), title: "一件小事")

    #expect(
      book.chapters[0].paragraphs == [
        "我從鄉下跑到京城裏，一轉眼已經六年了。其間耳聞目睹的所謂國家大事，算起來也很不少。",
        "但在我心裏，都不留什麼痕跡，倘要我尋出這些事的影響來說，便只是增長了我的壞脾氣。",
      ])
  }

  @Test func textWithoutHeadingsIsCutIntoNumberedParts() throws {
    let paragraph = String(repeating: "字", count: 900)
    let text = Array(repeating: paragraph, count: 50).joined(separator: "\n")
    let book = try TextBook(Data(text.utf8), title: "長文")

    #expect(book.chapters.count == 3)
    #expect(book.chapters.map(\.title) == ["1", "2", "3"])
    #expect(book.chapters.flatMap(\.paragraphs).count == 50)
  }

  @Test func aChapterPageIsWellFormedXHTMLWithItsTextEscaped() throws {
    let book = try TextBook(Data("第一章 <開始>\n甲 & 乙 < 丙".utf8), title: "x")
    let page = book.page(0)

    #expect(XMLTree.parse(page) != nil)
    #expect(String(decoding: page, as: UTF8.self).contains("<p>甲 &amp; 乙 &lt; 丙</p>"))
    #expect(book.contents.chapters.map(\.path) == ["chapter-0.xhtml"])
    #expect(TextBook.chapter(in: "chapter-0.xhtml") == 0)
    #expect(TextBook.chapter(in: "../chapter-0.xhtml") == nil)
  }

  @Test func emptyOrUndecodableTextIsNotABook() {
    #expect(throws: BookProblem.notABook) { try TextBook(Data(" \n\n ".utf8), title: "x") }
  }
}
