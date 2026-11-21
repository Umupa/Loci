import Foundation
import LociModel
import Testing

@testable import LociUI

/// C-S3, C-S5, C-S6: what of a reply becomes a document card or a link card, and what stays in the bubbles.
struct ReplyCardsTests {
  private static let kata = URL(string: "https://github.com/kata-containers/kata-containers")!
  private static let e2b = URL(string: "https://github.com/e2b-dev/infra")!

  @Test func aDocumentBlockBecomesADocumentWithItsTitleAndBody() {
    let bubble = """
      ```loci-doc
      # jailer 隔离了什么

      | | 没有 jailer | 有 jailer |
      |---|---|---|
      | 文件 | 宿主整个根目录 | chroot |
      ```
      """

    let pieces = ReplyPiece.pieces(in: bubble)

    #expect(
      pieces == [
        .document(
          LociDocument(
            title: "jailer 隔离了什么", body: "| | 没有 jailer | 有 jailer |\n|---|---|---|\n| 文件 | 宿主整个根目录 | chroot |"))
      ])
  }

  @Test func aDocumentFencedWithFourBackticksKeepsTheCodeInside() {
    let pieces = ReplyPiece.pieces(in: "````loci-doc\n# 启动\n\n```sh\njailer --id vm-42\n```\n````")

    #expect(pieces == [.document(LociDocument(title: "启动", body: "```sh\njailer --id vm-42\n```"))])
  }

  @Test func aDocumentStillBeingWrittenIsADocumentAlready() {
    let pieces = ReplyPiece.pieces(in: "就是这样：\n```loci-doc\n# 标题\n\n第一段")

    #expect(pieces == [.words("就是这样："), .document(LociDocument(title: "标题", body: "第一段"))])
  }

  @Test func aLinkOnALineOfItsOwnBecomesALinkAndTheWordsAroundItStay() {
    let pieces = ReplyPiece.pieces(
      in: "挑了两个：\n\(Self.kata.absoluteString)\n[e2b](\(Self.e2b.absoluteString))\n都是 microVM。")

    #expect(pieces == [.words("挑了两个："), .links([Self.kata, Self.e2b]), .words("都是 microVM。")])
  }

  @Test func aLinkInsideASentenceOrACodeBlockStaysInTheWords() {
    let sentence = "看 \(Self.kata.absoluteString) 这个"
    let code = "```\n\(Self.kata.absoluteString)\n```"

    #expect(ReplyPiece.pieces(in: sentence) == [.words(sentence)])
    #expect(ReplyPiece.pieces(in: code) == [.words(code)])
    #expect(ReplyPiece.pieces(in: "[两个](\(Self.kata.absoluteString)) 和 [另一个](\(Self.e2b.absoluteString))").count == 1)
  }

  @Test func aReplyWithADocumentIsABubbleAndThenACard() {
    let reply = "一句结论。\n\n```loci-doc\n# 对照\n\n正文\n```"
    let rows = TalkRow.rows(
      ConversationEntry.layout([.message(Self.message(1, .reply(reply)))], live: false))

    #expect(rows.count == 3)
    guard case .said(let words, let answer) = rows[1].kind, case .document(let document) = rows[2].kind else {
      Issue.record("expected a bubble then a document, got \(rows.map(\.kind))")
      return
    }
    #expect(words == "一句结论。")
    #expect(answer == reply)
    #expect(document.title == "对照")
  }

  @Test func linksThatOnlyBlankLinesKeepApartMakeOneStack() {
    let reply = "挑了两个。\n\n\(Self.kata.absoluteString)\n\n\(Self.e2b.absoluteString)"
    let rows = TalkRow.rows(ConversationEntry.layout([.message(Self.message(1, .reply(reply)))], live: false))

    guard case .links(let links) = rows.last?.kind else {
      Issue.record("expected links last, got \(rows.map(\.kind))")
      return
    }
    #expect(links == [Self.kata, Self.e2b])
    #expect(rows.count == 3)
  }

  private static func message(_ second: Int64, _ body: Message.Body) -> Message {
    Message(id: EntityID(), at: Timestamp(millisecondsSince1970: second * 1000), body: body)
  }

  @Test func aClickAnywhereButOnACardGathersASpreadStack() {
    let cards = [CGRect(x: 0, y: 0, width: 248, height: 200), CGRect(x: 264, y: 0, width: 248, height: 200)]

    #expect(StackSpread.gathers(click: CGPoint(x: 600, y: 100), cards: cards))
    #expect(StackSpread.gathers(click: CGPoint(x: 256, y: 100), cards: cards))
    #expect(StackSpread.gathers(click: CGPoint(x: 100, y: 400), cards: cards))
    #expect(!StackSpread.gathers(click: CGPoint(x: 300, y: 50), cards: cards))
  }

  @Test func aClickOnTheInputFieldOverACardScrolledUnderItGathersTheStack() {
    let cards = [CGRect(x: 0, y: 300, width: 248, height: 200)]
    let field = CGRect(x: 0, y: 440, width: 512, height: 100)

    #expect(StackSpread.gathers(click: CGPoint(x: 100, y: 460), cards: cards, covered: field))
    #expect(!StackSpread.gathers(click: CGPoint(x: 100, y: 400), cards: cards, covered: field))
  }
}
