import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// Every screen in light and dark, for looking at. Each test also checks that something was drawn.
@MainActor
@Suite(.serialized)
struct ScreenSnapshots {
  static func shoot(
    _ name: String, _ view: some View, appearance: Snapshot.Appearance, english: Bool = false
  ) async throws {
    let file = try await Snapshot.render(
      view, named: name, appearance: appearance, locale: Locale(identifier: english ? "en" : "zh-Hans"))
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  static func root(_ sample: Sample, at window: WindowState) -> some View {
    RootView(memory: WindowMemory(recall: { window }, remember: { _ in })).lociHost(FakeHost(sample))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func start(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot("start", Self.root(try Sample(problems: false), at: WindowState()), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func startInEnglish(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "start-en", Self.root(try Sample(problems: false), at: WindowState()), appearance: appearance, english: true)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func promptStates(appearance: Snapshot.Appearance) async throws {
    let fields = VStack(spacing: Spacing.l) {
      PromptField(text: .constant(""), submit: {})
      PromptField(text: .constant("我想搞懂 Kubernetes 的调度器"), submit: {})
      PromptField(text: .constant("https://research.google/pubs/borg/"), submit: {})
    }
    .padding(Spacing.xxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
    try await Self.shoot("prompt-states", fields, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func mentorWithCatalog(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample()
    try await Self.shoot(
      "mentor-catalog", Self.root(sample, at: WindowState(place: .mentor(sample.scheduling.id))),
      appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func mentorJustMade(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample(problems: false)
    try await Self.shoot(
      "mentor-empty", Self.root(sample, at: WindowState(place: .mentor(sample.sandbox.id))), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func lessonWithSources(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample(problems: false)
    let window = WindowState(place: .mentor(sample.scheduling.id), pages: [.lesson(sample.filterLesson)])
    try await Self.shoot("lesson", Self.root(sample, at: window), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func library(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "library", Self.root(try Sample(problems: false), at: WindowState(place: .library(nil))), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func libraryInEnglish(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "library-en", Self.root(try Sample(problems: false), at: WindowState(place: .library(nil))),
      appearance: appearance, english: true)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func itemCitedByALesson(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample(problems: false)
    let window = WindowState(place: .library(nil), pages: [.item(sample.borg.id)])
    try await Self.shoot("item", Self.root(sample, at: window), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func problems(appearance: Snapshot.Appearance) async throws {
    let list = ProblemList(health: try Sample().health).background(Palette.raised)
    try await Self.shoot("problems", list, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func damagedDatabase(appearance: Snapshot.Appearance) async throws {
    let view = StartupProblemView(problem: .database(.databaseUnreadable("file is not a database")), rebuild: {})
    try await Self.shoot("startup-unreadable", view, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func settings(appearance: Snapshot.Appearance) async throws {
    let view = SettingsView(folder: URL(filePath: "/Users/someone/Loci Dev"), version: "1.0.0-alpha")
    try await Self.shoot("settings", view, appearance: appearance)
  }
}
