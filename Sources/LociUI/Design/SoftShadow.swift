import SwiftUI

/// A soft shadow under a shape, drawn as a few faint copies of the shape, each a little larger, rather than with
/// `shadow(_:)`. A shadow filter is a blur of everything it covers, done away from the screen on every frame;
/// a gallery of covers with one each, under glass buttons and a floating dock, is redrawn through a dozen blurs
/// each time, and drawing the window without the graphics card, as a snapshot does, takes seconds.
struct SoftShadow<S: InsettableShape>: View {
  let shape: S
  var color = Color.black
  /// How dark it is under the shape itself.
  let opacity: Double
  /// How far past the shape's edge it fades out.
  let radius: CGFloat
  var y: CGFloat = 0

  static var steps: Int { 8 }

  var body: some View {
    ZStack {
      ForEach(1...Self.steps, id: \.self) { step in
        shape.inset(by: -radius * CGFloat(step) / CGFloat(Self.steps))
          .fill(color.opacity(opacity / Double(Self.steps)))
      }
    }
    .offset(y: y)
    .allowsHitTesting(false)
  }
}
