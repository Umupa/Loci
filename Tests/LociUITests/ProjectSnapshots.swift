import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// PJ-S1, PJ-S2, PJ-S3, PJ-S7, PJ-S9, PJ-S10, PJ-S12: the project bar over the chat and over a project, the
/// field a project starts from, and the list of every project.
@MainActor
@Suite(.serialized, .onStage)
struct ProjectSnapshots {
  static func id(_ seed: Int) -> EntityID {
    EntityID(canonical: "019a8b3e-0000-7000-8000-00000000000\(seed)")!
  }

  static let investing = Project(
    id: id(1), name: "投资", summary: "盯纳指和几只基金", pinned: ["holdings"], createdAt: Timestamp(millisecondsSince1970: 1))
  static let trip = Project(id: id(2), name: "东京五日", createdAt: Timestamp(millisecondsSince1970: 2))
  static let interview = Project(
    id: id(3), name: "AI Infra 面试", remembered: false, createdAt: Timestamp(millisecondsSince1970: 3))
  static let moving = Project(id: id(4), name: "搬家", archived: true, createdAt: Timestamp(millisecondsSince1970: 4))

  static let holdings = Panel(
    name: "holdings", title: "持仓", follow: "盯着我的几只基金",
    body: .rows([.sentence("今天 **−0.91%**，红利低波超配 2%。"), .cells([PanelCell(label: "纳指100", value: "−1.86%")])]))
  static let rules = Panel(
    name: "rules", title: "规矩", follow: "我的交易规矩",
    body: .rows([.sentence("每笔买前写好**止损价**。")]))

  static var bar: ProjectBar {
    ProjectBar(
      projects: [investing, trip, interview], archived: [moving], unseen: [trip.id],
      panels: [investing.id: [PanelName(name: "holdings", title: "持仓"), PanelName(name: "rules", title: "规矩")]])
  }

  static func window(project: Project.ID?, appearance: Snapshot.Appearance, named name: String) async throws {
    let chat = PanelColumn(slots: [.pinned(investing.id, holdings)])
    let projectColumn = PanelColumn(slots: [.panel(holdings), .panel(rules)])
    let host = FakeHost(
      try Sample(problems: false), panels: chat, projects: bar, projectPanels: [investing.id: projectColumn])
    let memory = WindowMemory(
      recall: { WindowState() }, remember: { _ in }, recallProject: { project }, rememberProject: { _ in })
    let view = MachineWindow(memory: memory)
      .lociHost(host)
      .defaultAppStorage(PanelSnapshots.defaults(columnShown: true, sidebarShown: true, layout: nil))
    let file = try await Snapshot.render(
      view, named: name, size: CGSize(width: 1280, height: 760), appearance: appearance, settle: .seconds(1))
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  /// PJ-S1, PJ-S7, PJ-S9, PJ-S12: the chat open, a dot on the project with news, a lock on the one kept out of
  /// memory, and the pinned panel in the chat's column.
  @Test(arguments: Snapshot.Appearance.allCases)
  func overTheChat(appearance: Snapshot.Appearance) async throws {
    try await Self.window(project: nil, appearance: appearance, named: "projects-chat")
  }

  /// PJ-S2: a project open, its name spread out, its own panels beside its conversation.
  @Test(arguments: Snapshot.Appearance.allCases)
  func overAProject(appearance: Snapshot.Appearance) async throws {
    try await Self.window(project: Self.investing.id, appearance: appearance, named: "projects-project")
  }

  /// PJ-S3: the field a project starts from, and the field risen over the skeletons once sent.
  @Test(arguments: Snapshot.Appearance.allCases)
  func starting(appearance: Snapshot.Appearance) async throws {
    for (name, sent) in [("projects-new", nil), ("projects-new-sent", "建一个投资项目，盯纳指和我的几只基金")] {
      let memory = WindowMemory(
        recall: { WindowState() }, remember: { _ in }, recallProject: { nil }, rememberProject: { _ in })
      let view = CompanionPage(
        focusRequest: 0, attach: {}, opened: { _ in }, failed: { _ in }, columnPreferred: .constant(true),
        memory: memory, visits: ConversationVisits(), opening: CompanionPage.Starting(sent: sent)
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(Palette.canvas)
      .lociHost(FakeHost(try Sample(problems: false), projects: Self.bar))
      .defaultAppStorage(PanelSnapshots.defaults(columnShown: true, sidebarShown: false, layout: nil))
      try await Snapshot.render(
        view, named: name, size: CGSize(width: 1000, height: 700), appearance: appearance, settle: .seconds(1))
    }
  }

  /// PJ-S8: a very long name stays on one line, cut short, and the corner buttons stay clear of the bar in the
  /// narrowest window; the field's prompt is one line too.
  @Test(arguments: Snapshot.Appearance.allCases)
  func aLongName(appearance: Snapshot.Appearance) async throws {
    let long = Project(
      id: Self.investing.id, name: "边界🌼" + String(repeating: "超长中文项目名🧪", count: 12), pinned: [],
      createdAt: Timestamp(millisecondsSince1970: 1))
    let bar = ProjectBar(projects: [long, Self.trip, Self.interview, Self.moving.with(archived: false)])
    let host = FakeHost(
      try Sample(problems: false), projects: bar,
      projectPanels: [long.id: PanelColumn(slots: [.panel(Self.rules)])])
    let memory = WindowMemory(
      recall: { WindowState() }, remember: { _ in }, recallProject: { long.id }, rememberProject: { _ in })
    let view = MachineWindow(memory: memory)
      .lociHost(host)
      .defaultAppStorage(PanelSnapshots.defaults(columnShown: true, sidebarShown: true, layout: nil))
    try await Snapshot.render(
      view, named: "projects-long-name", size: CGSize(width: 720, height: 560), appearance: appearance,
      settle: .seconds(1))
  }

  /// PJ-S10: every project, the open one marked, the archived ones folded at the bottom.
  @Test(arguments: Snapshot.Appearance.allCases)
  func list(appearance: Snapshot.Appearance) async throws {
    let view = ProjectList(bar: Self.bar, home: .project(Self.investing.id), open: { _ in }, start: {})
      .background(Palette.surface)
      .lociHost(FakeHost(try Sample(problems: false)))
    try await Snapshot.render(
      view, named: "projects-list", size: CGSize(width: 232, height: 260), appearance: appearance)
  }

  static let actions = ProjectBarActions(
    open: { _ in }, start: {}, rename: { _, _ in }, pin: { _, _, _ in }, remember: { _, _ in }, archive: { _ in },
    delete: { _ in })
}
