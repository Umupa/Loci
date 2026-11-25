import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// WK-S2, WK-S6, WK-S9: the Timers page and the menu bar's next timer.
@MainActor
@Suite(.serialized, .onStage)
struct TimersTests {
  @Test func theMenuBarNamesWhatComesDueSoonestAmongSchedulesAndFollowUps() throws {
    let next = try #require(NextTimer(SampleTimers.design.timers))
    #expect(next.title == "本周的任务")
  }

  @Test func aPausedScheduleIsNeverNext() throws {
    let paused = ScheduleEntry(
      ref: .panel(PanelRef("p")), name: "p", title: "暂停的", every: .hour, destination: .panel("p"), paused: true,
      next: nil,
      lastSummary: nil)
    #expect(NextTimer(Timers(schedules: [paused], followUps: [], next: nil)) == nil)
  }

  @Test func theMenuBarShowsTheNextTimer() async throws {
    let companion = MenuBarCompanion(host: FakeHost(try Sample(), timers: .design))
    try await eventually("the next timer") { companion.next?.title == "本周的任务" }
  }

  @Test func aRunsSourcesReadAsRepositoriesAndSites() {
    #expect(RunSources.name("https://github.com/TencentCloud/CubeSandbox/releases") == "TencentCloud/CubeSandbox")
    #expect(RunSources.name("https://www.cloud.tencent.com/developer/article/1") == "cloud.tencent.com")
    #expect(RunSources.name("资料库 · E2B 架构") == "资料库 · E2B 架构")
  }

  @Test func theFrequencyMenuAlwaysOffersTheCurrentOne() throws {
    let odd = Every.day(at: try #require(TimeOfDay(hour: 7, minute: 30)))
    #expect(odd.choices.contains(odd))
    #expect(Every.hour.choices.filter { $0 == .hour }.count == 1)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func timersPage(appearance: Snapshot.Appearance) async throws {
    let design = SampleTimers.design
    let opened = try #require(design.runs.keys.first)
    try await shoot("loci-timers", timers: design, opened: opened, appearance: appearance)
  }

  /// Half a screen: titles keep two lines, frequency and destination keep their width, follow-ups go below.
  @Test(arguments: Snapshot.Appearance.allCases)
  func timersPageNarrow(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-timers-narrow", timers: .design, opened: nil, appearance: appearance, width: 700)
    try await shoot("loci-timers-half", timers: .design, opened: nil, appearance: appearance, width: 520)
  }

  @Test func sectionsGoOneUnderTheOtherWhenTheyNoLongerFitSideBySide() throws {
    let columns = PageColumns()
    let wide = try #require(columns.widths(for: 900))
    #expect(wide.first >= columns.narrowestFirst && columns.second.contains(wide.second))
    #expect(columns.widths(for: 640) == nil)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func timersPageEmpty(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-timers-empty", timers: .none, opened: nil, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func timersPageInEnglish(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-timers-en", timers: .design, opened: nil, appearance: appearance, english: true)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func menuBarWithTheNextTimer(appearance: Snapshot.Appearance) async throws {
    let companion = MenuBarCompanion(host: FakeHost(try Sample(), working: true, timers: .design))
    try await eventually("the next timer") { companion.next != nil && !companion.name.isEmpty }
    let view = MenuBarPanel(companion: companion).background(Palette.canvas).padding(20).background(Palette.well)
      .environment(\.fixedNow, SampleTimers.now)
    try await Snapshot.render(
      view, named: "menu-bar-next", size: CGSize(width: 300, height: 200), appearance: appearance)
  }

  private func shoot(
    _ name: String, timers: SampleTimers, opened: ScheduleRef?, appearance: Snapshot.Appearance, english: Bool = false,
    width: CGFloat = 1036
  ) async throws {
    let view = HStack(spacing: 0) { LociScreen(tab: .timers, opened: opened) }
      .lociHost(
        FakeHost(try Sample(problems: false), library: try SampleLibrary(), panels: SampleTimers.panels, timers: timers)
      )
      .environment(\.fixedNow, SampleTimers.now)
    try await ScreenSnapshots.shoot(
      name, view, appearance: appearance, english: english, size: CGSize(width: width, height: 900))
  }
}
