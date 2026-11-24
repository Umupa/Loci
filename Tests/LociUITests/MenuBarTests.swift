import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// WK-S9: Loci stays in the menu bar with every window closed.
@MainActor
@Suite(.serialized, .onStage)
struct MenuBarTests {
  @Test func closingTheLastWindowLeavesLociRunning() {
    #expect(!LociAppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
  }

  @Test func theMenuBarFollowsTheCompanionsNameAndWork() async throws {
    let companion = MenuBarCompanion(host: FakeHost(try Sample(), working: true))
    try await eventually("the name and the work") { companion.name == "小满" && companion.work != nil }
  }

  @Test func theMenuBarIconChangesWhileTheCompanionWorks() {
    let idle = MenuBarGlyph.image(working: false)
    let working = MenuBarGlyph.image(working: true)
    #expect(idle.isTemplate && working.isTemplate)
    #expect(idle.tiffRepresentation != working.tiffRepresentation)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func menuBarPanel(appearance: Snapshot.Appearance) async throws {
    for working in [false, true] {
      let companion = MenuBarCompanion(host: FakeHost(try Sample(), working: working))
      try await eventually("the name") { companion.name == "小满" }
      let view = MenuBarPanel(companion: companion).background(Palette.canvas)
      let glyph = Image(nsImage: MenuBarGlyph.image(working: working)).renderingMode(.template)
        .foregroundStyle(Palette.ink).padding(8)
      let shown = VStack(alignment: .leading, spacing: 12) {
        glyph
        view
      }.padding(20).background(Palette.well)
      try await Snapshot.render(
        shown, named: working ? "menu-bar-working" : "menu-bar", size: CGSize(width: 320, height: 220),
        appearance: appearance)
    }
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func openAtLoginAwaitingApproval(appearance: Snapshot.Appearance) async throws {
    let view = GeneralSettingsPage(version: AppVersion(number: "1.8.0", build: "500"))
      .lociHost(FakeHost(try Sample()))
      .environment(\.loginItem, FakeLoginItem(state: .awaitingApproval))
    try await Snapshot.render(
      view, named: "settings-general-login", size: CGSize(width: 800, height: 600), appearance: appearance)
  }
}

@MainActor
final class FakeLoginItem: LoginItem {
  private(set) var state: LoginItemState

  init(state: LoginItemState) {
    self.state = state
  }

  func turn(on: Bool) throws {
    state = on ? .on : .off
  }

  func showSystemSettings() {}
}
