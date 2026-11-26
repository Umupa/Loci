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

  static func card(
    _ seed: Int, in home: Home, _ kind: NextUp.Kind, _ what: String, execution: NextUp.Execution = .waiting
  )
    -> NextUp
  {
    NextUp(
      id: EntityID(canonical: "019a8b3e-0000-7000-8000-0000000001\(seed / 10)\(seed % 10)")!, home: home,
      key: "\(seed)", kind: kind, what: what, execution: execution,
      shownAt: Timestamp(millisecondsSince1970: at.millisecondsSince1970 - Int64(seed) * 60_000))
  }

  static let investing = Home.project(ProjectSnapshots.investing.id)
  static let review = Approval.event(EventDraft(title: "投资复盘", start: at, calendar: "家庭"))

  static var cards: [NextUp] {
    [
      card(1, in: investing, .ask(question: "这对我意味着什么"), "费城半导体跌 8%，纳指 QDII 今天承压"),
      card(2, in: .project(ProjectSnapshots.trip.id), .ask(question: "行程要重算吗"), "JR Pass 12 月起涨价，行程要重算吗"),
      card(3, in: .chat, .ask(question: "要现在转吗"), "周五房租到期，还没转"),
      card(4, in: investing, .approval(review), "每周日晚上复盘一次"),
    ]
  }

  static func window(
    project: Project.ID?, appearance: Snapshot.Appearance, named name: String, cards: [NextUp] = cards,
    projectColumn: PanelColumn = PanelColumn(slots: [.panel(ProjectSnapshots.holdings), .panel(ProjectSnapshots.rules)]
    ),
    size: CGSize = CGSize(width: 1280, height: 760)
  ) async throws {
    let chat = PanelColumn(slots: [.pinned(ProjectSnapshots.investing.id, ProjectSnapshots.holdings)])
    let host = FakeHost(
      try Sample(problems: false), panels: chat, projects: ProjectSnapshots.bar,
      projectPanels: [ProjectSnapshots.investing.id: projectColumn], nextUps: cards)
    let memory = WindowMemory(
      recall: { WindowState() }, remember: { _ in }, recallProject: { project }, rememberProject: { _ in })
    let view = MachineWindow(memory: memory)
      .lociHost(host)
      .defaultAppStorage(PanelSnapshots.defaults(columnShown: true, sidebarShown: true, layout: nil))
    let file = try await Snapshot.render(view, named: name, size: size, appearance: appearance, settle: .seconds(1))
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

  /// NX-S1, NX-S8: the narrowest window folds the panel lane, and the cards wait behind a mark on it, also in a
  /// project with an approval card and no panels yet.
  @Test(arguments: Snapshot.Appearance.allCases)
  func inANarrowWindow(appearance: Snapshot.Appearance) async throws {
    try await Self.window(
      project: ProjectSnapshots.investing.id, appearance: appearance, named: "nextup-narrow",
      cards: [Self.card(4, in: Self.investing, .approval(Self.review), "每周日晚上复盘一次")],
      projectColumn: PanelColumn(slots: []), size: CGSize(width: 720, height: 560))
  }

  /// NX-S1, NX-S8: the chat in the narrowest window, panels shown: the cards wait behind the mark on the folded
  /// lane.
  @Test(arguments: Snapshot.Appearance.allCases)
  func overTheChatInANarrowWindow(appearance: Snapshot.Appearance) async throws {
    try await Self.window(
      project: nil, appearance: appearance, named: "nextup-chat-narrow", size: CGSize(width: 720, height: 560))
  }

  /// NX-S1, NX-S6: the deck laid out: a question, an approval waiting with its amber light, one done.
  @Test(arguments: Snapshot.Appearance.allCases)
  func laidOut(appearance: Snapshot.Appearance) async throws {
    let cards =
      Self.cards + [
        Self.card(
          5, in: .chat, .approval(.reminder(ReminderDraft(title: "交房租", due: Self.at))), "周五前交房租",
          execution: .made(
            Approved(identifier: "x", marker: "m", into: ApprovalTarget(id: "l", name: "提醒", source: "iCloud")))),
        Self.card(
          7, in: .chat, .approval(.event(EventDraft(title: "家长会", start: Self.at, calendar: "家庭"))), "周四家长会",
          execution: .choosing([
            ApprovalTarget(id: "c-1", name: "家庭", source: "iCloud"),
            ApprovalTarget(id: "c-2", name: "家庭", source: "Google"),
          ])),
        Self.card(
          6, in: Self.investing, .approval(.event(EventDraft(title: "组会", start: Self.at, calendar: "工作"))), "每周组会",
          execution: .targetGone("工作")),
      ]
    let projects = Dictionary(
      uniqueKeysWithValues: ProjectSnapshots.bar.projects.map { ($0.id, $0) })
    let actions = NextUpActions(start: { _ in }, set: { _, _ in }, approve: { _, _ in }, undo: { _, _ in })
    let view = NextUpDeck(state: NextUpDeckState(cards: cards, projects: projects, actions: actions), spread: true)
      .frame(width: 340)
      .padding(Spacing.l)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(Palette.canvas)
      .lociHost(FakeHost(try Sample(problems: false)))
    try await Snapshot.render(view, named: "nextup-deck", size: CGSize(width: 440, height: 840), appearance: appearance)
  }

  /// NX-S6: in a narrow column, where an event over two days goes is read whole before it is confirmed, however
  /// long the account, and so is each list of one name.
  @Test(arguments: Snapshot.Appearance.allCases)
  func confirmingWhereItGoesInANarrowColumn(appearance: Snapshot.Appearance) async throws {
    let end = Timestamp(millisecondsSince1970: Self.at.millisecondsSince1970 + 2 * 86_400_000 + 5_400_000)
    let trip = Approval.event(EventDraft(title: "东京五日行前会", start: Self.at, end: end, calendar: "家庭旅行计划"))
    let account = "umupa.family.shared.calendar@icloud.com"
    let rent = Approval.reminder(ReminderDraft(title: "交房租", due: Self.at, list: "家里的事"))
    let cards = [
      Self.card(
        1, in: .chat, .approval(trip), "行前会",
        execution: .choosing([ApprovalTarget(id: "c-1", name: "家庭旅行计划", source: account)])),
      Self.card(
        2, in: .chat, .approval(rent), "周五房租",
        execution: .choosing([
          ApprovalTarget(id: "l-1", name: "家里的事", source: account),
          ApprovalTarget(id: "l-2", name: "家里的事", source: "Exchange · 公司邮箱"),
        ])),
    ]
    let actions = NextUpActions(start: { _ in }, set: { _, _ in }, approve: { _, _ in }, undo: { _, _ in })
    let view = NextUpDeck(state: NextUpDeckState(cards: cards, projects: [:], actions: actions), spread: true)
      .frame(width: 260)
      .padding(Spacing.l)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(Palette.canvas)
      .lociHost(FakeHost(try Sample(problems: false)))
    try await Snapshot.render(
      view, named: "nextup-confirm", size: CGSize(width: 340, height: 620), appearance: appearance)
  }

  /// NX-S6, NX-S8: in a narrow window the cards open from the mark in a sheet as tall as they are, so an event
  /// over two days shows its confirm button whole.
  @Test(arguments: Snapshot.Appearance.allCases)
  func confirmingFromTheMarkInANarrowWindow(appearance: Snapshot.Appearance) async throws {
    let start = Timestamp(millisecondsSince1970: Self.at.millisecondsSince1970 + 13_800_000)
    let end = Timestamp(millisecondsSince1970: start.millisecondsSince1970 + 1_800_000)
    let check = Approval.event(EventDraft(title: "R4 跨日核验 星河", start: start, end: end, calendar: "Loci 黑盒"))
    let cards = [
      Self.card(
        1, in: Self.investing, .approval(check), "跨日核验",
        execution: .choosing([ApprovalTarget(id: "c-1", name: "Loci 黑盒", source: "iCloud")]))
    ]
    let projects = Dictionary(uniqueKeysWithValues: ProjectSnapshots.bar.projects.map { ($0.id, $0) })
    let actions = NextUpActions(start: { _ in }, set: { _, _ in }, approve: { _, _ in }, undo: { _, _ in })
    let view = RailDeckSheet(deck: NextUpDeckState(cards: cards, projects: projects, actions: actions))
      .background(Palette.surface)
      .overlay(Rectangle().strokeBorder(Palette.lineStrong, lineWidth: 1))
      .padding(Spacing.l)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(Palette.canvas)
      .lociHost(FakeHost(try Sample(problems: false)))
    try await Snapshot.render(
      view, named: "nextup-rail-confirm", size: CGSize(width: 440, height: 420), appearance: appearance)
  }
}
