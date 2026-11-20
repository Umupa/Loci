import LociModel
import SwiftUI

/// The cover of an article or paper that has no picture: its title set in the serif on warm paper, a few lines
/// of text under it, and for a paper where it was published.
struct PaperCover: View {
  let item: Item

  var body: some View {
    GeometryReader { frame in
      let width = frame.size.width
      VStack(alignment: .leading, spacing: width * 0.04) {
        Text(serif: item.title, Serif.Face(size: max(width * 0.075, 11), weight: .bold))
          .foregroundStyle(Palette.paperInk)
          .lineLimit(3)
          .lineSpacing(-1)
          .padding(.bottom, width * 0.01)
        ForEach([0.9, 0.84, 0.88], id: \.self) { share in
          Capsule().fill(Palette.paperInk.opacity(0.16)).frame(
            width: width * 0.8 * share, height: max(width * 0.018, 2))
        }
        if item.kind == .paper, let site = item.site ?? item.source?.host() {
          Text(verbatim: site)
            .font(.system(size: max(width * 0.036, 8)).monospaced())
            .foregroundStyle(Palette.paperInk.opacity(0.55))
            .padding(.top, width * 0.02)
        }
      }
      .padding(.horizontal, width * 0.1)
      .padding(.vertical, width * 0.085)
      .frame(width: width, height: frame.size.height, alignment: .topLeading)
    }
    .background(LinearGradient(colors: [Palette.paper, Palette.paperFoot], startPoint: .top, endPoint: .bottom))
  }
}
