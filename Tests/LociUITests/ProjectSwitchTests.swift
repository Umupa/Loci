import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// PJ-S2: going between the chat and a project shows each as it was left, without making either again.
@MainActor
@Suite(.onStage(alone: true))
struct ProjectSwitchTests {
  private static let size = CGSize(width: 1400, height: 860)
  private static let investingSeal = CGPoint(x: 662, y: 31)
  private static let chatTab = CGPoint(x: 590, y: 31)

  @Test func goingBackAndForthBetweenTheChatAndAProjectMakesNeitherPageAgain() async throws {
    let activity = Activity()
    let (window, host) = try Self.show(activity)
    defer { window.orderOut(nil) }
    try await eventually("the chat to appear", within: .seconds(5)) {
      (Self.conversations(in: host).first?.documentView?.bounds.height ?? 0) > 2000
    }

    try Self.click(Self.investingSeal, in: window)
    try await eventually("the project to open over the chat", within: .seconds(5)) {
      Self.conversations(in: host).count == 2
    }
    for seal in [Self.chatTab, Self.investingSeal, Self.chatTab] {
      try await Task.sleep(for: .milliseconds(500))
      try Self.click(seal, in: window)
    }

    try await Task.sleep(for: .milliseconds(300))
    #expect(Self.conversations(in: host).count == 2)
    #expect(activity.watches(of: OneConversation(.main)) == 1)
    #expect(activity.watches(of: OneConversation(Home.project(ProjectSnapshots.investing.id).conversation)) == 1)
  }

  @Test func twoFingersAcrossTheTrackpadTurnFromTheChatToTheProjectBesideIt() async throws {
    @MainActor final class Remembered { var projects: [Project.ID?] = [] }
    let remembered = Remembered()
    let (window, host) = try Self.show(Activity()) { remembered.projects.append($0) }
    defer { window.orderOut(nil) }
    try await eventually("the chat to appear", within: .seconds(5)) {
      (Self.conversations(in: host).first?.documentView?.bounds.height ?? 0) > 2000
    }

    try await Self.swipe(toward: .left, in: window)
    try await eventually("the project to open", within: .seconds(3)) {
      remembered.projects.last == ProjectSnapshots.investing.id
    }

    try await Task.sleep(for: .milliseconds(600))
    try await Self.swipe(toward: .left, in: window, steps: 1)
    try await Task.sleep(for: .milliseconds(600))
    #expect(remembered.projects.last == ProjectSnapshots.investing.id)
  }

  @Test func aScrollUpTheChatIsNotTakenForASwipe() async throws {
    @MainActor final class Remembered { var projects: [Project.ID?] = [] }
    let remembered = Remembered()
    let (window, host) = try Self.show(Activity()) { remembered.projects.append($0) }
    defer { window.orderOut(nil) }
    try await eventually("the chat to appear", within: .seconds(5)) {
      (Self.conversations(in: host).first?.documentView?.bounds.height ?? 0) > 2000
    }

    try await Self.swipe(toward: .left, in: window, upward: 3)
    try await Task.sleep(for: .milliseconds(600))
    #expect(remembered.projects.allSatisfy { $0 == nil })
  }

  @Test func theProjectBarYieldsNameWidthSmoothlyBeforeFoldingOverflowIntoTheList() {
    let projects = (1...8).map { index in
      Project(
        id: ProjectSnapshots.id(index), name: index == 8 ? "系统设计深度精读与架构实践" : "项目 \(index)",
        createdAt: Timestamp(millisecondsSince1970: Int64(index)))
    }
    let last = projects[7]
    let wide = ProjectBarPlan.compute(
      projects: projects, home: .project(last.id), drafting: false, availableWidth: 720, chatLabel: "聊天")
    #expect(wide.visible.count == 8)
    #expect(wide.hidden.isEmpty)
    #expect(wide.openNameWidth > Size.projectNameNarrow)

    let squeezed = ProjectBarPlan.compute(
      projects: projects, home: .project(last.id), drafting: false, availableWidth: 500, chatLabel: "聊天")
    #expect(squeezed.visible.count == 8)
    #expect(squeezed.openNameWidth < wide.openNameWidth)
    #expect(squeezed.openNameWidth >= Size.projectNameNarrow)

    let folded = ProjectBarPlan.compute(
      projects: projects, home: .project(last.id), drafting: false, availableWidth: 320, chatLabel: "聊天")
    #expect(folded.visible.count < 8)
    #expect(folded.visible.contains { $0.id == last.id })
    #expect(folded.hidden.count == 8 - folded.visible.count)
  }

