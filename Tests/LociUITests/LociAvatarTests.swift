import AppKit
import Testing

@testable import LociUI

@MainActor
struct LociAvatarTests {
  @Test func theDefaultFaceIsSquareAndSharpAtPortraitSize() throws {
    let drawing = try #require(LociFace.drawing)
    #expect(
      drawing.representations.contains { $0.pixelsWide == $0.pixelsHigh && $0.pixelsWide >= Int(Portrait.side * 2) })
  }
}
