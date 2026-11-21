import Foundation
import LociModel
import Testing

@testable import LociHost

/// P-S8: a panel is refreshed at its time; one missed while the app was closed is made up once.
struct PanelScheduleTests {
  static let zone = TestWorld.timeZone
  static let daily = PanelRefresh(every: .day, at: "10:00")
  /// Sundays at 10:00.
  static let weekly = PanelRefresh(every: .week, at: "10:00", weekday: 1)

  /// A moment on 2025-11-17, a Monday in Shanghai, or `days` later.
  static func at(_ time: String, days: Int = 0) -> Timestamp {
    let day = Day("2025-11-17")!.adding(days: days)
    let clock = TimeOfDay(time)!
    return Timestamp(
      millisecondsSince1970: day.start(in: zone).millisecondsSince1970 + Int64(clock.hour * 60 + clock.minute) * 60_000)
  }

  static func isDue(_ refresh: PanelRefresh, last: Timestamp?, now: Timestamp) -> Bool {
    PanelSchedule.isDue(refresh, last: last, now: now, timeZone: zone)
  }

  @Test func aDailyPanelIsDueOnceItsTimeHasCome() {
    let last = Self.at("10:05", days: -1)

    #expect(!Self.isDue(Self.daily, last: last, now: Self.at("09:59")))
    #expect(Self.isDue(Self.daily, last: last, now: Self.at("10:00")))
    #expect(!Self.isDue(Self.daily, last: Self.at("10:00"), now: Self.at("23:00")))
  }

  @Test func aTimeMissedWhileClosedIsMadeUpOnceNotForEachDay() {
    let last = Self.at("10:00", days: -3)
    let opened = Self.at("08:00")

    #expect(Self.isDue(Self.daily, last: last, now: opened))
    #expect(!Self.isDue(Self.daily, last: opened, now: Self.at("09:00")))
    #expect(Self.isDue(Self.daily, last: opened, now: Self.at("10:00")))
  }

  @Test func aWeeklyPanelWaitsForItsDay() {
    let sunday = Self.at("10:00", days: -1)

    #expect(Self.isDue(Self.weekly, last: Self.at("12:00", days: -2), now: Self.at("08:00")))
    #expect(!Self.isDue(Self.weekly, last: Self.at("11:00", days: -1), now: Self.at("08:00", days: 5)))
    #expect(Self.isDue(Self.weekly, last: Self.at("11:00", days: -1), now: Self.at("10:00", days: 6)))
    #expect(PanelSchedule.latestTime(of: Self.weekly, atOrBefore: Self.at("08:00"), in: Self.zone) == sunday)
  }

  @Test func anHourlyPanelIsDueAnHourAfterTheLastTime() {
    let last = Self.at("08:10")
    let hourly = PanelRefresh(every: .hour)

    #expect(!Self.isDue(hourly, last: last, now: Self.at("09:09")))
    #expect(Self.isDue(hourly, last: last, now: Self.at("09:10")))
  }

  @Test func aPanelNeverRefreshedIsDue() {
    #expect(Self.isDue(Self.daily, last: nil, now: Self.at("08:00")))
  }
}

/// P-S9: the column keeps the person's order; 「接着读」 starts at the top and new panels go to the bottom.
struct PanelOrderTests {
  static func panel(_ name: String) -> Panel {
    Panel(name: name, title: name, follow: "x", body: .rows([.sentence("a")]))
  }

  @Test func readingStartsAtTheTopAndPanelsTheOrderDoesNotKnowGoToTheBottom() {
    #expect(PanelOrder.places([], panels: ["b", "a"]) == [.reading, .panel("a"), .panel("b")])
    #expect(
      PanelOrder.places([.panel("b"), .reading, .panel("gone")], panels: ["a", "b"]) == [
        .panel("b"), .reading, .panel("a"),
      ])
  }

  @Test func movingToTheTopKeepsTheRestInOrder() {
    let order: [PanelPlace] = [.reading, .panel("a"), .panel("b")]

    #expect(
      PanelOrder.movingToTop(.panel("b"), in: order, panels: ["a", "b"]) == [.panel("b"), .reading, .panel("a")])
    #expect(PanelOrder.movingToTop(.reading, in: [.panel("a"), .reading], panels: ["a"]) == [.reading, .panel("a")])
  }

  @Test func readingIsLeftOutWhenNothingIsReadPartway() throws {
    let item = try Item(id: TestWorld().nextID(), kind: .article, title: "Borg")
    let reading = [ReadingNow(item: item, progress: 0.5)]
    let panels = [Self.panel("a")]

    #expect(PanelOrder.slots([], panels: panels, reading: []) == [.panel(Self.panel("a"))])
    #expect(PanelOrder.slots([], panels: panels, reading: reading) == [.reading(reading), .panel(Self.panel("a"))])
  }
}

