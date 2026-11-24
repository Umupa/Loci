import LociModel
import SwiftUI

/// The cover of a book that brought none: its title in the serif and its authors, on paper.
struct BookPaperCover: View {
  let item: Item

  var body: some View {
    GeometryReader { frame in
      let short = min(frame.size.width, frame.size.height)
      VStack(spacing: short * 0.06) {
        Text(serif: item.title, Serif.Face(size: max(9, short * 0.13), weight: .semibold))
          .foregroundStyle(Palette.paperInk)
          .multilineTextAlignment(.center)
          .lineLimit(3)
          .minimumScaleFactor(0.6)
        if short >= 100, !item.authors.isEmpty {
          Rectangle().fill(Palette.paperInk.opacity(0.4)).frame(width: short * 0.12, height: 1)
          Text(verbatim: item.authors.joined(separator: " "))
            .font(.system(size: short * 0.065))
            .foregroundStyle(Palette.paperInkMuted)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, short * 0.12)
      .frame(width: frame.size.width, height: frame.size.height)
    }
    .background(LinearGradient(colors: [Palette.paper, Palette.paperFoot], startPoint: .top, endPoint: .bottom))
    .accessibilityHidden(true)
  }
}
