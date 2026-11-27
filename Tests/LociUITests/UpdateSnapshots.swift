import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// The update button at the foot of the sidebar, in each of its states.
@MainActor
@Suite(.serialized, .onStage)
struct UpdateSnapshots {
  nonisolated static let release = AppRelease(
    version: ReleaseVersion("1.2.0")!, image: URL(string: "https://example.com/Loci-Beta-1.2.0.dmg")!,
    checksum: String(repeating: "0", count: 64))

  @Test(arguments: Snapshot.Appearance.allCases)
  func manualChecksShowTheVersionAndNextAction(appearance: Snapshot.Appearance) async throws {
    let states: [(String, AppUpdate)] = [
      ("current", .current), ("downloading", .downloading(Self.release, Fraction(0.4))),
      ("ready", .ready(Self.release)), ("waiting", .waiting(Self.release, for: .answering)),
      ("failed", .failed(Self.release, .checksum)),
    ]
    for (name, state) in states {
      try await Snapshot.render(
        AppUpdateWindow(updates: FixedUpdates(state: state), version: "1.1.1"),
        named: "update-check-\(name)", size: CGSize(width: 352, height: 128), appearance: appearance)
    }
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func manualChecksListTheChangesSinceTheRunningVersion(appearance: Snapshot.Appearance) async throws {
    let three = Self.notes(["9.0.3", "9.0.2", "9.0.1"])
    let many = Self.notes((1...12).reversed().map { "9.0.\($0)" })
    let cases: [(String, AppUpdate)] = [
      ("ready", .ready(Self.release(three))), ("downloading", .downloading(Self.release(three), Fraction(0.4))),
      ("did-not-start", .failed(Self.release(three), .launch)), ("many", .ready(Self.release(many))),
      ("misplaced", .misplaced),
    ]
    for (name, state) in cases {
      let window = AppUpdateWindow(updates: FixedUpdates(state: state), version: "9.0.0")
      try await Snapshot.render(
        window, named: "update-changes-\(name)", size: try await Self.fitted(window), appearance: appearance)
    }
  }

  private static func notes(_ versions: [String]) -> [ReleaseNotes] {
    versions.map { version in
      ReleaseNotes(
        version: ReleaseVersion(version)!,
        changes: [
          "更新只下补丁：从上一版升级通常十几 MB，打好后逐个文件核对，再验整包签名。",
          "**项目栏**切换更顺，`检查更新` 窗口列出跨版本的变化。",
        ])
    }
  }

  private static func release(_ notes: [ReleaseNotes]) -> AppRelease {
    AppRelease(
      version: notes[0].version, image: URL(string: "https://example.com/Loci-Beta.dmg")!,
      checksum: String(repeating: "0", count: 64), notes: notes)
  }

  /// The size the update window takes for `view` once it has checked, as the window scene sizes to its content.
  private static func fitted(_ view: AppUpdateWindow) async throws -> CGSize {
    let controller = NSHostingController(rootView: view)
    let window = NSWindow(contentViewController: controller)
    window.setFrameOrigin(CGPoint(x: -20_000, y: -20_000))
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(500))
    var size = CGSize.zero
    try await eventually("the update window to settle") {
      let next = controller.sizeThatFits(in: CGSize(width: 440, height: 0))
      defer { size = next }
      return next == size
    }
    return size
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func sidebarWithAnUpdate(appearance: Snapshot.Appearance) async throws {
    let window = ScreenSnapshots.root(try Sample(problems: false), at: WindowState(place: .library(nil)))
      .environment(\.updates, FixedUpdates(state: .ready(Self.release)))
    try await ScreenSnapshots.shoot("update", window, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func everyState(appearance: Snapshot.Appearance) async throws {
    let states: [AppUpdate] = [
      .ready(Self.release), .waiting(Self.release, for: .answering), .waiting(Self.release, for: .library),
      .failed(Self.release, .signature), .failed(Self.release, .launch), .misplaced,
    ]
    let row = HStack(spacing: Spacing.m) {
      ForEach(states, id: \.self) { UpdateMark(state: $0, act: {}) }
    }
    .padding(Spacing.m)
    .background(Palette.sidebarWash)
    let file = try await Snapshot.render(
      row, named: "update-states", size: CGSize(width: 340, height: 60), appearance: appearance)
    #expect(try Data(contentsOf: file).count > 1_000)
  }

  @Test(arguments: [AppUpdate.current, .downloading(release, Fraction(0.4)), .downloading(release, nil)])
  func noButtonUntilTheUpdateIsReady(state: AppUpdate) async throws {
    let file = try await Snapshot.render(
      UpdateMark(state: state, act: {}).frame(width: 40, height: 40).background(Palette.canvas),
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

  func retry() async {}

  func restart() async {}

  func finishOnQuit() async {}
}
