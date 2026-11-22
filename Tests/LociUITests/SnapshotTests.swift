import AppKit
import SwiftUI
import Testing

@MainActor
@Suite(.onStage)
struct SnapshotTests {
  @Observable final class Arrival {
    var shown = false
  }

  @Test(arguments: [false, true])
  func theFirstFrameAfterAnArrivalShowsTheCompletedTransition(explicit: Bool) async throws {
    let arrival = Arrival()
    let animation = Animation.linear(duration: 30)
    let file = try await Snapshot.render(
      Square(arrival: arrival, animation: explicit ? nil : animation),
      named: explicit ? "snapshot-explicit-transition" : "snapshot-implicit-transition",
      size: CGSize(width: 40, height: 40), appearance: .light
    ) { window in
      guard let content = window.contentView else { return false }
      if arrival.shown { return true }
      content.layoutSubtreeIfNeeded()
      _ = try? Snapshot.bitmap(of: content)
      withAnimation(explicit ? animation : nil) { arrival.shown = true }
      return false
    }

    let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: file)))
    let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
    let gray = try #require(center.usingColorSpace(.genericGray))
    #expect(gray.whiteComponent > 0.95)
  }

  private struct Square: View {
    let arrival: Arrival
    let animation: Animation?

    var body: some View {
      ZStack {
        Color.black
        if arrival.shown { Color.white.transition(.opacity) }
      }
      .animation(animation, value: arrival.shown)
    }
  }
}
