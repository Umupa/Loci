import LociModel
import SwiftUI

/// The content of a Loci window: one Mac's data at a time, and switching between the Macs paired with this one.
///
/// Each Mac gets a window of its own state, so nothing of the Mac left behind is ever shown for the next one,
/// and each reopens where it was left.
public struct RootView: View {
  private let machines: any Machines
  private let memory: @MainActor (MachineID?) -> WindowMemory
  private let talkShown: () -> Void
  private let updates: any Updates
  private let reset: DataReset?
  @State private var roster: Roster?
  /// `nil` is this Mac.
  @State private var current: MachineID?
  @State private var menuOpen: Bool
  @State private var sheet: RemoteSheetState?
  @State private var requests: [PairingRequest] = []
  @State private var browser: BrowserSession
  private let signIns: (any BrowserSignIns)?
  @AppStorage(PaneWidth.sidebar.key) private var sidebarWidth = Double(PaneWidth.sidebar.ideal)

  /// `folder` is the data folder this Mac serves, so each folder reopens where it was left. `talkShown` runs
  /// when the main conversation first appears, which is when Loci can be typed into. `updates` keeps this copy of
  /// Loci up to date, whichever Mac the window shows. `signIns` are this Mac's other browsers, which the built-in
  /// browser can start signed in to, whichever Mac the window shows. `reset` starts this Mac's Loci over; another
  /// Mac's cannot be reset from here.
  public init(
    folder: URL, machines: any Machines, updates: any Updates = NoUpdates(), signIns: (any BrowserSignIns)? = nil,
    reset: DataReset? = nil, talkShown: @escaping () -> Void = {}
  ) {
    self.init(
      machines: machines,
      memory: { machine in
        machine.map { .preferences(.standard, remote: $0) } ?? .preferences(.standard, folder: folder)
      }, updates: updates, talkShown: talkShown, browser: BrowserSession(signIns: signIns), signIns: signIns,
      reset: reset)
  }

  /// Opens each Mac where `memory` says it was last. `current`, `menuOpen` and `sheet` start the window
  /// part way through, for a snapshot.
  init(
    machines: any Machines, memory: @escaping @MainActor (MachineID?) -> WindowMemory,
    updates: any Updates = NoUpdates(), talkShown: @escaping () -> Void = {}, current: MachineID? = nil,
    menuOpen: Bool = false,
    sheet: RemoteSheetState? = nil, browser: BrowserSession = BrowserSession(), signIns: (any BrowserSignIns)? = nil,
    reset: DataReset? = nil
  ) {
    self.machines = machines
    self.memory = memory
    self.talkShown = talkShown
    self.updates = updates
    _current = State(initialValue: current)
    _menuOpen = State(initialValue: menuOpen)
    _sheet = State(initialValue: sheet)
    _browser = State(initialValue: browser)
    self.signIns = signIns
    self.reset = reset
  }

  public var body: some View {
    ZStack {
      if let roster {
        let shown = roster.all.first { $0.id == current } ?? roster.this
        MachineWindow(
          talkShown: talkShown, memory: memory(shown == roster.this ? nil : shown.id), browser: browser
        )
        .id(shown.id)
        .lociHost(machines.open(shown.id))
        .environment(\.machineChoice, choice(roster, shown: shown))
        .environment(\.updates, updates)
        .environment(\.signIns, signIns)
        .environment(\.dataReset, shown == roster.this ? reset : nil)
      } else {
        Palette.canvas
      }
    }
    .glassMenuLayer(isPresented: $menuOpen) {
      if let roster {
        MachineMenu(roster: roster, current: current ?? roster.this.id, choose: choose, close: { menuOpen = false })
          .frame(width: PaneWidth.sidebar.clamped(sidebarWidth) - Spacing.xs * 2)
          .padding(.leading, Spacing.xs * 2)
          .padding(.bottom, Spacing.xs + Size.machineMenuLift)
      }
    }
    .overlay { sheets }
    .task {
      for await next in machines.roster() {
        roster = next
        if let current, next.link(of: current) == nil { show(nil) }
      }
    }
    .task {
      for await waiting in machines.requests() { requests = waiting }
    }
  }

  private func choice(_ roster: Roster, shown: Machine) -> MachineChoice {
    MachineChoice(
      roster: roster, shown: shown, link: roster.link(of: shown.id), menuOpen: menuOpen, openMenu: { menuOpen = true },
      addMac: { sheet = .adding },
      remove: { machine in Task { await machines.remove(machine) } },
      acceptInvite: accept)
  }

  private func choose(_ entry: MachineMenu.Entry) {
    menuOpen = false
    switch entry {
    case .machine(let machine): show(machine == roster?.this.id ? nil : machine)
    case .add: sheet = .adding
    }
  }

  /// Shows another Mac at once, without carrying anything over or animating between the two.
  private func show(_ machine: MachineID?) {
    var instant = Transaction()
    instant.disablesAnimations = true
    withTransaction(instant) { current = machine }
  }

  private func accept(_ invite: Invite) {
    sheet = .joining(invite)
  }

  @ViewBuilder private var sheets: some View {
    if let request = requests.first {
      ApproveSheet(request: request) { allow in Task { await machines.answer(request.id, allow: allow) } }
    } else if let sheet {
      RemoteSheets(sheet: sheet, machines: machines) { self.sheet = $0 }
    }
  }
}

extension View {
  /// Gives the views inside the host they read from and send commands to.
  public func lociHost(_ host: any LociModel.Host) -> some View {
    environment(\.host, host)
  }
}
