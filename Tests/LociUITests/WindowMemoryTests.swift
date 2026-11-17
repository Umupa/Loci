import Foundation
import LociModel
import SwiftUI
import Synchronization
import Testing

@testable import LociUI

/// α1-S4: after quitting, Loci reopens where it was, without the system's window restoration.
@MainActor
struct WindowMemoryTests {
  @Test func aPlaceRememberedByOneLaunchIsRecalledByTheNext() throws {
    let suite = "loci-window-memory-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let sample = try Sample()
    let window = WindowState(place: .mentor(sample.scheduling.id), pages: [.lesson(sample.filterLesson)])

    WindowMemory.preferences(defaults).remember(window)
    let nextLaunch = WindowMemory.preferences(try #require(UserDefaults(suiteName: suite)))

    #expect(nextLaunch.recall() == window)
  }

  @Test func withNothingRememberedTheWindowOpensAtStart() throws {
    let suite = "loci-window-memory-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(WindowMemory.preferences(defaults).recall() == WindowState())
  }

  @Test func theWindowOpensWhereItWasAndKeepsTheMemoryCurrent() async throws {
    let sample = try Sample()
    let last = WindowState(place: .library(nil), pages: [.item(sample.borg.id)])
    let remembered = Mutex<[WindowState]>([])
    let memory = WindowMemory(recall: { last }, remember: { state in remembered.withLock { $0.append(state) } })

    try await Snapshot.render(
      RootView(memory: memory).lociHost(FakeHost(sample)), named: "reopened", appearance: .light)

    #expect(remembered.withLock { $0 } == [last])
  }

  @Test func aRememberedMentorThatWasDeletedOpensAtStart() async throws {
    let sample = try Sample()
    let gone = WindowState(place: .mentor(EntityID()))
    let remembered = Mutex<[WindowState]>([])
    let memory = WindowMemory(recall: { gone }, remember: { state in remembered.withLock { $0.append(state) } })

    try await Snapshot.render(
      RootView(memory: memory).lociHost(FakeHost(sample)), named: "reopened-deleted", appearance: .light)

    #expect(remembered.withLock { $0.last } == WindowState())
  }
}
