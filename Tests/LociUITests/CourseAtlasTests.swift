import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

@MainActor
struct CourseAtlasTests {
  @Test("Atlas text keeps its strong words and code apart from plain words, and an unclosed mark stays plain")
  func readsMarks() {
    let pieces = AtlasInline.pieces(of: "用 **KVM** 换隔离，`mmap` 就是内存，a*b 和 `x")
    #expect(pieces.map(\.0) == ["用 ", "KVM", " 换隔离，", "mmap", " 就是内存，a*b 和 `x"])
    #expect(pieces.map(\.1) == [.plain, .strong, .plain, .code, .plain])
  }

  @Test("CA-S4: a lesson opened whose part Loci is still adding shows as a frame in pencil")
  func showsLessonsBeingAdded() throws {
    let shown = try AtlasSamples.shown()
    #expect(shown.adding.map(\.id.description) == ["pause-fork-compare"])
    #expect(shown.lessons[try #require(Lesson.ID("virtio"))]?.mark == .read)
    #expect(shown.lessons[try #require(Lesson.ID("control-plane"))]?.mark == .planned)
  }

  @Test("CA-S1: the contents show the atlas row only for a course that has an atlas, lit while it is open")
  func atlasRowFollowsTheCourse() throws {
    let reading = try AtlasSamples.reading()
    #expect(reading.hasAtlas && reading.atlasOpen)
    #expect(!ReadingSamples.first().hasAtlas && !ReadingSamples.first().atlasOpen)
  }

}

/// The atlas page in light and dark.
@MainActor
@Suite(.serialized, .onStage)
struct CourseAtlasSnapshots {
  /// CA-S1, CA-S2: the course opens on its atlas, with the atlas row lit above the lessons.
  @Test(arguments: Snapshot.Appearance.allCases)
  func atlas(appearance: Snapshot.Appearance) async throws {
    try await CourseSnapshots.shoot(
      "course-atlas", ReadingStage(shown: AtlasSamples.reading(), panel: false), appearance: appearance,
      size: CourseSnapshots.wide)
  }

  /// CA-S2, CA-S4, CA-S5: every kind of block, the beads of their lessons, and a lesson still being added.
  @Test(arguments: Snapshot.Appearance.allCases)
  func wholeAtlas(appearance: Snapshot.Appearance) async throws {
    try await CourseSnapshots.shoot(
      "course-atlas-whole", AtlasPage(shown: try AtlasSamples.shown(), open: { _ in }), appearance: appearance,
      size: CGSize(width: 1100, height: 2600))
  }
}
