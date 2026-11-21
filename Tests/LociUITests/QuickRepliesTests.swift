import Testing

@testable import LociUI

struct QuickRepliesTests {
  @Test func aReplyEndingInRepliesShowsItsWordsWithoutTheBlockAndOffersTheReplies() {
    let parsed = QuickReplies("要我存进资料库吗？\n\n```loci-replies\n好，存进去\n先不用\n```\n")

    #expect(parsed.text == "要我存进资料库吗？")
    #expect(parsed.replies == ["好，存进去", "先不用"])
  }

  @Test func atMostTwoRepliesAreOfferedAndBlankLinesAreSkipped() {
    let parsed = QuickReplies("好吗？\n```loci-replies\n\n一\n  二  \n三\n```")

    #expect(parsed.replies == ["一", "二"])
  }

  @Test func aReplyWithoutTheBlockIsLeftAsItIs() {
    let parsed = QuickReplies("就这样。\n\n```swift\nlet a = 1\n```")

    #expect(parsed.text == "就这样。\n\n```swift\nlet a = 1\n```")
    #expect(parsed.replies.isEmpty)
  }

  @Test func repliesStillBeingWrittenNeverShowAsCode() {
    #expect(QuickReplies("要吗？\n\n```loci-replies\n好").text == "要吗？")
    #expect(QuickReplies("要吗？\n\n```loci-replies\n好").replies == ["好"])
    #expect(QuickReplies("要吗？\n\n```loci-rep").text == "要吗？")
  }

  @Test func aBlockFollowedByMoreWordsIsNotReplies() {
    let reply = "看这个：\n\n```loci-replies\n一\n```\n\n然后呢。"

    #expect(QuickReplies(reply).text == reply)
    #expect(QuickReplies(reply).replies.isEmpty)
  }
}
