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

  static let wide = CGSize(width: 1240, height: 800)

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
    try await Self.shoot(
      "lesson", Self.root(sample, at: WindowState(place: .lesson(sample.filterLesson))), appearance: appearance,
      size: Self.wide)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func highlightsPanel(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample(problems: false)
    let text = ReadingText(markdown: sample.lessonText)
    let notes = PlacedNote.place(sample.notes, in: text)
    let panel = ReaderPanel(
      content: .lesson(sample.filterLesson), mentor: sample.scheduling, conversation: nil, notes: notes,
      tab: .constant(.highlights), draft: .constant(nil), chosen: ChosenNote(note: notes[1].id, serial: 1),
      reveal: { _ in }, revealPassage: { _ in }, ask: { _ in }, collapse: {}, extra: { EmptyView() }
    )
    .lociHost(FakeHost(sample))
    try await Self.shoot("highlights-panel", panel, appearance: appearance, size: CGSize(width: 384, height: 640))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func selectionBar(appearance: Snapshot.Appearance) async throws {
    let actions = PassageActions(highlight: { _ in nil }, think: { _, _ in }, ask: { _ in })
    let bar = PassageBar(actions: actions, range: NSRange(), typing: {}, done: {})
      .padding(Spacing.xl)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Palette.canvas)
    try await Self.shoot("selection-bar", bar, appearance: appearance, size: CGSize(width: 320, height: 120))
  }

  /// UI-S6, UI-S8: a passage question answered and saved, a reply streaming, a passage waiting to be asked.
  @Test(arguments: Snapshot.Appearance.allCases)
  func conversation(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample(problems: false)
    let draft = PassageDraft(
      content: .lesson(sample.filterLesson), locator: sample.notes[0].locator, excerpt: "约束是硬的，偏好是软的。")
    let mentor = try Mentor(
      id: sample.scheduling.id, name: sample.scheduling.name, avatar: sample.scheduling.avatar,
      color: sample.scheduling.color, provider: .claudeCode, model: "opus", effort: .high)
    let view = ConversationView(
      mentor: mentor, conversation: try sample.conversation(), draft: .constant(draft), revealPassage: { _ in },
      send: { (_: String, _: Passage?) async throws(HostError) -> Done in Done() }, stop: {}
    )
    .lociHost(FakeHost(sample))
    try await Self.shoot("conversation", view, appearance: appearance, size: CGSize(width: 384, height: 900))
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
    try await Self.shoot("item", Self.root(sample, at: window), appearance: appearance, size: Self.wide)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func problems(appearance: Snapshot.Appearance) async throws {
    let list = ProblemList(health: try Sample().health).background(Palette.well)
    try await Self.shoot("problems", list, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func damagedDatabase(appearance: Snapshot.Appearance) async throws {
    let view = StartupProblemView(problem: .database(.databaseUnreadable("file is not a database")), rebuild: {})
    try await Self.shoot("startup-unreadable", view, appearance: appearance)
  }

  /// UI-S10.
  @Test(arguments: Snapshot.Appearance.allCases)
  func generalSettings(appearance: Snapshot.Appearance) async throws {
    let view = GeneralSettingsPage().lociHost(FakeHost(try Sample()))
    try await Self.shoot("settings-general", view, appearance: appearance, size: CGSize(width: 800, height: 600))
  }

  /// UI-S10.
  @Test(arguments: Snapshot.Appearance.allCases)
  func agentSettings(appearance: Snapshot.Appearance) async throws {
    let view = AgentSettingsPage().lociHost(FakeHost(try Sample()))
    try await Self.shoot("settings-agents", view, appearance: appearance, size: CGSize(width: 800, height: 820))
  }

  /// UI-S9: the mentor working, its course on the shelf, its memory and its soul.
  @Test(arguments: Snapshot.Appearance.allCases)
  func mentorPage(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample()
    let view = NavigationStack { MentorScreen(mentor: sample.scheduling.id) }.lociHost(FakeHost(sample))
    try await Self.shoot("mentor-page", view, appearance: appearance, size: CGSize(width: 800, height: 1000))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func mentorSoul(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample()
    let view = SoulSheet(soul: sample.mind.soul, file: sample.mind.soulFile, color: sample.scheduling.color)
      .padding(Spacing.xl).background(Palette.canvas)
    try await Self.shoot("mentor-soul", view, appearance: appearance, size: CGSize(width: 720, height: 560))
  }
}
