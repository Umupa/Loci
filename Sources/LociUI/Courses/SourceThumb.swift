import SwiftUI

/// A source's small picture, drawn by its kind: a paper is a page of type, a video a dark still with a play
/// button, a repository braces on GitHub's dark, a web page a blue panel with lines of text.
struct SourceThumb: View {
  let kind: SourceShown.Kind
  var height: CGFloat = 80

  var body: some View {
    let scale = height / 80
    let shape = RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
    Group {
      switch kind {
      case .paper:
        VStack(alignment: .leading, spacing: 4 * scale) {
          Capsule().fill(Palette.leafInk.opacity(0.55)).frame(width: 34 * scale, height: 4 * scale)
            .padding(.bottom, 3 * scale)
          ForEach(0..<6, id: \.self) { line in
            Capsule().fill(Palette.leafInk.opacity(0.18))
              .frame(width: line == 5 ? 26 * scale : 44 * scale, height: 2.5 * scale)
          }
        }
        .padding(.top, 9 * scale).padding(.leading, 7 * scale)
        .frame(width: 58 * scale, height: height, alignment: .topLeading)
        .background(Palette.leaf)
        .overlay { shape.strokeBorder(.black.opacity(0.12), lineWidth: Size.hairline) }
      case .video:
        LinearGradient(
          colors: [Palette.SourceThumb.video, Palette.SourceThumb.videoDeep], startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .overlay {
          Circle().fill(.white.opacity(0.16)).frame(width: 30 * scale, height: 30 * scale)
            .overlay {
              Image(systemName: Symbols.play).font(.system(size: 11 * scale)).foregroundStyle(.white.opacity(0.92))
                .offset(x: 1.2 * scale)
            }
        }
        .frame(width: height, height: height)
      case .repository:
        Palette.Site.github
          .overlay {
            Text(verbatim: "{ }").font(.system(size: 22 * scale, weight: .semibold).monospaced())
              .foregroundStyle(.white.opacity(0.9))
          }
          .frame(width: 58 * scale, height: height)
      case .page:
        LinearGradient(
          colors: [Palette.SourceThumb.page, Palette.SourceThumb.pageDeep], startPoint: .top, endPoint: .bottom
        )
        .overlay(alignment: .bottomLeading) {
          VStack(alignment: .leading, spacing: 4 * scale) {
            ForEach([1.0, 0.7, 0.85], id: \.self) { share in
              Capsule().fill(.white.opacity(0.55)).frame(width: 40 * scale * share, height: 2.5 * scale)
            }
          }
          .padding(.horizontal, 8 * scale).padding(.bottom, 10 * scale)
        }
        .frame(width: 58 * scale, height: height)
      }
    }
    .clipShape(shape)
    .accessibilityHidden(true)
  }
}
