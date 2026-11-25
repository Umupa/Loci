import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// NX-S1, NX-S6, NX-S8, NX-S9: the deck over the chat's panels with every project's cards, a project's deck
/// with only its own, and an approval card waiting and done.
@MainActor
@Suite(.serialized, .onStage)
struct NextUpSnapshots {
  static let at = Timestamp(millisecondsSince1970: 1_764_504_000_000)

  static func card(_ seed: Int, in home: Home, _ kind: NextUp.Kind, _ what: String, state: NextUp.State = .new)
    -> NextUp
  {
    NextUp(
      id: ProjectSnapshots.id(seed + 4), home: home, key: "\(seed)", kind: kind, what: what, state: state,
      shownAt: Timestamp(millisecondsSince1970: at.millisecondsSince1970 - Int64(seed) * 60_000))
  }

  static let investing = Home.project(ProjectSnapshots.investing.id)
  static let review = Approval.event(EventDraft(title: "投资复盘", start: at))

  static var cards: [NextUp] {
    [
      card(1, in: investing, .ask(question: "这对我意味着什么"), "费城半导体跌 8%，纳指 QDII 今天承压"),
      card(2, in: .project(ProjectSnapshots.trip.id), .ask(question: "行程要重算吗"), "JR Pass 12 月起涨价，行程要重算吗"),
      card(3, in: .chat, .ask(question: "要现在转吗"), "周五房租到期，还没转"),
      card(4, in: investing, .approval(review), "每周日晚上复盘一次"),
    ]
  }

  static func window(project: Project.ID?, appearance: Snapshot.Appearance, named name: String) async throws {
    let chat = PanelColumn(slots: [.pinned(ProjectSnapshots.investing.id, ProjectSnapshots.holdings)])
    let projectColumn = PanelColumn(slots: [.panel(ProjectSnapshots.holdings), .panel(ProjectSnapshots.rules)])
    let host = FakeHost(
      try Sample(problems: false), panels: chat, projects: ProjectSnapshots.bar,
      projectPanels: [ProjectSnapshots.investing.id: projectColumn], nextUps: cards)
    let memory = WindowMemory(
      recall: { WindowState() }, remember: { _ in }, recallProject: { project }, rememberProject: { _ in })
    let view = MachineWindow(memory: memory)
      .lociHost(host)
      .defaultAppStorage(PanelSnapshots.defaults(columnShown: true, sidebarShown: true, layout: nil))
    let file = try await Snapshot.render(
      view, named: name, size: CGSize(width: 1280, height: 760), appearance: appearance, settle: .seconds(1))
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  /// NX-S1: over the chat's panels, the top card with its project's seal, two more tucked under it.
  @Test(arguments: Snapshot.Appearance.allCases)
  func overTheChat(appearance: Snapshot.Appearance) async throws {
    try await Self.window(project: nil, appearance: appearance, named: "nextup-chat")
  }

  /// NX-S8: a project's deck has only its own cards.
  @Test(arguments: Snapshot.Appearance.allCases)
  func overAProject(appearance: Snapshot.Appearance) async throws {
    try await Self.window(project: ProjectSnapshots.investing.id, appearance: appearance, named: "nextup-project")
  }

  /// NX-S1, NX-S6: the deck laid out: a question, an approval waiting with its amber light, one done.
  @Test(arguments: Snapshot.Appearance.allCases)
  func laidOut(appearance: Snapshot.Appearance) async throws {
    let cards =
      Self.cards + [
        Self.card(
          5, in: .chat, .approval(.reminder(ReminderDraft(title: "交房租", due: Self.at))), "周五前交房租",
          state: .approved(Approved(identifier: "x")))
      ]
    let projects = Dictionary(
      uniqueKeysWithValues: ProjectSnapshots.bar.projects.map { ($0.id, $0) })
    let actions = NextUpActions(start: { _ in }, set: { _, _ in }, approve: { _ in }, undo: { _ in })
    let view = NextUpDeck(state: NextUpDeckState(cards: cards, projects: projects, actions: actions), spread: true)
      .frame(width: 340)
      .padding(Spacing.l)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(Palette.canvas)
      .lociHost(FakeHost(try Sample(problems: false)))
    try await Snapshot.render(view, named: "nextup-deck", size: CGSize(width: 440, height: 680), appearance: appearance)
  }
}
