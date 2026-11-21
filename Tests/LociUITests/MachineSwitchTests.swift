import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociUI

/// R-S4, R-S7: the window shows one Mac at a time, each where it was left, and goes quiet about changes while
/// the Mac shown cannot take them.
@MainActor
@Suite(.serialized, .onStage)
struct MachineSwitchTests {
  static func machines(studio: LociModel.Link = .connected) throws -> FakeMachines {
    let activity = Activity()
    return FakeMachines(
      paired: [PairedMachine(machine: FakeMachines.studio, link: studio)],
      hosts: [
        FakeMachines.thisMac.id: FakeHost(try Sample(), activity: activity),
        FakeMachines.studio.id: FakeHost(try Sample(), activity: activity),
      ], activity: activity)
  }

  /// Opens a window on `current` and says which Mac's memory it read and what it kept there, once it has kept a
  /// place and the data it asked for has arrived, so a place it would give up for a missing item is gone too.
  static func open(_ machines: FakeMachines, current: MachineID?, places: [MachineID?: WindowState]) async throws
    -> (asked: [MachineID?], kept: [MachineID?: WindowState])
  {
    let asked = Mutex<[MachineID?]>([])
    let kept = Mutex<[MachineID?: WindowState]>([:])
    let view = RootView(
      machines: machines,
      memory: { machine in
        asked.withLock { $0.append(machine) }
        return WindowMemory(
          recall: { places[machine] ?? WindowState() }, remember: { state in kept.withLock { $0[machine] = state } })
      }, current: current)
    let quiet = Quiet(machines.activity)
    try await Snapshot.render(
      view, named: "machine-switch", appearance: .light,
      until: { _ in quiet.settled() && !kept.withLock { $0.isEmpty } })
    return (asked.withLock { $0 }, kept.withLock { $0 })
  }

  @Test func aPairedMacOpensWhereItWasLeftWithoutTouchingThisMacsPlace() async throws {
    let studio = FakeMachines.studio.id
    let there = WindowState(place: .loci)

    let opened = try await Self.open(
      try Self.machines(), current: studio, places: [nil: WindowState(place: .library(nil)), studio: there])

    #expect(Set(opened.asked) == [studio])
    #expect(opened.kept == [studio: there])
  }

  @Test func thisMacOpensWhereItWasLeft() async throws {
    let here = WindowState(place: .library(nil))

    let opened = try await Self.open(try Self.machines(), current: nil, places: [nil: here])

    #expect(Set(opened.asked) == [nil])
    #expect(opened.kept == [nil: here])
  }

  /// R-S8: a Mac removed while it was shown gives way to this one.
  @Test func aMacNoLongerPairedGivesWayToThisMac() async throws {
    let here = WindowState(place: .library(nil))

    let opened = try await Self.open(
      try Self.machines(), current: FakeMachines.mini.id,
      places: [nil: here, FakeMachines.mini.id: WindowState(place: .browser)])

    #expect(opened.kept == [nil: here])
  }

  @Test(arguments: [(LociModel.Link?.none, false), (.connected, false), (.reconnecting, true), (.offline, true)])
  func onlyAMacThatCannotBeReachedRefusesChanges(link: LociModel.Link?, refuses: Bool) {
    let choice = MachineChoice(
      roster: Roster(this: FakeMachines.thisMac, paired: []), shown: FakeMachines.studio, link: link,
      menuOpen: false, openMenu: {}, addMac: {}, remove: { _ in }, acceptInvite: { _ in })

    #expect((choice.offline != nil) == refuses)
  }

  /// R-S7: no dialog for a change refused because the Mac is offline; the window already says so.
  @Test func aChangeRefusedWhileOfflineRaisesNoDialog() {
    var dialogs = Dialogs()
    dialogs.failure = .offline
    #expect(dialogs.failure == nil)
    dialogs.failure = .notFound("item")
    #expect(dialogs.failure != nil)
  }
}
