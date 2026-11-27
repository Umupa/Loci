import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// UI-S23: checking by hand finds a new release already downloading and shows how far it has got.
@MainActor
@Suite(.onStage)
struct AppUpdateWindowTests {
  @Test func findingANewReleaseShowsItsDownloadProgress() async throws {
    let release = AppRelease(
      version: ReleaseVersion("1.2.0")!, image: URL(string: "https://example.com/Loci-Beta-1.2.0.dmg")!,
      checksum: String(repeating: "0", count: 64))
    let updates = FindingUpdates(found: .downloading(release, Fraction(0.4)))
    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 352, height: 128), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: AppUpdateWindow(updates: updates, version: "1.1.1"))
    window.orderBack(nil)
    defer { window.orderOut(nil) }

    try await eventually("the download's progress to show") {
      Self.indicators(in: window.contentView).contains { !$0.isIndeterminate && $0.doubleValue == 0.4 }
    }
  }

  @Test func theUpdateWindowListsEveryVersionBetweenTheRunningOneAndTheNew() {
    let notes = ["1.2.0", "1.1.2", "1.1.1", "1.1.0"].map {
      ReleaseNotes(version: ReleaseVersion($0)!, changes: ["in \($0)"])
    }
    let release = AppRelease(
      version: ReleaseVersion("1.2.0")!, image: URL(string: "https://example.com/Loci-Beta-1.2.0.dmg")!,
      checksum: String(repeating: "0", count: 64), notes: notes)
    let listed = AppUpdateWindow.changes(in: .ready(release), running: "1.1.1")
    #expect(listed.map(\.version.description) == ["1.2.0", "1.1.2"])
    #expect(AppUpdateWindow.changes(in: .current, running: "1.1.1").isEmpty)
  }

  @Test(arguments: [3, 12])
  func theWindowGrowsToShowEveryChangeAndTheButton(versions: Int) async throws {
    let notes = (1...versions).reversed().map { "9.0.\($0)" }.map { version in
      ReleaseNotes(
        version: ReleaseVersion(version)!,
        changes: ["\(version) 的第一条变化，写得足够长，在窗口里会折成两行，看得出高度。", "\(version) 的第二条变化。"])
    }
    let release = AppRelease(
      version: notes[0].version, image: URL(string: "https://example.com/Loci-Beta-9.dmg")!,
      checksum: String(repeating: "0", count: 64), notes: notes)
    let controller = NSHostingController(
      rootView: AppUpdateWindow(updates: FindingUpdates(found: .ready(release)), version: "9.0.0"))
    let window = NSWindow(contentViewController: controller)
    window.setFrameOrigin(CGPoint(x: -20_000, y: -20_000))
    window.orderBack(nil)
    defer { window.orderOut(nil) }

    let list = NSHostingController(rootView: ReleaseChanges.Rows(notes: notes).frame(width: 440 - 48))
    let listHeight = list.sizeThatFits(in: CGSize(width: 440 - 48, height: 10_000)).height
    try await eventually("the window to hold every change and the button", within: .seconds(10)) {
      let squeezed = controller.sizeThatFits(in: CGSize(width: 440, height: 0)).height
      let roomy = controller.sizeThatFits(in: CGSize(width: 440, height: 10_000)).height
      let shown = min(listHeight, ReleaseChanges.tallest)
      return squeezed == roomy && squeezed >= shown + 100 && squeezed <= shown + 200
        && window.contentLayoutRect.height >= squeezed
    }
  }

  @Test func theButtonSaysWhenTheNewVersionDidNotStartOrLociMustMoveFirst() {
    let release = AppRelease(
      version: ReleaseVersion("1.2.0")!, image: URL(string: "https://example.com/Loci-Beta-1.2.0.dmg")!,
      checksum: String(repeating: "0", count: 64))
    #expect(UpdateWords.title(of: .failed(release, .launch)).key == "update.failedLaunch")
    #expect(UpdateWords.title(of: .misplaced).key == "update.misplaced")
  }

  private static func indicators(in view: NSView?) -> [NSProgressIndicator] {
    guard let view else { return [] }
    return [view].compactMap { $0 as? NSProgressIndicator } + view.subviews.flatMap { indicators(in: $0) }
  }
}

/// A check that finds `found`, which then stays.
private struct FindingUpdates: Updates {
  let found: AppUpdate

  func check() async throws(UpdateCheckError) {}

  func states() -> AsyncStream<AppUpdate> {
    AsyncStream { $0.yield(found) }
  }

  func retry() async {}

  func restart() async {}

  func finishOnQuit() async {}
}
