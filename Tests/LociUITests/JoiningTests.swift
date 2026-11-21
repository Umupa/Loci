import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// R-S3: pairing from a pasted invite link can be given up while it waits for the other Mac.
@MainActor
@Suite(.onStage)
struct JoiningTests {
  @Observable final class Shown {
    var sheet = true
  }

  @Test func closingTheSheetCancelsThePairing() async throws {
    let machines = FakeMachines(hosts: [:], acceptWaits: true)
    let shown = Shown()
    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 600, height: 400), styleMask: [.titled], backing: .buffered,
      defer: false)
    window.contentView = NSHostingView(
      rootView: JoiningHarness(shown: shown, machines: machines, invite: FakeMachines.invite(issuedAt: .now))
        .frame(width: 600, height: 400))
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    try await eventually("accept to start") { machines.acceptStarted.withLock { $0 } }

    shown.sheet = false
    try await eventually("accept to be cancelled") { machines.acceptCancelled.withLock { $0 } }

    #expect(machines.acceptCancelled.withLock { $0 })
  }

  private struct JoiningHarness: View {
    let shown: Shown
    let machines: FakeMachines
    let invite: Invite

    var body: some View {
      if shown.sheet {
        JoiningSheet(invite: invite, machines: machines) { _ in }
      }
    }
  }
}
