import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// ME-S7: the Memory page, the index beside a sheet, in ink and gray.
@MainActor
@Suite(.serialized, .onStage)
struct MemoryTabTests {
  @Test func aPageReadsItsTitleAndItsLinesAndLinksToAnother() throws {
    let page = try SampleLibrary().wikiPage("raft")

    #expect(page.title == "Raft")
    #expect(page.lines.count == 4)
    guard case .entry(let last) = page.lines.last else { throw HostError.notFound("entry") }
    #expect(last.page == WikiLink(name: "sandboxes", title: "沙箱学习"))
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func memoryPageWithAPageOpen(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-memory", appearance: appearance, opened: "raft")
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func memoryPageForgettingALine(appearance: Snapshot.Appearance) async throws {
    try await shoot(
      "loci-memory-forget", appearance: appearance, opened: "raft", pointed: "- 不抠代码细节；要原理、取舍、数量级")
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func memoryPageWithTodaysNotes(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-memory-today", appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func memoryPageEmpty(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-memory-empty", appearance: appearance, remembers: false)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func memoryPageNarrow(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-memory-narrow", appearance: appearance, opened: "raft", width: 620)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func memoryPageInEnglish(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-memory-en", appearance: appearance, english: true)
  }

  private func shoot(
    _ name: String, appearance: Snapshot.Appearance, opened: String? = nil, pointed: String? = nil,
    remembers: Bool = true, english: Bool = false, width: CGFloat = 1036
  ) async throws {
    let library = try SampleLibrary()
    let view = HStack(spacing: 0) { LociScreen(tab: .memory, wikiPage: opened) }
      .lociHost(FakeHost(try Sample(problems: false), library: library, remembers: remembers))
      .environment(\.pointedMemoryLine, pointed)
    try await ScreenSnapshots.shoot(
      name, view, appearance: appearance, english: english, size: CGSize(width: width, height: 1000))
  }
}
