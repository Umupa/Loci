import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// UI-S26: the sidebar's button stays on the row of the window's close, minimize and zoom buttons however short
/// the window is.
@MainActor
@Suite(.serialized, .onStage)
struct SidebarFitTests {
  @Test(arguments: Snapshot.Appearance.allCases)
  func theSidebarButtonStaysInTheShortestWindow(appearance: Snapshot.Appearance) async throws {
    let view = MachineWindow(memory: WindowMemory(recall: { WindowState() }, remember: { _ in }))
      .lociHost(FakeHost(try Sample(problems: false)))
      .defaultAppStorage(LibrarySnapshots.defaults(panel: true))
    let file = try await Snapshot.render(
      view, named: "sidebar-shortest", size: Size.windowMinimum, appearance: appearance, settle: .seconds(1))
    let bitmap = try #require(NSBitmapImageRep(data: try Data(contentsOf: file)))

    let right = Spacing.xs + PaneWidth.sidebar.ideal - Spacing.xs
    let button = CGRect(
      x: right - Size.iconButton, y: Spacing.xs, width: Size.iconButton, height: Size.trafficLights)
    #expect(Self.inked(in: button, of: bitmap, appearance: appearance) > 20)
  }

  /// How many pixels in `rect`, in points from the top left, differ by more than `threshold` in brightness from
  /// what is just left of it.
  static func inked(
    in rect: CGRect, of bitmap: NSBitmapImageRep, appearance: Snapshot.Appearance, threshold: CGFloat = 0.2
  ) -> Int {
    let wash = bitmap.colorAt(x: Int(rect.minX * 2) - 20, y: Int(rect.midY * 2))?.brightnessComponent ?? 0
    var count = 0
    for y in Int(rect.minY * 2)..<Int(rect.maxY * 2) {
      for x in Int(rect.minX * 2)..<Int(rect.maxX * 2) {
        guard let color = bitmap.colorAt(x: x, y: y) else { continue }
        if abs(color.brightnessComponent - wash) > threshold { count += 1 }
      }
    }
    return count
  }
}
