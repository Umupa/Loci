import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// Switching between Macs and pairing them, in light and dark, one picture for each state the design draws.
@MainActor
@Suite(.serialized, .onStage)
struct RemoteSnapshots {
  static let window = CGSize(width: 1240, height: 800)

  static func machines(
    studio: LociModel.Link = .connected, alone: Bool = false, nearby: [NearbyMac] = [],
    requests: [PairingRequest] = [], studioLibrary: Bool = false, acceptWaits: Bool = false
  ) throws -> FakeMachines {
    let paired =
      alone
      ? []
      : [
        PairedMachine(machine: FakeMachines.studio, link: studio),
        PairedMachine(machine: FakeMachines.mini, link: .offline),
      ]
    let activity = Activity()
    return FakeMachines(
      paired: paired,
      hosts: [
        FakeMachines.thisMac.id: FakeHost(
          try Sample(problems: false), library: try SampleLibrary(), activity: activity),
        FakeMachines.studio.id: FakeHost(
          try Sample(problems: false), library: studioLibrary ? try SampleLibrary() : nil, activity: activity),
      ], nearby: nearby, requests: requests, acceptWaits: acceptWaits, activity: activity)
  }

  static func shoot(
    _ name: String, _ machines: FakeMachines, current: Machine? = nil,
    at place: WindowState = WindowState(
      place: .library(nil)), menuOpen: Bool = false, sheet: RemoteSheetState? = nil, standIns: StandIns = StandIns(),
    size: CGSize = window, appearance: Snapshot.Appearance, english: Bool = false,
    shows: @escaping @MainActor (NSWindow) -> Bool = { _ in true }
  ) async throws {
    let view = RootView(
      machines: machines, memory: { _ in WindowMemory(recall: { place }, remember: { _ in }) },
      current: current?.id, menuOpen: menuOpen, sheet: sheet
    )
    .environment(\.standIns, standIns)
    let quiet = Quiet(machines.activity)
    let file = try await Snapshot.render(
      view, named: "remote-\(name)", size: size, appearance: appearance,
      locale: Locale(identifier: english ? "en" : "zh-Hans"), until: { quiet.settled() && shows($0) },
      steady: true)
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  /// R-S1: with no other Mac, nothing remote but settings' row.
  @Test(arguments: Snapshot.Appearance.allCases)
  func single(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("single", try Self.machines(alone: true), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func thisMac(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "this", try Self.machines(), standIns: StandIns(pointerOnMachineFoot: true), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func menu(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("menu", try Self.machines(), menuOpen: true, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func menuInEnglish(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("menu-en", try Self.machines(), menuOpen: true, appearance: appearance, english: true)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func connected(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("connected", try Self.machines(), current: FakeMachines.studio, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func reconnecting(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "reconnecting", try Self.machines(studio: .reconnecting), current: FakeMachines.studio, appearance: appearance)
  }

  /// R-S7: the article reads as before; where Loci's field was, one line says the Mac is offline.
  @Test(arguments: Snapshot.Appearance.allCases)
  func offline(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "offline", try Self.machines(studio: .offline, studioLibrary: true), current: FakeMachines.studio,
      at: LibrarySnapshots.reading(library.article.id), appearance: appearance)
  }

  /// R-S7: a passage can still be selected, but not highlighted or asked about.
  @Test(arguments: Snapshot.Appearance.allCases)
  func offlineSelection(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    try await Self.shoot(
      "offline-selection", try Self.machines(studio: .offline, studioLibrary: true), current: FakeMachines.studio,
      at: LibrarySnapshots.reading(library.article.id),
      standIns: StandIns(selection: "NGINX hands each request to a single worker process"),
      appearance: appearance, shows: { !($0.childWindows ?? []).isEmpty })
  }

  /// R-S12: Loci's page is the other Mac's Loci, readable offline, with nothing on it that would change it.
  @Test(arguments: Snapshot.Appearance.allCases)
  func offlineLoci(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "offline-loci", try Self.machines(studio: .offline), current: FakeMachines.studio,
      at: WindowState(place: .loci), appearance: appearance)
  }

  /// R-S7: the library reads as before; downloading, retrying and adding wait for the Mac.
  @Test(arguments: Snapshot.Appearance.allCases)
  func offlineLibrary(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "offline-library", try Self.machines(studio: .offline, studioLibrary: true), current: FakeMachines.studio,
      appearance: appearance)
  }

  /// R-S3: a pasted invite link pairing with the Mac that made it, which can be given up.
  @Test(arguments: Snapshot.Appearance.allCases)
  func joining(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "joining", try Self.machines(alone: true, acceptWaits: true), sheet: .joining(FakeMachines.invite),
      appearance: appearance)
  }

  /// R-S7: the main conversation of the other Mac, with one line where the field was.
  @Test(arguments: Snapshot.Appearance.allCases)
  func offlineTalk(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "offline-talk", try Self.machines(studio: .offline), current: FakeMachines.studio, at: WindowState(),
      appearance: appearance, english: true)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func settings(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "settings", try Self.machines(), at: WindowState(place: .settings(.remote)),
      standIns: StandIns(pointerOnFirstPairedMac: true), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func settingsWithNonePaired(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "settings-empty", try Self.machines(alone: true), at: WindowState(place: .settings(.remote)),
      appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func addMac(appearance: Snapshot.Appearance) async throws {
    let nearby = [FakeMachines.nearby("iMac", .iMac, key: 4), FakeMachines.nearby("MacBook Air", .laptop, key: 5)]
    try await Self.shoot(
      "add", try Self.machines(alone: true, nearby: nearby), sheet: .adding, appearance: appearance)
  }

  /// R-S2 on the Mac asked: the code, and the answer.
  @Test(arguments: Snapshot.Appearance.allCases)
  func approve(appearance: Snapshot.Appearance) async throws {
    let request = PairingRequest(id: EntityID(), from: FakeMachines.iMac, code: FakeMachines.code)
    try await Self.shoot(
      "approve", try Self.machines(alone: true, requests: [request]), appearance: appearance)
  }

  /// R-S2 on the Mac asking: the same code, waiting.
  @Test(arguments: Snapshot.Appearance.allCases)
  func wait(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "wait", try Self.machines(alone: true), sheet: .pairing(FakeMachines.nearby("MacBook Pro", .laptop, key: 1)),
      appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func invite(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("invite", try Self.machines(alone: true), sheet: .inviting, appearance: appearance)
  }
}