  @Test func anOpenProjectWithoutANameKeepsJustItsSealInTheBar() {
    let unnamed = Project(id: ProjectSnapshots.id(5), name: nil, createdAt: Timestamp(millisecondsSince1970: 5))
    let projects = [ProjectSnapshots.investing, ProjectSnapshots.trip, unnamed]

    let plan = ProjectBarPlan.compute(
      projects: projects, home: .project(unnamed.id), drafting: false, availableWidth: 720, chatLabel: "聊天")

    #expect(plan.visible.map(\.id) == projects.map(\.id))
    #expect(plan.openNameWidth == 0)
  }

  @Test func aNewProjectsBlankSealTakesASlotOfItsOwn() {
    let projects = (1...8).map { index in
      Project(id: ProjectSnapshots.id(index), name: "项目 \(index)", createdAt: Timestamp(millisecondsSince1970: 1))
    }

    let shown = ProjectBarPlan.compute(
      projects: projects, home: .chat, drafting: false, availableWidth: 400, chatLabel: "聊天")
    let drafting = ProjectBarPlan.compute(
      projects: projects, home: .chat, drafting: true, availableWidth: 400, chatLabel: "聊天")

    #expect(drafting.visible.count == shown.visible.count - 1)
  }

  @Test func aNewProjectsSealWearsWhatItsWordsSuggestUnlessASymbolWasChosen() {
    var draft = NewProjectDraft()
    #expect(draft.symbol == nil)

    draft.text = "hello"
    #expect(draft.symbol == nil)

    draft.text = "下个月去东京旅行"
    #expect(draft.symbol == "airplane")

    draft.chosenIcon = "leaf"
    #expect(draft.symbol == "leaf")
  }

  private static func show(
    _ activity: Activity, remember: @escaping @MainActor @Sendable (Project.ID?) -> Void = { _ in }
  ) throws -> (NSWindow, NSView) {
    let projects = ProjectSnapshots.self
    var clock: Int64 = 1_763_400_000_000
    let said = (1...40).flatMap { question in
      [
        Message.Body.prompt(Prompt(text: "问题 \(question)", purpose: .chat)),
        .reply(String(repeating: "这是第 \(question) 个回答里的一句话。", count: 12)),
      ]
    }.map { body in
      clock += 1000
      return Message(id: EntityID(), at: Timestamp(millisecondsSince1970: clock), body: body)
    }
    let fake = FakeHost(
      try Sample(problems: false), panels: PanelColumn(slots: [.panel(projects.rules)]), activity: activity,
      projects: projects.bar, projectPanels: [projects.investing.id: PanelColumn(slots: [.panel(projects.holdings)])],
      chat: Conversation(ref: .main, entries: said.map { .message($0) }, turn: nil))
    let memory = WindowMemory(
      recall: { WindowState() }, remember: { _ in }, recallProject: { nil }, rememberProject: remember)
    let host = NSHostingView(
      rootView: CompanionPage(
        focusRequest: 0, attach: {}, opened: { _ in }, failed: { _ in }, columnPreferred: .constant(true),
        memory: memory, visits: ConversationVisits()
      )
      .frame(width: size.width, height: size.height)
      .background(Palette.canvas)
      .lociHost(fake)
      .defaultAppStorage(PanelSnapshots.defaults(columnShown: true, sidebarShown: false, layout: nil)))
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderBack(nil)
    return (window, host)
  }

  /// The conversations made on the page, the chat's first; one kept under a project is still made.
  private static func conversations(in view: NSView) -> [NSScrollView] {
    if let scroll = view as? NSScrollView { return scroll.bounds.width >= 450 ? [scroll] : [] }
    return view.subviews.flatMap(conversations(in:))
  }

  /// Two fingers across the middle of the window toward `side`, `upward` times as far up as across.
  private static func swipe(toward side: Side, in window: NSWindow, steps: Int = 12, upward: CGFloat = 0) async throws {
    let content = try #require(window.contentView)
    let area = try #require(swipeArea(in: content))
    let middle = CGPoint(x: window.frame.width / 2, y: window.frame.height / 2)
    let across: CGFloat = side == .left ? -30 : 30
    let phases = [SwipeTracker.Step.began] + Array(repeating: .changed, count: steps) + [.ended]
    for (index, step) in phases.enumerated() {
      let moving = step != .ended
      _ = area.take(
        step, across: moving ? across : 0, upward: moving ? upward * 30 : 0, at: Double(index) * 0.012, in: middle)
      try await Task.sleep(for: .milliseconds(12))
    }
  }

  private static func swipeArea(in view: NSView) -> SwipeArea? {
    if let area = view as? SwipeArea { return area }
    return view.subviews.lazy.compactMap(swipeArea(in:)).first
  }

  private static func click(_ point: CGPoint, in window: NSWindow) throws {
    let host = try #require(window.contentView)
    let location = host.convert(
      NSPoint(x: point.x, y: host.isFlipped ? point.y : host.bounds.height - point.y), to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      let event = try #require(
        NSEvent.mouseEvent(
          with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
      window.sendEvent(event)
    }
  }
}
