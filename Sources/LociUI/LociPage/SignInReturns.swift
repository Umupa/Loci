import AppKit
import LociModel
import SwiftUI

/// The connector whose sign-in the browser just came back from, waiting for a window on this Mac to turn to its
/// Connectors page. Loci comes to the front as it arrives, so the person need not switch back from the browser.
@MainActor
@Observable
public final class SignInReturns {
  public private(set) var waiting: ConnectorID?
  private let activate: @MainActor () -> Void

  /// `activate` brings Loci to the front.
  public init(activate: @escaping @MainActor () -> Void = { NSApp.activate() }) {
    self.activate = activate
  }

  public func returned(from connector: ConnectorID) {
    waiting = connector
    activate()
  }

  /// Hands over the connector waiting, once.
  func take() -> ConnectorID? {
    defer { waiting = nil }
    return waiting
  }
}

extension EnvironmentValues {
  @Entry var signInReturns: SignInReturns?
}

extension View {
  /// Lets the windows inside turn to a connector's page when the browser comes back from its sign-in.
  public func returningFromSignIns(_ returns: SignInReturns) -> some View {
    environment(\.signInReturns, returns)
  }
}
