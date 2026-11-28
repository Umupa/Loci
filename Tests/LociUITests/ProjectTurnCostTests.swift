import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// PJ-S16: turning between the chat and a project in the whole window leaves the main thread free for most of
/// the slide. It measures time, so it runs with the full check, not the fast one.
@MainActor
@Suite(.onStage(alone: true))
struct ProjectTurnCostTests {
  private static let size = CGSize(width: 1400, height: 860)
  private static let chatTab = CGPoint(x: 590, y: 31)
  private static let investingSeal = CGPoint(x: 672, y: 31)

  @Test func turningBetweenTheChatAndAProjectLeavesTheMainThreadMostlyFree() async throws {
    @MainActor final class Remembered { var projects: [Project.ID?] = [] }
    let remembered = Remembered()
    let window = try Self.show { remembered.projects.append($0) }
    defer { window.orderOut(nil) }
    try await eventually("the chat to appear", within: .seconds(20)) {
      (window.contentView.map(Self.conversations(in:))?.first?.documentView?.bounds.height ?? 0) > 2000
    }
    for (seal, home) in [(Self.investingSeal, ProjectSnapshots.investing.id), (Self.chatTab, nil)] {
      try Self.click(seal, in: window)
      try await eventually("the bar to open what was clicked", within: .seconds(10)) {
        remembered.projects.last == .some(home)
      }
      try await Task.sleep(for: .milliseconds(1200))
    }

    var costs: [Double] = []
    for seal in [Self.investingSeal, Self.chatTab, Self.investingSeal, Self.chatTab, Self.investingSeal, Self.chatTab] {
      let before = Self.mainCPU()
      try Self.click(seal, in: window)
      try await Task.sleep(for: .milliseconds(1100))
      costs.append(Self.mainCPU() - before)
    }

    let median = costs.sorted()[costs.count / 2]
    #expect(median < Self.budget, "a turn kept the main thread busy for \(Int(median)) ms: \(costs.map(Int.init))")
  }

  /// The most main-thread time, in milliseconds, one turn and its slide may take in a debug build.
  private static let budget: Double = 600

  /// The whole window over a long chat and a project with a panel, the sidebar folded.
  private static func show(remember: @escaping @MainActor @Sendable (Project.ID?) -> Void) throws -> NSWindow {
    let said = (1...40).flatMap { question in
      [
        Message.Body.prompt(Prompt(text: "问题 \(question)", purpose: .chat)),
        .reply(String(repeating: "这是第 \(question) 个回答里的一句话。", count: 12)),
      ]
    }.enumerated().map { index, body in
      Message(
        id: EntityID(), at: Timestamp(millisecondsSince1970: 1_763_400_000_000 + Int64(index) * 1000), body: body)
    }
    let host = FakeHost(
      try Sample(problems: false), panels: PanelColumn(slots: [.panel(ProjectSnapshots.rules)]),
      projects: ProjectSnapshots.bar,
      projectPanels: [ProjectSnapshots.investing.id: PanelColumn(slots: [.panel(ProjectSnapshots.holdings)])],
      chat: Conversation(ref: .main, entries: said.map { .message($0) }, turn: nil))
    let memory = WindowMemory(
      recall: { WindowState() }, remember: { _ in }, recallProject: { nil }, rememberProject: remember)
    let view = MachineWindow(memory: memory)
      .lociHost(host)
      .defaultAppStorage(PanelSnapshots.defaults(columnShown: true, sidebarShown: false, layout: nil))
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.titled, .resizable],
      backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: view)
    window.setContentSize(size)
    window.orderBack(nil)
    return window
  }

  /// The conversations made in the window, the chat's first.
  private static func conversations(in view: NSView) -> [NSScrollView] {
    if let scroll = view as? NSScrollView { return scroll.bounds.width >= 450 ? [scroll] : [] }
    return view.subviews.flatMap(conversations(in:))
  }

  /// Time the main thread has spent working so far, in milliseconds.
  private static func mainCPU() -> Double {
    var time = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
    return Double(time.tv_sec) * 1000 + Double(time.tv_nsec) / 1_000_000
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
