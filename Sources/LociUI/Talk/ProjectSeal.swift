import LociModel
import SwiftUI

/// A project's seal: the first character of its name in the serif, ink on a rounded square. A project kept out
/// of memory carries a small lock; a project being started is a dashed outline.
struct ProjectSeal: View {
  let seal: String
  var size: CGFloat = Size.seal
  var locked = false
  var ghost = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
    Text(serif: seal, Serif.Face(size: size * 0.54, weight: .semibold))
      .foregroundStyle(Palette.canvas)
      .frame(width: size, height: size)
      .background(shape.fill(ghost ? Color.clear : Palette.ink))
      .overlay {
        if ghost { shape.strokeBorder(Palette.inkFaint, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])) }
      }
      .overlay(alignment: .bottomTrailing) {
        if locked {
          Image(systemName: "lock.fill")
            .font(.system(size: size * 0.26, weight: .bold))
            .foregroundStyle(Palette.inkMuted)
            .frame(width: size * 0.46, height: size * 0.46)
            .background(Circle().fill(Palette.canvas))
            .offset(x: size * 0.14, y: size * 0.14)
        }
      }
  }
}

extension Project {
  var shownName: String { name ?? "" }
}
