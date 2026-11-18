import LociModel
import SwiftUI

/// The menu rising from the sidebar's foot: this Mac, the paired ones, and adding another.
struct MachineMenu: View {
  enum Entry: Hashable {
    case machine(MachineID)
    case add
  }

  let roster: Roster
  let current: MachineID
  let choose: (Entry) -> Void
  let close: () -> Void

  var body: some View {
    GlassMenu(entries: entries, choose: choose, close: close)
  }

  private var entries: [GlassMenuEntry<Entry>] {
    [item(roster.this, enabled: true), .separator]
      + roster.paired.map { item($0.machine, enabled: $0.link != .offline) }
      + [.separator, .item(GlassMenuItem(id: .add, title: Text(.loci("remote.addMac"))))]
  }

  private func item(_ machine: Machine, enabled: Bool) -> GlassMenuEntry<Entry> {
    .item(
      GlassMenuItem(
        id: .machine(machine.id), title: Text(verbatim: machine.name), symbol: Symbols.machine(machine.model),
        checked: machine.id == current, enabled: enabled))
  }
}
