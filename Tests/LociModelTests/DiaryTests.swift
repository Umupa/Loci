import Testing

@testable import LociModel

struct DiaryTests {
  static let day = Day("2026-11-17")!

  @Test func theFirstLineGivesTheTimeAndTheTitle() {
    let diary = Diary(
      day: Self.day,
      parsing: "# 2026-11-17 23:48 — 你读到了一点十分\n\n第一段。\n\n第二段。\n\n## To remember\n- 先讲 fd 表\n- 少说去睡吧\n")

    #expect(diary.heading == Diary.Heading(day: Self.day, writtenAt: TimeOfDay("23:48"), title: "你读到了一点十分"))
    #expect(diary.body == "第一段。\n\n第二段。")
    #expect(diary.toRemember == ["先讲 fd 表", "少说去睡吧"])
  }

  @Test func everyPartOfTheFirstLineMayBeMissing() {
    #expect(Diary(day: Self.day, parsing: "# 调度器\nx").heading == .init(day: Self.day, writtenAt: nil, title: "调度器"))
    #expect(
      Diary(day: Self.day, parsing: "# 2026-11-17\nx").heading == .init(day: Self.day, writtenAt: nil, title: nil))
    #expect(Diary(day: Self.day, parsing: "# 8:05\nx").heading.writtenAt == TimeOfDay("08:05"))
  }

  @Test func theDayInTheFileNameWins() {
    #expect(Diary(day: Self.day, parsing: "# 2020-01-01 题目").heading.day == Self.day)
  }

  @Test func aDiaryWithoutAHeadingIsAllBody() {
    let diary = Diary(day: Self.day, parsing: "just words\n\nmore")

    #expect(diary.heading.title == nil)
    #expect(diary.body == "just words\n\nmore")
    #expect(diary.toRemember.isEmpty)
  }

  @Test func theListIsFoundUnderEitherLanguagesHeading() {
    #expect(Diary(day: Self.day, parsing: "# t\nbody\n### 要记住的\n- 一\nloose").toRemember == ["一", "loose"])
  }
}
