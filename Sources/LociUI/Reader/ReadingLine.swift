import SwiftUI

/// A thin amber line along the top of the text, as long as the share of it read.
struct ReadingLine: View {
  let share: Double

  var body: some View {
    GeometryReader { frame in
      Rectangle().fill(Palette.accent)
        .frame(width: frame.size.width * min(max(share, 0), 1), height: 2)
        .animation(.linear(duration: 0.2), value: share)
    }
    .frame(height: 2)
    .allowsHitTesting(false)
  }
}
