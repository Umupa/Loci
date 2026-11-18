import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

struct ChatTests {
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

  @Test func aCommandReadsWithoutTheShellThatRanIt() {
    #expect(ToolTitle.unwrapped("/bin/zsh -lc 'python3 cleanup.py'") == "python3 cleanup.py")
    #expect(ToolTitle.unwrapped("bash -c \"echo \\\"hi\\\"\"") == "echo \"hi\"")
    #expect(ToolTitle.unwrapped("/bin/zsh -lc 'echo '\\''x'\\'''") == "echo 'x'")
    #expect(ToolTitle.unwrapped("ls -a") == "ls -a")
    #expect(ToolTitle(Self.tool(.execute, "/bin/zsh -lc 'ls -a'")) == ToolTitle(Self.tool(.execute, "ls -a")))
  }

  @Test func aWebSearchReadsAsSearchingForItsQuery() {
    let title = ToolTitle(Self.tool(.search, "python str.strip", name: "webSearch"))

    #expect(title.action == .searched)
    #expect(title.object == "python str.strip")
  }

  @Test func fileToolsReadAsWhatTheyDidToWhichFile() {
    #expect(ToolTitle(Self.tool(.read, "/w/src/cleanup.py")).object == "cleanup.py")
    #expect(ToolTitle(Self.tool(.edit, "/w/cleanup.py", name: "fileChange")).action == .edited)
    #expect(ToolTitle(Self.tool(.create, "/w/cleanup.py", name: "fileChange")).action == .created)
    #expect(ToolTitle(Self.tool(.create, "/w/cleanup.py")).object == "cleanup.py")
  }

  @Test func aDeletedFileReadsAsDeletedAndIsCountedAsADeletion() {
    let deleted = Self.tool(.delete, "/w/qa_r2_file_event.txt", name: "fileChange")
    let tally = ToolTally([deleted, Self.tool(.create, "/w/qa_r2_file_event.txt")])

    #expect(ToolTitle(deleted).action == .deleted)
    #expect(ToolTitle(deleted).object == "qa_r2_file_event.txt")
    #expect(tally.deleted == 1)
    #expect(tally.edited == 0)
  }

  @Test func aCodeBlocksCopyButtonShowsOnlyWhileThePointerIsOverIt() {
    let block = CGRect(x: 0, y: 200, width: 360, height: 80)

    #expect(CodePointer.isOver(block, CGPoint(x: 340, y: 210)))
    #expect(!CodePointer.isOver(block, CGPoint(x: 340, y: 120)))
    #expect(!CodePointer.isOver(block, nil))
  }

  @Test func toolsInARowFoldIntoOneRowCountedByAction() {
    let entries = ConversationEntry.layout(
      [
        Self.asked, Self.message(1, .thinking("想")),
        Self.message(2, .tool(Self.tool(.execute, "ls"))), Self.message(3, .tool(Self.tool(.execute, "pwd"))),
        Self.message(4, .tool(Self.tool(.read, "a.md"))), Self.message(5, .reply("好")),
        Self.message(6, .tool(Self.tool(.read, "b.md"))),
      ], live: false)
    let cards = entries.compactMap { if case .steps(let steps) = $0 { StepsCard.segments(steps) } else { nil } }
    let folded = cards.first?.compactMap { if case .tools(let steps) = $0 { steps } else { nil } }.first
    let tools: [ToolActivity] = (folded ?? []).compactMap { step in
      if case .tool(let tool) = step.kind { tool } else { nil }
    }

    #expect(cards.map(\.count) == [2, 1])
    #expect(ToolTally(tools).ran == 2)
    #expect(ToolTally(tools).read == 1)
    #expect(ToolTally(tools).phrases.count == 2)
    if case .one = cards.last?.first {} else { Issue.record("a single tool is not folded") }
  }

  @Test func aFinishedAnswerIsCopiedWholeFromUnderItsLastReply() throws {
    let first = Self.message(2, .reply("一"))
    let last = Self.message(4, .reply("二"))
    let entries = ConversationEntry.layout(
      [Self.asked, first, Self.message(3, .tool(Self.tool(.read, "a.md"))), last], live: false)

    #expect(ConversationEntry.answers(entries) == [last.id: "一\n\n二"])
  }

  @Test func anAnswerStillStreamingCannotBeCopiedYet() {
    let entries = ConversationEntry.layout([Self.asked, Self.message(1, .reply("一"))], live: true)

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
    let entries = ConversationEntry.layout(
      [Self.asked, Self.message(1, .reply("一")), Self.message(2, .startedOver)], live: false)

    if case .aside(let line) = entries.last { #expect(line.body == .startedOver) } else { Issue.record() }
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
    var fit = SidebarFit()
    fit.fit(width: 890, reading: true)
    #expect(!fit.shows(true))

    fit.fit(width: 890, reading: false)
    #expect(fit.shows(true))

    fit.fit(width: 1200, reading: true)
    #expect(fit.shows(true))
  }

  @Test func theSidebarOpenedInANarrowWindowStaysUntilTheWindowWidens() {
    var fit = SidebarFit()
    fit.fit(width: 890, reading: true)

    let preferred = fit.toggle(true)
    #expect(preferred && fit.shows(preferred))

    let hidden = fit.toggle(preferred)
    #expect(hidden && !fit.shows(hidden))

    fit.fit(width: 1200, reading: true)
    #expect(fit.shows(hidden))
  }
}
