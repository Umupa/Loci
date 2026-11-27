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
