import SwiftUI

/// The faint line where Loci's reply will be, saying what it is doing, with a light passing over it. A new
/// thing to do rises in place of the last.
struct DoingLine: View {
  let doing: Doing
  var size: CGFloat = 15
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    ZStack(alignment: .leading) {
      Text(doing.words)
        .font(.system(size: size))
        .foregroundStyle(Palette.ink.opacity(Self.faint))
        .overlay { if !reduceMotion { Sheen().mask { Text(doing.words).font(.system(size: size)) } } }
        .id(doing)
        .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
    }
    .animation(reduceMotion ? nil : Motion.swap, value: doing)
    .lineLimit(1)
    .truncationMode(.tail)
    .padding(.vertical, 14.5)
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  static let faint = 0.3
}

/// A band of light crossing from left to right, again and again.
private struct Sheen: View {
  @State private var crossed = false

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0), .init(color: Palette.ink.opacity(0.85), location: 0.5),
          .init(color: .clear, location: 1),
        ],
        startPoint: .leading, endPoint: .trailing
      )
      .frame(width: width * 0.6)
      .offset(x: crossed ? width : -width * 0.6)
    }
    .onAppear {
      withAnimation(Motion.sheen) { crossed = true }
    }
  }
}
