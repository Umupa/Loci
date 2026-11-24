import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// CN-S1: once the browser is back from a sign-in, Loci comes to the front on that connector's page.
@MainActor
@Suite(.onStage)
struct SignInReturnsTests {
  @MainActor final class Shown {
    var window: WindowState?
    var activated = 0
  }

  @Test func theWindowTurnsToTheConnectorTheBrowserCameBackFrom() async throws {
    let shown = Shown()
    let returns = SignInReturns { shown.activated += 1 }
    let size = CGSize(width: 1000, height: 700)
    let view = MachineWindow(memory: WindowMemory(recall: { WindowState() }, remember: { shown.window = $0 }))
      .lociHost(FakeHost(try Sample(problems: false)))
      .returningFromSignIns(returns)
      .frame(width: size.width, height: size.height)
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: view)
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(300))

    returns.returned(from: ConnectorID("linear"))

    try await eventually("the connector's page") { shown.window?.place == .connector(ConnectorID("linear")) }
    #expect(shown.activated == 1)
    #expect(returns.waiting == nil)
  }
}
