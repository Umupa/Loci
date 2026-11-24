import LociModel
import SwiftUI

/// The cover of an item without a picture: its site's initial in a ring of ink and the site's name, on ruled
/// paper. The title is not set on it, as the card or row around it already shows the title.
struct PaperCover: View {
  let item: Item

  var body: some View {
    GeometryReader { frame in
      let scale = min(frame.size.width, frame.size.height * 1.6)
      let short = min(frame.size.width, frame.size.height)
      let small = short < 100
      ZStack {
        if !small {
          Ruling(gap: scale * 0.075)
            .stroke(Palette.paperInk.opacity(0.06), lineWidth: 1)
            .mask(
              LinearGradient(
                stops: [
                  .init(color: .clear, location: 0.08), .init(color: .black, location: 0.3),
                  .init(color: .black, location: 0.75), .init(color: .clear, location: 0.95),
                ], startPoint: .top, endPoint: .bottom))
        }
        VStack(spacing: scale * 0.04) {
          seal(side: small ? short * 0.5 : scale * 0.2)
          if !small {
            Group {
              if let source = item.sourceName {
                Text(verbatim: source)
              } else {
                Text(.loci("link.files"))
              }
            }
            .font(.system(size: scale * 0.048, weight: .medium).monospaced())
            .foregroundStyle(Palette.paperInkMuted)
            .lineLimit(1)
            .padding(.horizontal, scale * 0.06)
          }
        }
      }
      .frame(width: frame.size.width, height: frame.size.height)
    }
    .background(LinearGradient(colors: [Palette.paper, Palette.paperFoot], startPoint: .top, endPoint: .bottom))
    .accessibilityHidden(true)
  }

  /// The site's first letter, or the item's kind where there is no site, in a ring with a fainter ring around it.
  private func seal(side: CGFloat) -> some View {
    SiteSeal(side: side) {
      if let initial = item.sourceName?.first {
        Text(serif: String(initial).uppercased(), Serif.Face(size: side * 0.5, weight: .semibold))
      } else {
        Image(systemName: Symbols.kind(ItemKind(item.kind))).font(.system(size: side * 0.4, weight: .medium))
      }
    }
    .padding(side * 0.1)
    .overlay(Circle().strokeBorder(Palette.paperInk.opacity(0.18), lineWidth: max(side * 0.015, 0.75)))
  }
}

/// Lines across, `gap` apart, as on writing paper.
private struct Ruling: Shape {
  let gap: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path()
    var y = rect.minY + gap
    while y < rect.maxY {
      path.move(to: CGPoint(x: rect.minX, y: y))
      path.addLine(to: CGPoint(x: rect.maxX, y: y))
      y += gap
    }
    return path
  }
}
