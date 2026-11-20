import LociModel
import SwiftUI

/// One key point in the list: the picture at that moment with its number on it (an article's has the number
/// alone), the title, why it is worth the reader's time, and where it is. The one playing is washed in amber,
/// with how far it has got along its foot.
struct KeyPointRow: View {
  let media: Item?
  let point: KeyPoint
  let number: Int
  /// How far through this one playback is; `nil` when it is not playing.
  let progress: Double?
  let frames: KeyPointFrames?
  let open: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: open) {
      HStack(alignment: .top, spacing: Spacing.s) {
        if let media, point.span != nil {
          thumbnail(media)
        } else {
          Text(verbatim: "\(number)")
            .font(.system(size: 12, weight: .bold).monospaced())
            .foregroundStyle(Palette.accentInk)
            .frame(width: 18, alignment: .leading)
            .padding(.top, 1)
        }
        VStack(alignment: .leading, spacing: 3) {
          Text(verbatim: point.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .lineLimit(2)
          Text(verbatim: point.reason)
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.inkMuted)
            .lineSpacing(1.5)
            .lineLimit(3)
          Text(verbatim: KeyPointWords.place(point))
            .font(.system(size: 11.5).monospaced())
            .foregroundStyle(progress != nil ? Palette.accentInk : Palette.inkFaint)
            .padding(.top, 1)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      .padding(Spacing.xs)
      .background(
        RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
          .fill(progress != nil ? Palette.tint : hovering ? Palette.fill : .clear)
      )
      .overlay(alignment: .bottom) {
        if let progress {
          GeometryReader { frame in
            Capsule().fill(Palette.accent.opacity(0.25))
              .overlay(alignment: .leading) {
                Capsule().fill(Palette.accent).frame(width: frame.size.width * min(max(progress, 0), 1))
              }
          }
          .frame(height: 2)
          .padding(.horizontal, Spacing.xs)
          .padding(.bottom, 2)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .accessibilityElement(children: .combine)
  }

  private func thumbnail(_ media: Item) -> some View {
    ZStack(alignment: .topLeading) {
      KeyPointPicture(item: media, at: point.span?.start, frames: frames)
        .frame(width: 104, height: 58.5)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(
            Palette.lineStrong, lineWidth: Size.hairline)
        )
      Text(verbatim: "\(number)")
        .font(.system(size: 11, weight: .bold).monospaced())
        .foregroundStyle(progress != nil ? Palette.onAccent : Palette.onCover)
        .frame(minWidth: 18, minHeight: 18)
        .background {
          if progress != nil {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.accent)
          } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.ultraThinMaterial)
              .environment(\.colorScheme, .dark)
              .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.coverShade.opacity(0.35)))
          }
        }
        .padding(5)
    }
  }
}

/// The picture at a key point's start: a frame of the video once it is drawn, and until then, or for audio, the
/// cover as a 16:9 card shows it, a square one whole over a blur of itself.
private struct KeyPointPicture: View {
  let item: Item
  let at: Duration?
  let frames: KeyPointFrames?

  var body: some View {
    if let at, let image = frames?.image(at: at) {
      Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
    } else {
      Cover(item: item, corner: 0, squareInset: 0.1, squareCorner: 3, symbolSize: 16)
    }
  }
}
