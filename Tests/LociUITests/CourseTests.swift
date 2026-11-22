import AppKit
import Foundation
import LociModel
import Testing

@testable import LociUI

@MainActor
struct CourseTests {
  @Test func aTitleIsAlwaysBoundTheSameWay() {
    #expect(BookDesign(title: "Raft") == BookDesign(title: "Raft"))
    #expect(BookDesign.fnv1a("") == 0xcbf2_9ce4_8422_2325)
  }

  @Test func titlesAreSpreadOverEveryDrawingAndCloth() {
    let designs = CourseSamples.motifTitles.map(BookDesign.init(title:))
    #expect(Set(designs.map { String(describing: $0.motif.family) }).count == BookMotif.Family.allCases.count)
    #expect(Set(designs.map(\.cloth)).count == Palette.Cloth.all.count)
  }

  @Test func aCitationIsNumberedByTheSourceItPointsInto() throws {
    let sources = ReadingSamples.sources.compactMap(\.url)
    func number(_ link: String) throws -> Int? {
      LessonFacts.citation(of: try #require(URL(string: link)), in: sources)
    }
    #expect(try number("https://raft.github.io/raft.pdf#page=4") == 1)
    #expect(try number("https://github.com/etcd-io/raft/blob/4abf9f2/raft.go#L560-L590") == 4)
    #expect(try number("https://etcd.io/docs/v3.5/learning/api_guarantees/#:~:text=linearizable") == 5)
    #expect(try number("https://example.com/elsewhere") == nil)
  }

  @Test func theCourseBeingReadIsWhereTheWindowReopens() {
    let course = EntityID()
    #expect(WindowState(restoring: WindowState(place: .courses(course)).text).place == .courses(course))
    #expect(WindowState(restoring: WindowState(place: .courses(nil)).text).place == .courses(nil))
  }

  @Test func anAnswerFliesToTheLineItsQuestionFills() throws {
    #expect(try BuilderSamples.goal(0).line(answering: try BuilderSamples.known().draft) == 2)
    let open = try BuilderSamples.question("讲到多深？", [("原理", "讲清取舍"), ("代码", "指到行")])
    #expect(try BuilderSamples.goal(2).line(answering: open.draft) == 2)
    #expect(try BuilderSamples.goal(5).line(answering: open.draft) == nil)
  }

  @Test func theBuilderShowsWhatLociIsWritingAsItArrives() throws {
    let courses = try SampleCourses()
    let draft =
      "# 随机超时打破平票\n\n两个候选人同时超时，[论文](https://raft.github.io/raft.pdf#page=6)说**随机**一点就好。\n\n```go\nfor {}\n```\n\n> 打破对称。"
    let page = CoursePage(
      course: courses.raft, lessons: courses.page.lessons,
      activity: .writing(lesson: BuilderSamples.lessonIDs[3], draft: draft))
    let shown = BuilderShown(page, minutes: [BuilderSamples.lessonIDs[0]: 8], shownLesson: nil)
    #expect(shown.working)
    #expect(
      shown.leaf == Leaf(number: 4, title: "随机超时打破平票", paragraphs: ["两个候选人同时超时，论文说随机一点就好。", "打破对称。"], writing: true))
    #expect(shown.lessons[0].state == .written(minutes: 8))
    #expect(shown.lessons[1].state == .written(minutes: nil))
    #expect(shown.lessons[3].state == .writing)
    #expect(shown.lessons[4].state == .planned)
    #expect(shown.canGoOn)
  }

  @Test func aBookShowsItsStagesUntilItsFirstLessonIsWrittenAndWhileLociWorks() {
    func book(_ stage: CourseStage, written: Int, working: Bool) -> CourseBook {
      CourseBook(
        CourseSummary(
          id: EntityID(), title: "Raft", subtitle: nil, stage: stage, lessonCount: 10, writtenCount: written,
          readCount: 2, isWorking: working))
    }
    #expect(book(.goal, written: 0, working: false).building?.fraction == nil)
    #expect(book(.writing, written: 0, working: false).building != nil)
    #expect(book(.writing, written: 4, working: false).building == nil)
    #expect(book(.writing, written: 4, working: true).building?.fraction == 0.4)
    #expect(book(.writing, written: 4, working: false).read == 0.2)
  }

  @Test func aCourseOpensAtTheFirstLessonNotReadYet() throws {
    #expect(ReadingCourse.opening(try SampleCourses().page) == BuilderSamples.lessonIDs[1])
  }

  @Test func paragraphsArrivingTogetherComeIntoViewOneAfterAnother() {
    let start = ContinuousClock.now
    let beat = ParagraphPace.beat
    var pace = ParagraphPace(number: 2, showing: 0, at: start)
    pace.arrived(3, at: start)
    pace.catchUp(at: start)
    #expect(pace.shown == 1)
    pace.catchUp(at: start + beat * 0.5)
    #expect(pace.shown == 1)
    #expect(pace.next == start + beat)
    pace.catchUp(at: start + beat)
    #expect(pace.shown == 2)
    pace.arrived(4, at: start + beat * 5)
    pace.catchUp(at: start + beat * 5)
    #expect(pace.shown == 4)
  }

  @Test func aPageFirstSeenShowsWhatIsAlreadyWrittenAtOnce() {
    var pace = ParagraphPace(number: 1, showing: 6, at: .now)
    #expect(pace.shown == 6)
    #expect(pace.next == nil)
    pace.arrived(2, at: .now)
    #expect(pace.shown == 2)
  }

  @Test func inTheNarrowestWindowTheContentsAndLociMakeWayForTheLesson() {
    let narrowest = Size.windowMinimum.width - Size.sidebarIdeal
    #expect(!CourseNav.fitsBeside(in: narrowest))
    #expect(!PaneWidth.panel.fitsBeside(in: narrowest))
    let wide = CourseSnapshots.wide.width
    #expect(CourseNav.fitsBeside(in: wide))
    #expect(PaneWidth.panel.fitsBeside(in: wide - CourseNav.width))
  }

  @Test func aSourceCardsMenuOpensTheOriginalAndRemovesItWhileSourcesCanChange() throws {
    let source = ReadingSamples.sources[3]
    let url = try #require(source.url)
    #expect(SourceCard.menu(for: source, editable: true) == [.open(url), .remove])
    #expect(SourceCard.menu(for: source, editable: false) == [.open(url)])
    #expect(SourceCard.menu(for: BuilderSamples.sources[3], editable: true) == [.remove])
  }

  @Test func readingTimeCountsChineseByCharacterAndEnglishByWord() {
    #expect(LessonFacts.minutes(String(repeating: "多数派", count: 400)) == 3)
    #expect(LessonFacts.minutes(Array(repeating: "quorum", count: 660).joined(separator: " ")) == 3)
    #expect(LessonFacts.minutes("短") == 1)
  }
}

/// The words on a course's paper and cloth stay readable, in both appearances.
@MainActor
struct CourseColorTests {
  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func inkOnPaperAndClothIsReadable(appearance: NSAppearance.Name) {
    let paper = PaletteTests.components(of: Palette.leaf, in: appearance)
    #expect(PaletteTests.contrast(PaletteTests.components(of: Palette.leafInk, in: appearance), paper) >= 7)
    for cloth in Palette.Cloth.all {
      let ground = PaletteTests.components(of: cloth, in: appearance)
      #expect(PaletteTests.contrast(PaletteTests.components(of: Palette.clothInk, in: appearance), ground) >= 4.5)
    }
  }
}
