import Foundation
import LociModel
import SwiftUI
import Synchronization
import Testing

@testable import LociUI

/// α1-S4: after quitting, Loci reopens where it was, without the system's window restoration.
@MainActor
struct WindowMemoryTests {
  static let folder = URL(filePath: "/Users/someone/Loci Dev")

  @Test func aPlaceRememberedByOneLaunchIsRecalledByTheNext() throws {
    let suite = "loci-window-memory-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let sample = try Sample()
    let window = WindowState(place: .mentor(sample.scheduling.id), pages: [.lesson(sample.filterLesson)])

    WindowMemory.preferences(defaults, folder: Self.folder).remember(window)
    let nextLaunch = WindowMemory.preferences(try #require(UserDefaults(suiteName: suite)), folder: Self.folder)

    #expect(nextLaunch.recall() == window)
  }

  @Test func withNothingRememberedTheWindowOpensAtStart() throws {
    let suite = "loci-window-memory-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(WindowMemory.preferences(defaults, folder: Self.folder).recall() == WindowState())
  }

  /// α1-S1: a data folder opened for the first time starts at the start page, whatever another folder left.
  @Test func aNewDataFolderOpensAtStartWhateverAnotherFolderRemembers() throws {
    let suite = "loci-window-memory-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    WindowMemory.preferences(defaults, folder: Self.folder).remember(WindowState(place: .library(nil)))
    let other = WindowMemory.preferences(defaults, folder: URL(filePath: "/tmp/loci-blackbox-empty"))

    #expect(other.recall() == WindowState())
    #expect(WindowMemory.preferences(defaults, folder: Self.folder).recall() == WindowState(place: .library(nil)))
  }

  /// R-S4: each Mac keeps its own last place, so switching back to one returns to where it was.
  @Test func eachMacRemembersItsOwnPlace() throws {
    let suite = "loci-window-memory-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let sample = try Sample()
    let here = WindowState(place: .mentor(sample.scheduling.id))
    let studio = WindowState(place: .library(nil), pages: [.item(sample.borg.id)])

    WindowMemory.preferences(defaults, folder: Self.folder).remember(here)
    WindowMemory.preferences(defaults, remote: "studio").remember(studio)

    #expect(WindowMemory.preferences(defaults, folder: Self.folder).recall() == here)
    #expect(WindowMemory.preferences(defaults, remote: "studio").recall() == studio)
    #expect(WindowMemory.preferences(defaults, remote: "mini").recall() == WindowState())
  }

  @Test func theWindowOpensWhereItWasAndKeepsTheMemoryCurrent() async throws {
    let sample = try Sample()
    let last = WindowState(place: .library(nil), pages: [.item(sample.borg.id)])
    let remembered = Mutex<[WindowState]>([])
    let memory = WindowMemory(recall: { last }, remember: { state in remembered.withLock { $0.append(state) } })

    let host = FakeHost(sample)
    let quiet = Quiet(host.activity)
    try await Snapshot.render(
      MachineWindow(memory: memory).lociHost(host), named: "reopened", appearance: .light,
      until: { _ in quiet.settled() && !remembered.withLock { $0.isEmpty } })

    #expect(remembered.withLock { $0 } == [last])
  }

  @Test func aRememberedMentorThatWasDeletedOpensAtStart() async throws {
    let sample = try Sample()
    let gone = WindowState(place: .mentor(EntityID()))
    let remembered = Mutex<[WindowState]>([])
    let memory = WindowMemory(recall: { gone }, remember: { state in remembered.withLock { $0.append(state) } })

    try await Snapshot.render(
      MachineWindow(memory: memory).lociHost(FakeHost(sample)), named: "reopened-deleted", appearance: .light,
      until: { _ in remembered.withLock { $0.last } == WindowState() })

    #expect(remembered.withLock { $0.last } == WindowState())
  }
}
