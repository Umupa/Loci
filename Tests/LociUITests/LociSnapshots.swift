import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// Loci's face, its page and the main conversation, in light and dark.
@MainActor
@Suite(.serialized, .onStage)
struct LociSnapshots {
  @Test(arguments: Snapshot.Appearance.allCases)
  func avatars(appearance: Snapshot.Appearance) async throws {
    let sizes: [CGFloat] = [20, 26, 30, 36]
    let row = HStack(alignment: .center, spacing: Spacing.xl) {
      ForEach(sizes, id: \.self) { LociAvatar(size: $0) }
      LociAvatar(size: 168, framing: .portrait)
    }
    let view = VStack(spacing: Spacing.xl) {
      row
      row.environment(\.lociFace, .picture(Self.picture))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
    try await ScreenSnapshots.shoot("loci-avatar", view, appearance: appearance, size: CGSize(width: 640, height: 480))
  }

  /// A picture the person might choose: a plain gradient, so it is plainly not the drawing.
  static let picture = NSImage(size: NSSize(width: 200, height: 160), flipped: false) { rect in
    NSGradient(starting: .systemTeal, ending: .systemIndigo)?.draw(in: rect, angle: 45)
    return true
  }

  static func avatar(_ name: String) throws -> Avatar {
    try Avatar(data: try #require(SampleLibrary.picture(name)), format: "jpg")
  }

  /// UI-S: the sidebar with Loci at its top, working, and the main conversation the design draws.
  @Test(arguments: Snapshot.Appearance.allCases)
  func talk(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot("talk", try SampleLibrary(), at: WindowState(), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func talkWhileLociWorks(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "talk-working", try SampleLibrary(), at: WindowState(), appearance: appearance, working: true)
  }

  /// H-S1, H-S2: Loci at the top of the sidebar, chosen and not, idle and at each kind of work.
  @Test(arguments: Snapshot.Appearance.allCases)
  func sidebarLoci(appearance: Snapshot.Appearance) async throws {
    let search = ToolActivity(
      id: "1", name: "web_search", kind: .search, subject: "CubeSandbox snapshot restore latency", output: "",
      state: .running)
    let states: [(chosen: Bool, work: LociWork?)] = [
      (true, nil), (false, nil), (true, .answering(nil)), (false, .answering(search)),
      (false, .refreshing(title: "沙箱雷达")), (false, .reviewing), (false, .saving), (false, .unspecified),
    ]
    let view = VStack(alignment: .leading, spacing: Spacing.m) {
      ForEach(states.indices, id: \.self) { index in
        SidebarLoci(chosen: states[index].chosen, work: states[index].work) {}
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, Spacing.l)
    .frame(width: 240)
    .background(Palette.sidebarWash)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
    try await ScreenSnapshots.shoot("sidebar-loci", view, appearance: appearance, size: CGSize(width: 480, height: 560))
  }

  /// H-S4: a link from the main conversation open over it.
  @Test(arguments: Snapshot.Appearance.allCases)
  func linkOverTheConversation(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "talk-web-overlay", try SampleLibrary(), at: WindowState(), appearance: appearance,
      standIns: StandIns(
        webPage: LibrarySnapshots.webPage("article", appearance),
        overlayPage: URL(string: "https://blog.cloudflare.com/how-we-built-pingora")))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func talkInEnglish(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "talk-en", try SampleLibrary(), at: WindowState(), appearance: appearance, english: true)
  }

  /// UI-S: a face the person chose shows in the sidebar and beside every message.
  @Test(arguments: Snapshot.Appearance.allCases)
  func talkWithTheirOwnFace(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "talk-own-face", try SampleLibrary(), at: WindowState(), appearance: appearance,
      avatar: try Self.avatar("late"))
  }

  @Test(arguments: [LociTab.soul, .memory, .diary], Snapshot.Appearance.allCases)
  func lociPage(tab: LociTab, appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    let view = HStack(spacing: 0) { LociScreen(tab: tab) }
      .lociHost(FakeHost(try Sample(problems: false), library: library))
    try await ScreenSnapshots.shoot(
      "loci-\(tab)", view, appearance: appearance, size: CGSize(width: 1036, height: 800))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func lociPageInTheWindow(appearance: Snapshot.Appearance) async throws {
    try await LibrarySnapshots.shoot(
      "loci", try SampleLibrary(), at: WindowState(place: .loci), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func talkPieces(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    let pieces = VStack(alignment: .leading, spacing: Size.messageGap) {
      DayDivider(label: Text(verbatim: "今天 09:12"))
      BubbleRow(speaker: .loci) { ReplyText(text: "早", streaming: false, size: 15) }
      BubbleRow(speaker: .loci) { ReplyText(text: "图画好了，挂在 Pingora 第二条划线旁边", streaming: false, size: 15) }
      DoingLine(doing: .reading("Pingora 第二条划线"))
      DoingLine(doing: .working)
      QuickReplyChips(replies: ["好，存进去", "先不用"]) { _ in }
      LatestButton {}.padding(.leading, 40)
    }
    .padding(28)
    .frame(width: TalkLayout.standard.conversationWidth)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Palette.canvas)
    .environment(\.standIns, StandIns(conversationAt: Date(timeIntervalSince1970: 5)))
    .lociHost(FakeHost(try Sample(problems: false), library: library))
    try await ScreenSnapshots.shoot(
      "talk-pieces", pieces, appearance: appearance, size: CGSize(width: 760, height: 640))
  }
}
