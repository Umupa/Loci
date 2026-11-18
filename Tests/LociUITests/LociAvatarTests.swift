import AppKit
import CoreGraphics
import Testing

@testable import LociUI

@MainActor
struct LociAvatarTests {
  @Test func aSmallAvatarShowsTheFaceCroppedAsTheDesignDoes() {
    let frame = LociAvatar.frame(of: .face, in: 68)
    #expect(frame == CGRect(x: -26, y: -22, width: 120, height: 120))
  }

  @Test func aPortraitShowsTheWholeDrawing() {
    #expect(LociAvatar.frame(of: .portrait, in: 168) == CGRect(x: 0, y: 0, width: 168, height: 168))
  }

  @Test func theDrawingShipsWithTheApp() {
    #expect(LociFace.drawing != nil)
  }
}
