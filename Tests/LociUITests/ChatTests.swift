import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

struct ChatTests {
  private static func layout(_ messages: [Message], live: Bool) -> [ConversationEntry] {
    ConversationEntry.layout(messages.map { .message($0) }, live: live)
  }

  private static func message(_ second: Int64, _ body: Message.Body) -> Message {
    Message(id: EntityID(), at: Timestamp(millisecondsSince1970: second * 1000), body: body)
  }

  private static func tool(_ kind: ToolActivity.Kind, _ subject: String?, name: String = "tool") -> ToolActivity {
    ToolActivity(id: UUID().uuidString, name: name, kind: kind, subject: subject, output: "", state: .succeeded)
  }

  private static let asked = message(0, .prompt(Prompt(text: "演示一下", purpose: .chat)))

  @Test func aDisplayFormulaOnOneLineIsTypesetAsABlock() {
    let reply = "行内 $x^2$。\n$$ \\sum_{i=1}^{n}i=\\frac{n(n+1)}{2} $$\n下一段"

    #expect(
      DisplayMath.fenced(reply)
        == "行内 $x^2$。\n\n```math\n\\sum_{i=1}^{n}i=\\frac{n(n+1)}{2}\n```\n\n下一段")
  }

  @Test func aDisplayFormulaAcrossLinesOrInBracketsIsTypesetAsABlock() {
    #expect(DisplayMath.fenced("$$\na+b\n$$") == "\n```math\na+b\n```\n")
    #expect(DisplayMath.fenced("\\[\n  E = mc^2\n\\]") == "\n```math\nE = mc^2\n```\n")
  }

  @Test func dollarsInsideCodeAndInlineFormulasAreLeftAsTheyAre() {
    let code = "```sh\n$$ echo $HOME $$\n```"
    #expect(DisplayMath.fenced(code) == code)
    #expect(DisplayMath.fenced("价格 $5 到 $6") == "价格 $5 到 $6")
  }

  @Test func activityDotsMoveAcrossBothAxesInsideOneIconSlot() {
    let initial = ActivityDots.spots(at: 0)
    let later = ActivityDots.spots(at: 0.4)
    let bounds = CGRect(origin: .zero, size: ActivityDots.size)

    #expect(initial.count == 3)
    #expect(Set(initial.map(\.midY)).count == 3)
    #expect(zip(initial, later).allSatisfy { $0.midX != $1.midX && $0.midY != $1.midY })
    #expect((initial + later).allSatisfy { bounds.contains($0) })
  }

  @Test func aCodeBlocksCopyButtonShowsOnlyWhileThePointerIsOverIt() {
    let block = CGRect(x: 0, y: 200, width: 360, height: 80)

    #expect(CodePointer.isOver(block, CGPoint(x: 340, y: 210)))
    #expect(!CodePointer.isOver(block, CGPoint(x: 340, y: 120)))
    #expect(!CodePointer.isOver(block, nil))
  }

  @Test func aFinishedAnswerIsCopiedWithoutTheRepliesItOffers() {
    let offer = Self.message(2, .reply("要我存进去吗？\n\n```loci-replies\n好\n```"))

    #expect(ConversationEntry.answers(Self.layout([Self.asked, offer], live: false)) == [offer.id: "要我存进去吗？"])
  }

  @Test func aFinishedAnswerIsCopiedAsItsLastReplyAlone() throws {
    let first = Self.message(2, .reply("我先看看。"))
    let last = Self.message(4, .reply("二"))
    let entries = Self.layout(
      [Self.asked, first, Self.message(3, .tool(Self.tool(.read, "a.md"))), last], live: false)

    #expect(ConversationEntry.answers(entries) == [last.id: "二"])
  }

  @Test func anAnswerStillStreamingCannotBeCopiedYet() {
    let entries = Self.layout([Self.asked, Self.message(1, .reply("一"))], live: true)

    #expect(ConversationEntry.answers(entries).isEmpty)
  }

  @Test func shiftReturnMakesANewLineAndCommandReturnSends() {
    #expect(ComposerKey([.shift]) == .newLine)
    #expect(ComposerKey([.command]) == .send)
    #expect(ComposerKey([]) == .field)
  }

  @Test func aNewLineGoesWhereTheCaretIs() {
    let text = "第一行第二行"
    let caret = text.index(text.startIndex, offsetBy: 3)
    let (changed, selection) = ComposerKey.newLine(in: text, at: TextSelection(insertionPoint: caret))

    #expect(changed == "第一行\n第二行")
    #expect(selection == TextSelection(insertionPoint: changed.index(changed.startIndex, offsetBy: 4)))
    #expect(ComposerKey.newLine(in: "末尾", at: nil).0 == "末尾\n")
  }

  @Test func slashNewOnItsOwnStartsOver() {
    #expect(ComposerKey.isStartOver("/new"))
    #expect(ComposerKey.isStartOver(" /NEW \n"))
    #expect(!ComposerKey.isStartOver("/new topic"))
  }

  @Test func startingOverShowsAsALineBetweenTheMessages() {
    let entries = Self.layout(
      [Self.asked, Self.message(1, .reply("一")), Self.message(2, .startedOver)], live: false)

    #expect(TalkRow.rows(entries).last.map { if case .startedOver = $0.kind { true } else { false } } == true)
  }

  @Test func scrollingUpStopsFollowingAndOffersTheWayBack() {
    var follow = Following()
    #expect(!follow.offersLatest)

    follow.scrolled(to: 600)
    #expect(follow.offersLatest)

    follow.returned()
    #expect(follow.isOn)
  }

  @Test func askingOrScrollingBackToTheEndFollowsAgain() {
    var follow = Following()
    follow.scrolled(to: 600)
    follow.asked()
    #expect(follow.isOn)

    follow.scrolled(to: 600)
    follow.scrolled(to: 10)
    #expect(follow.isOn)
  }

  @Test func aNarrowWindowGivesTheSidebarsRoomToTheConversation() {
    var fit = PaneFit.sidebar
    fit.fit(width: 890, crowded: true)
    #expect(!fit.shows(true))

    fit.fit(width: 890, crowded: false)
    #expect(fit.shows(true))

    fit.fit(width: 1200, crowded: true)
    #expect(fit.shows(true))
  }

  @Test func theSidebarOpenedInANarrowWindowStaysUntilTheWindowWidens() {
    var fit = PaneFit.sidebar
    fit.fit(width: 890, crowded: true)

    let preferred = fit.toggle(true)
    #expect(preferred && fit.shows(preferred))

    let hidden = fit.toggle(preferred)
    #expect(hidden && !fit.shows(hidden))

    fit.fit(width: 1200, crowded: true)
    #expect(fit.shows(hidden))
  }
}
