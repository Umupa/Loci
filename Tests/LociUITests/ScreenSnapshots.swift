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
    _ name: String, _ view: some View, appearance: Snapshot.Appearance, english: Bool = false,
    size: CGSize = Snapshot.windowSize
  ) async throws {
    let file = try await Snapshot.render(
      view, named: name, size: size, appearance: appearance, locale: Locale(identifier: english ? "en" : "zh-Hans"))
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
  func notesPanel(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample(problems: false)
    let text = ReadingText(markdown: sample.lessonText)
    let panel = ReaderPanel(
      content: .lesson(sample.filterLesson), headings: text.headings, notes: PlacedNote.place(sample.notes, in: text),
      pending: [
        PendingAnswer(
          note: sample.notes[0].id, mentor: sample.scheduling.id, question: "可行性检查会看哪些约束？",
          askedAt: Timestamp(millisecondsSince1970: 1_763_338_000_000), answer: "资源、端口、亲和性", failure: nil)
      ], tab: .constant(.notes), focusedNote: nil, reveal: { _ in }, extra: { EmptyView() }
    )
    .lociHost(FakeHost(sample))
    try await Self.shoot("notes-panel", panel, appearance: appearance, size: CGSize(width: 320, height: 640))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func conversation(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample(problems: false)
    let view = ConversationView(
      mentor: sample.scheduling, conversation: try sample.conversation(),
      send: { (_: String) async throws(HostError) -> Done in Done() }, stop: {}, answer: { _, _ in })
    try await Self.shoot("conversation", view, appearance: appearance)
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

extension ScreenSnapshots {
  @Test(arguments: Snapshot.Appearance.allCases)
  func agentSettings(appearance: Snapshot.Appearance) async throws {
    let view = AgentSettings().lociHost(FakeHost(try Sample()))
    try await Self.shoot("settings-agents", view, appearance: appearance, size: CGSize(width: 520, height: 720))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func mentorSettings(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample()
    let view = MentorSettings(mentor: sample.scheduling) { _ in }.lociHost(FakeHost(sample))
    try await Self.shoot("mentor-settings", view, appearance: appearance, size: CGSize(width: 520, height: 300))
  }
}
