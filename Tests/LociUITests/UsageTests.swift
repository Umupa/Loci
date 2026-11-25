import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// US-S2–US-S8: the usage page adds up the companion's sessions and marks what looks wrong.
@MainActor
@Suite(.serialized, .onStage)
struct UsageTests {
  private static let now = SampleTimers.now

  private static func report(span: UsageSpan = .week, kind: UsageKind? = nil) -> UsageReport {
    UsageReport(SampleUsage.month(), span: span, kind: kind, now: now, calendar: .current)
  }

  @Test func theWeekHoldsSevenDaysAndTodayHoldsTwentyFourHours() {
    #expect(Self.report().buckets.count == 7)
    #expect(Self.report(span: .today).buckets.count == 24)
    #expect(Self.report(span: .month).buckets.count == 30)
    let week = Self.report()
    #expect(
      week.sessions.allSatisfy {
        Calendar.current.dateComponents([.day], from: $0.startedAt.date, to: Self.now).day ?? 99 < 7
      })
    #expect(week.buckets.map(\.total).reduce(0, +) == week.tokens.fresh)
  }

  @Test func activitiesAreOneRowEachWithTheMostNewTokensFirst() throws {
    let activities = Self.report(span: .month).activities
    #expect(activities.contains { $0.activity == .course(SampleUsage.course) })
    #expect(Set(activities.map(\.activity)).count == activities.count)
    #expect(activities.map(\.fresh) == activities.map(\.fresh).sorted(by: >))
    let weather = try #require(activities.first { $0.activity == .panel("weather") })
    #expect(weather.sessions.count == 30)
  }

  @Test func choosingAKindNarrowsTheTableAndTotalsButNotTheChartOrLegend() {
    let all = Self.report()
    let panels = Self.report(kind: .panel)
    #expect(panels.activities.allSatisfy { $0.kind == .panel })
    #expect(panels.tokens.fresh < all.tokens.fresh)
    #expect(panels.kinds == all.kinds)
    #expect(panels.buckets == all.buckets)
  }

  @Test func aPanelThatStartsOnMostOfItsContextOrKeepsFindingNothingIsMarked() throws {
    let activities = Self.report().activities
    let weather = try #require(activities.first { $0.activity == .panel("weather") })
    #expect(weather.flags.contains { if case .heavyStart = $0 { true } else { false } })
    let tweets = try #require(activities.first { $0.activity == .panel("tweet-intel") })
    #expect(
      tweets.flags.contains { if case .idleStreak(let runs) = $0 { runs >= UsageFlag.idleStreak } else { false } })
    let course = try #require(Self.report(span: .month).activities.first { $0.kind == .course })
    #expect(course.flags.contains(.largeContext(course.peak)))
    #expect(course.outcomes == nil)
  }

  @Test func theStartIsSplitIntoTheCLIAgentsAndThePrefix() {
    let start = Self.report().start
    #expect(Set(start.map(\.source)) == [.runtime, .instructions, .prefix])
    #expect(start.first?.source == .runtime)
  }

  @Test(arguments: [
    (940, "940"), (71_400, "71.4K"), (330_000, "330K"), (3_850_000, "3.85M"), (25_600_000, "25.6M"), (1_000, "1K"),
  ])
  func tokenCountsReadShort(count: Int, text: String) {
    #expect(TokenFigure.text(count) == text)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func usagePage(appearance: Snapshot.Appearance) async throws {
    let view = LociScreen(tab: .usage)
      .lociHost(FakeHost(try Sample(problems: false), usage: SampleUsage.month()))
      .environment(\.fixedNow, Self.now)
    try await ScreenSnapshots.shoot("loci-usage", view, appearance: appearance, size: CGSize(width: 1100, height: 1500))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func anActivityOpenedInPlace(appearance: Snapshot.Appearance) async throws {
    let view = ScrollView {
      UsageTab(span: .month, opened: .panel("following-picks")).padding(Spacing.xl)
    }
    .background(Palette.canvas)
    .lociHost(FakeHost(try Sample(problems: false), usage: SampleUsage.month()))
    .environment(\.fixedNow, Self.now)
    try await ScreenSnapshots.shoot(
      "loci-usage-open", view, appearance: appearance, size: CGSize(width: 1040, height: 1500))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func aKindChosenAndNarrowed(appearance: Snapshot.Appearance) async throws {
    let view = ScrollView {
      UsageTab(span: .today, kind: .panel).padding(Spacing.xl)
    }
    .background(Palette.canvas)
    .lociHost(FakeHost(try Sample(problems: false), usage: SampleUsage.month()))
    .environment(\.fixedNow, Self.now)
    try await ScreenSnapshots.shoot(
      "loci-usage-panels", view, appearance: appearance, size: CGSize(width: 1040, height: 1100))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func usagePageInEnglish(appearance: Snapshot.Appearance) async throws {
    let view = ScrollView {
      UsageTab(opened: .panel("sandbox-radar")).padding(Spacing.xl)
    }
    .background(Palette.canvas)
    .lociHost(FakeHost(try Sample(problems: false), usage: SampleUsage.month()))
    .environment(\.fixedNow, Self.now)
    try await ScreenSnapshots.shoot(
      "loci-usage-en", view, appearance: appearance, english: true, size: CGSize(width: 1040, height: 1500))
  }
}
