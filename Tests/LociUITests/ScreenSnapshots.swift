import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// Every screen in light and dark, for looking at. Each test also checks that something was drawn.
@MainActor
@Suite(.serialized, .onStage)
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
    MachineWindow(memory: WindowMemory(recall: { window }, remember: { _ in })).lociHost(FakeHost(sample))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func highlightsPanel(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample(problems: false)
    let text = ReadingText(markdown: sample.text)
    let notes = PlacedNote.place(sample.notes, in: text)
    let panel = ReaderPanel(
      item: sample.borg.id, notes: notes, keyPoints: nil, openKeyPoint: { _ in }, tab: .constant(.highlights),
      draft: .constant(nil),
      chosen: ChosenNote(note: notes[1].id, serial: 1), reveal: { _ in }, revealPassage: { _ in }, ask: { _ in },
      collapse: {}
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

  /// UI-S6, UI-S8, C-S9, C-S10: a passage question answered and saved, a reply streaming, a passage waiting
  /// to be asked.
  @Test(arguments: Snapshot.Appearance.allCases)
  func conversation(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample(problems: false)
    let draft = PassageDraft(
      content: .item(sample.borg.id), locator: sample.notes[0].locator, excerpt: sample.notes[0].excerpt ?? "")
    let view = ConversationView(
      conversation: try sample.conversation(), draft: .constant(draft), revealPassage: { _ in },
      send: { (_: String, _: Passage?) async throws(HostError) -> Done in Done() }, stop: {}, scale: .companion
    )
    .lociHost(FakeHost(sample))
    try await Self.shoot("conversation", view, appearance: appearance, size: CGSize(width: 384, height: 900))
  }

  /// UI-S11, UI-S13, UI-S14, C-S7, C-S9, C-S10: a display formula, a code block and an answer with their
  /// copy buttons, no trace of the tools, a line where the conversation started over, replies offered at
  /// the end, and the way back to the latest.
  @Test(arguments: Snapshot.Appearance.allCases)
  func chat(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample(problems: false)
    var away = Following()
    away.scrolled(to: 600)
    let view = ConversationView(
      conversation: try sample.chat(), draft: .constant(nil), revealPassage: { _ in },
      send: { (_: String, _: Passage?) async throws(HostError) -> Done in Done() }, stop: {}, attach: {}, follow: away
    )
    .environment(\.showsCopyButtons, true)
    .lociHost(FakeHost(sample))
    try await Self.shoot("chat", view, appearance: appearance, size: CGSize(width: 720, height: 1100))
  }

  /// C-S1: one faint line says what Loci is doing where its reply will be.
  @Test(arguments: Snapshot.Appearance.allCases)
  func chatWorking(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample(problems: false)
    let start = Timestamp(millisecondsSince1970: 1_763_400_000_000)
    let question = Message(
      id: EntityID(), at: start, body: .prompt(Prompt(text: "对比这两篇资料对连接池的解释。", purpose: .chat)))
    let thought = Message(
      id: EntityID(), at: Timestamp(millisecondsSince1970: start.millisecondsSince1970 + 2_000),
      body: .tool(
        ToolActivity(
          id: "pr", name: "commandExecution", kind: .execute,
          subject: "/bin/zsh -lc 'gh pr list -R tencentcloud/CubeSandbox'", output: "", state: .running)))
    let conversation = Conversation(
      ref: .main, entries: [], turn: LiveTurn(startedAt: start, messages: [question, thought]))
    var away = Following()
    away.scrolled(to: 600)
    let view = ConversationView(
      conversation: conversation, draft: .constant(nil), revealPassage: { _ in },
      send: { (_: String, _: Passage?) async throws(HostError) -> Done in Done() }, stop: {}, attach: {}, follow: away
    )
    .environment(\.standIns, StandIns(conversationAt: start.date.addingTimeInterval(5)))
    .lociHost(FakeHost(sample))
    try await Self.shoot("chat-working", view, appearance: appearance, size: CGSize(width: 720, height: 310))
  }

  /// UI-S19, C-S2: an agent that is not installed, one that is there but would not start, a turn that
  /// failed and one that was stopped, each a bubble from Loci, in both languages.
  @Test(arguments: Snapshot.Appearance.allCases)
  func agentUnavailable(appearance: Snapshot.Appearance) async throws {
    let endings: [TurnEnding] = [
      .unstarted(.codex, .notInstalled), .unstarted(.codex, .wouldNotStart), .failed("exit 1: panic"), .interrupted,
    ]
    let lines = VStack(spacing: ConversationView.gap) {
      ForEach(endings, id: \.self) { ending in
        BubbleRow(speaker: .loci) { EndedTurn(ending: ending) }
      }
    }
    .padding(Spacing.l)
    .frame(maxHeight: .infinity)
    .background(Palette.canvas)
    let size = CGSize(width: 520, height: 320)
    try await Self.shoot("agent-unavailable", lines, appearance: appearance, size: size)
    try await Self.shoot("agent-unavailable-en", lines, appearance: appearance, english: true, size: size)
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
  func item(appearance: Snapshot.Appearance) async throws {
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
    let view = GeneralSettingsPage(version: AppVersion(number: "1.1.0", build: "412")).lociHost(FakeHost(try Sample()))
    try await Self.shoot("settings-general", view, appearance: appearance, size: CGSize(width: 800, height: 600))
  }

  /// UI-S10.
  @Test(arguments: Snapshot.Appearance.allCases)
  func agentSettings(appearance: Snapshot.Appearance) async throws {
    let view = AgentSettingsPage().lociHost(FakeHost(try Sample()))
    try await Self.shoot("settings-agents", view, appearance: appearance, size: CGSize(width: 800, height: 820))
  }
}
