import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// Loci's face, its page and the main conversation, in light and dark.
@MainActor
@Suite(.serialized)
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

  /// The pieces of the main conversation the sample does not reach: a task card part way, one stopped, and a
  /// card marked to start with.
  @Test(arguments: Snapshot.Appearance.allCases)
  func talkPieces(appearance: Snapshot.Appearance) async throws {
    let library = try SampleLibrary()
    let video = library.video
    let pieces = VStack(alignment: .leading, spacing: 0) {
      DayDivider(label: Text(verbatim: "今天 09:12"))
      BubbleRow(speaker: .loci, position: .first, turn: false, scale: .main) { ReplyText(text: "早", streaming: false) }
      BubbleRow(speaker: .loci, position: .last, turn: false, scale: .main) {
        ReplyText(text: "图画好了，挂在 Pingora 第二条划线旁边", streaming: false)
      }
      StepsCard.working(since: Timestamp(millisecondsSince1970: 0)).padding(.leading, TalkScale.main.indent)
      LatestButton {}.padding(.leading, 40)
      SavingCard(
        item: video, job: LociModel.Job(item: video.id, stage: .translate, state: .running(progress: nil)), indent: 40)
      SavingCard(
        item: library.article,
        job: LociModel.Job(
          item: library.article.id, stage: .resolve, state: .failed(Job.Failure(reason: "403", cause: .network))),
        indent: 40)
      ItemCardRow {
        ItemCard(title: video.title, source: video.site, duration: Text(verbatim: "34:12"), first: true) {
          Palette.coverBackdrop
        }
      }
    }
    .padding(28)
    .frame(width: 640)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Palette.canvas)
    .environment(\.standIns, StandIns(conversationAt: Date(timeIntervalSince1970: 5)))
    .lociHost(FakeHost(try Sample(problems: false), library: library))
    try await ScreenSnapshots.shoot(
      "talk-pieces", pieces, appearance: appearance, size: CGSize(width: 760, height: 640))
  }
}