/// P-S5: how far along an item is, and how long the rest takes.
struct ReadingProgressTests {
  @Test func aVideoIsAsFarAlongAsItsTimeAndTheRestIsItsLength() throws {
    let id = TestWorld().nextID()
    let video = try Item(id: id, kind: .video(duration: .seconds(600)), title: "Borg")
    let position = Locator.item(id, .time(try TimeSpan(start: .seconds(150))))

    let now = try #require(ReadingProgress.of(position, in: video) { nil })

    #expect(now.progress == 0.25)
    #expect(now.minutesLeft == 8)
  }

  @Test func anArticleIsAsFarAlongAsItsQuoteAndTheRestTakesAnOrdinaryPace() throws {
    let id = TestWorld().nextID()
    let article = try Item(id: id, kind: .article, title: "Borg")
    let text = String(repeating: "调度", count: 400) + "从这里接着读" + String(repeating: "调度", count: 400)
    let position = Locator.item(id, .quote(try TextQuote("从这里接着读", before: "调度")))

    let now = try #require(ReadingProgress.of(position, in: article) { text })

    #expect(abs(now.progress - 800.0 / 1606.0) < 0.001)
    #expect(now.minutesLeft == 3)
  }

  /// The reader quotes the text as it shows it: list bullets, link text, no Markdown marks.
  @Test(arguments: [
    ("•\tAs several representations of a given ", "As several representations"),
    ("GET methods unchanged. Others may or may ", "methods unchanged"),
    ("When browsers receive a redirect, they im", "When browsers receive"),
  ])
  func aQuoteAsTheReaderShowsItIsFoundInTheMarkdown(quote: String, marks: String) throws {
    let id = TestWorld().nextID()
    let article = try Item(id: id, kind: .article, title: "Redirections in HTTP")
    let earlier = String(repeating: "Some earlier words about caches and validators.\n\n", count: 20)
    let later = String(repeating: "Some later words about redirects and loops.\n\n", count: 20)
    let markdown =
      earlier + "| Code | Method handling |\n| --- | --- |\n"
      + "| `301` | [`GET`](https://developer.mozilla.org/GET) methods unchanged. Others may or may not be changed. |\n\n"
      + "- As several representations of a given resource are sent, shared caches are less efficient.\n\n"
      + "When browsers receive a redirect, they immediately load the new URL provided in the `Location` header.\n\n"
      + later
    let position = Locator.item(id, .quote(try TextQuote(quote, before: "\n")))

    let now = try #require(ReadingProgress.of(position, in: article) { markdown })

    #expect(markdown.contains(marks))
    #expect(now.progress > 0.4 && now.progress < 0.6)
    #expect(now.minutesLeft == 1)
  }

  @Test func aQuoteOfTheTitleAtTheTopIsTheStartEvenWhenTheTitleComesAgainLater() throws {
    let id = TestWorld().nextID()
    let article = try Item(id: id, kind: .article, title: "How we built Pingora")
    let markdown =
      "Today we are happy to talk about it.\n\n" + String(repeating: "Words. ", count: 300)
      + "\n\nHow we built Pingora, the proxy\n"
    let position = Locator.item(
      id, .quote(try TextQuote("How we built Pingora, the prox", after: "\nThe Cloudflare Blog")))

    #expect(ReadingProgress.of(position, in: article) { markdown }?.progress == 0)
  }

  @Test func whatCannotBeToldIsLeftOut() throws {
    let id = TestWorld().nextID()
    let article = try Item(id: id, kind: .article, title: "Borg")
    let video = try Item(id: id, kind: .video(duration: nil), title: "Borg")

    #expect(
      ReadingProgress.of(.item(id, .quote(try TextQuote("gone words here", before: "an"))), in: article) {
        "other words"
      } == nil)
    #expect(ReadingProgress.of(.item(id, .time(try TimeSpan(start: .seconds(5)))), in: video) { nil } == nil)
    #expect(ReadingProgress.of(.item(id, .page(try PageRegion(page: 3))), in: article) { "text" } == nil)
  }

  @Test func wordsAndCharactersAreReadAtTheirOwnPace() {
    #expect(ReadingProgress.minutes(toRead: Substring(String(repeating: "word ", count: 460))) == 2)
    #expect(ReadingProgress.minutes(toRead: Substring(String(repeating: "字", count: 401))) == 2)
  }
}
