import LociModel
import SwiftUI

/// The Macs a window can switch between, and what the sidebar's foot, its menu and settings can do with them.
struct MachineChoice {
  let roster: Roster
  /// The Mac the window shows.
  let shown: Machine
  /// `nil` when the window shows this Mac.
  let link: LociModel.Link?
  let menuOpen: Bool
  let openMenu: () -> Void
  let addMac: () -> Void
  let remove: (MachineID) -> Void
  let acceptInvite: (Invite) -> Void

  /// Whether the shown Mac is another one that cannot take changes now: it is offline or being dialed again.
  var offline: Machine? {
    switch link {
    case nil, .connected: nil
    case .reconnecting, .offline: shown
    }
  }
}

extension EnvironmentValues {
  @Entry var machineChoice: MachineChoice?
}

extension Roster {
  /// This Mac, then the paired ones.
  var all: [Machine] { [this] + paired.map(\.machine) }

  /// How a paired Mac can be reached; `nil` for this Mac and for a Mac not in the roster.
  func link(of machine: MachineID) -> LociModel.Link? {
    paired.first { $0.id == machine }?.link
  }
}
