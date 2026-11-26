import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// PJ-S2: going from the chat to a project and back shows the chat as it was left, without making it again.
@MainActor
@Suite(.onStage(alone: true))
struct ProjectSwitchTests {
  private static let size = CGSize(width: 1400, height: 860)
  private static let investingSeal = CGPoint(x: 675, y: 31)
  private static let chatTab = CGPoint(x: 588, y: 31)

  @Test func goingBackToTheChatFromAProjectKeepsTheChatAsItWas() async throws {
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
    try await Task.sleep(for: .seconds(1))
    try Self.click(Self.chatTab, in: window)
    try await eventually("the project to close", within: .seconds(5)) {
      Self.conversations(in: host).count == 1
    }

    try await Task.sleep(for: .milliseconds(300))
    #expect(activity.watches(of: OneConversation(.main)) == 1)
  }

  private static func show(_ activity: Activity) throws -> (NSWindow, NSView) {
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
      recall: { WindowState() }, remember: { _ in }, recallProject: { nil }, rememberProject: { _ in })
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
