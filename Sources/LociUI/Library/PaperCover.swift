import LociModel
import SwiftUI

/// The item's kind, source and title set in ink on paper when it has no picture.
struct PaperCover: View {
  let item: Item

  var body: some View {
    GeometryReader { frame in
      let width = frame.size.width
      let scale = min(width, frame.size.height * 1.6)
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: scale * 0.032) {
          Image(systemName: Symbols.kind(ItemKind(item.kind)))
            .font(.system(size: scale * 0.062, weight: .medium))
          if let source = item.sourceName {
            Text(verbatim: source)
          } else {
            Text(.loci("link.files"))
          }
        }
        .font(.system(size: scale * 0.048, weight: .medium))
        .foregroundStyle(Palette.paperInkMuted)
        .lineLimit(1)
        Spacer(minLength: scale * 0.035)
        Text(serif: item.title, Serif.Face(size: scale * 0.097, weight: .semibold))
          .foregroundStyle(Palette.paperInk)
          .lineLimit(3)
          .lineSpacing(-scale * 0.005)
      }
      .padding(scale * 0.084)
      .frame(width: width, height: frame.size.height, alignment: .leading)
    }
    .background(LinearGradient(colors: [Palette.paper, Palette.paperFoot], startPoint: .top, endPoint: .bottom))
    .accessibilityHidden(true)
  }
}
