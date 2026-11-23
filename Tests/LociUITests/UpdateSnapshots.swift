import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// The update button at the foot of the sidebar, in each of its states.
@MainActor
@Suite(.serialized, .onStage)
struct UpdateSnapshots {
  static let release = AppRelease(
    version: ReleaseVersion("1.2.0")!, image: URL(string: "https://example.com/Loci-Beta-1.2.0.dmg")!,
    checksum: String(repeating: "0", count: 64))

  @Test(arguments: Snapshot.Appearance.allCases)
  func manualChecksShowTheVersionAndNextAction(appearance: Snapshot.Appearance) async throws {
    for (name, state) in [("current", AppUpdate.current), ("available", .available(Self.release))] {
      try await Snapshot.render(
        AppUpdateWindow(updates: FixedUpdates(state: state), version: "1.1.1"),
        named: "update-check-\(name)", size: CGSize(width: 352, height: 128), appearance: appearance)
    }
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func sidebarWithAnUpdate(appearance: Snapshot.Appearance) async throws {
    let window = ScreenSnapshots.root(try Sample(problems: false), at: WindowState(place: .library(nil)))
      .environment(\.updates, FixedUpdates(state: .available(Self.release)))
    try await ScreenSnapshots.shoot("update", window, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func everyState(appearance: Snapshot.Appearance) async throws {
    let states: [AppUpdate] = [
      .available(Self.release), .downloading(Self.release, Fraction(0.4)), .ready(Self.release),
      .failed(Self.release, reason: "offline"),
    ]
    let row = HStack(spacing: Spacing.m) {
      ForEach(states, id: \.self) { UpdateMark(state: $0, act: {}) }
    }
    .padding(Spacing.m)
    .background(Palette.sidebarWash)
    let file = try await Snapshot.render(
      row, named: "update-states", size: CGSize(width: 220, height: 60), appearance: appearance)
    #expect(try Data(contentsOf: file).count > 1_000)
  }

  @Test func noButtonWithoutANewerRelease() async throws {
    let file = try await Snapshot.render(
      UpdateMark(state: .current, act: {}).frame(width: 40, height: 40).background(Palette.canvas),
      named: "update-none", size: CGSize(width: 40, height: 40), appearance: .light)
    let other = try await Snapshot.render(
      Color.clear.frame(width: 40, height: 40).background(Palette.canvas), named: "update-empty",
      size: CGSize(width: 40, height: 40), appearance: .light)
    #expect(try Data(contentsOf: file) == Data(contentsOf: other))
  }
}

private struct FixedUpdates: Updates {
  let state: AppUpdate

  func check() async throws(UpdateCheckError) {}

  func states() -> AsyncStream<AppUpdate> {
    AsyncStream { $0.yield(state) }
  }

  func download() async {}

  func install() async -> Bool { false }
}
