import SwiftUI

/// A course as a cloth-bound book: its cloth woven and shaded at the spine, a line drawing made from its title,
/// the title and subtitle in the serif, and a ribbon as long as how far it has been read. A book no one has
/// opened has no ribbon.
struct ClothBook: View {
  let title: String
  let subtitle: String
  /// How much has been read, from 0 to 1.
  let read: Double
  /// Whether the title is printed on it; too small a cover shows only its drawing.
  var lettered = true

  var body: some View {
    let design = BookDesign(title: title)
    GeometryReader { frame in
      let scale = frame.size.width / 220
      ZStack(alignment: .topLeading) {
        design.clothColor
        ClothWeave()
        RadialGradient(
          colors: [.white.opacity(0.13), .clear], center: UnitPoint(x: 0.8, y: 0), startRadius: 0,
          endRadius: frame.size.width * 1.1)
        MotifDrawing(motif: design.motif)
          .frame(width: frame.size.width * 0.6, height: frame.size.height * 0.46)
          .frame(width: frame.size.width - 16 * scale, height: frame.size.height * (lettered ? 0.58 : 0.62))
          .offset(x: 16 * scale)
        if lettered {
          lettering(scale: scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        Spine().frame(width: 16 * scale)
        if read > 0 {
          Ribbon()
            .frame(width: 12 * scale, height: max(frame.size.height * 0.78 * min(read, 1), 22 * scale))
            .offset(x: frame.size.width - 38 * scale, y: -2)
            .transition(.scale(scale: 0, anchor: .top))
        }
      }
      .animation(Motion.standard, value: read)
    }
    .aspectRatio(3 / 4, contentMode: .fit)
    .clipShape(Self.shape)
    .accessibilityElement()
    .accessibilityLabel(Text(verbatim: title))
  }

  private func lettering(scale: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 8 * scale) {
      Text(serif: title, Serif.Face(size: 21 * scale, weight: .semibold))
        .lineLimit(3)
        .lineSpacing(-1)
        .foregroundStyle(Palette.clothInk)
        .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
      if !subtitle.isEmpty {
        Text(serif: subtitle, Serif.Face(size: 12.5 * scale))
          .lineLimit(2)
          .lineSpacing(2)
          .foregroundStyle(Palette.clothInk.opacity(0.62))
      }
    }
    .multilineTextAlignment(.leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 14 * scale)
    .overlay(alignment: .top) { Rectangle().fill(Palette.clothInk.opacity(0.35)).frame(height: Size.hairline) }
    .padding(.leading, 30 * scale)
    .padding(.trailing, 18 * scale)
    .padding(.bottom, 22 * scale)
  }

  static let shape = UnevenRoundedRectangle(
    topLeadingRadius: Radius.bookSpine, bottomLeadingRadius: Radius.bookSpine, bottomTrailingRadius: Radius.bookEdge,
    topTrailingRadius: Radius.bookEdge, style: .continuous)
}

/// The weave of the cloth: fine threads both ways, lighter one way and darker the other.
struct ClothWeave: View {
  var body: some View {
    Canvas { context, size in
      var light = Path()
      var dark = Path()
      var x = -size.height
      while x < size.width {
        light.move(to: CGPoint(x: x, y: size.height))
        light.addLine(to: CGPoint(x: x + size.height, y: 0))
        dark.move(to: CGPoint(x: x, y: 0))
        dark.addLine(to: CGPoint(x: x + size.height, y: size.height))
        x += 3
      }
      context.stroke(light, with: .color(.white.opacity(0.035)), lineWidth: 1)
      context.stroke(dark, with: .color(.black.opacity(0.07)), lineWidth: 1)
    }
    .allowsHitTesting(false)
  }
}

/// The spine's hinge: shadow where the cover bends, a crease of light, and shadow again.
struct Spine: View {
  var body: some View {
    LinearGradient(
      stops: [
        .init(color: .black.opacity(0.36), location: 0), .init(color: .black.opacity(0.08), location: 0.55),
        .init(color: .white.opacity(0.11), location: 0.7), .init(color: .black.opacity(0.12), location: 1),
      ], startPoint: .leading, endPoint: .trailing
    )
    .allowsHitTesting(false)
  }
}

/// A bookmark ribbon hanging from the top edge, notched at its end.
struct Ribbon: View {
  var body: some View {
    RibbonShape()
      .fill(
        LinearGradient(
          colors: [Palette.ribbonEdge, Palette.ribbon, Palette.ribbonEdge], startPoint: .leading, endPoint: .trailing)
      )
      .shadow(color: .black.opacity(0.3), radius: 1.5, y: 2)
  }
}

private struct RibbonShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: rect.origin)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - min(6, rect.width * 0.5)))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}
