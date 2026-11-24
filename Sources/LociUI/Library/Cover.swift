import LociModel
import SwiftUI

/// An item's picture in a frame, with a paper cover when the item has no picture.
struct Cover: View {
  @Environment(\.host) private var host
  @Environment(\.covers) private var covers
  @Environment(\.displayScale) private var displayScale
  @State private var pixels = 0
  @State private var picture: CoverPicture?
  let item: Item
  var corner: CGFloat = Radius.cover
  /// For a podcast in a wide frame, the inset around its square art over a wash of the cover's colors.
  var squareInset: CGFloat? = 0.08
  var squareCorner: CGFloat = 4
  var dimmed = false
  var backdrop = Palette.coverBackdrop
  var edge: CGFloat?

  private struct Request: Equatable {
    let item: Item
    let pixels: Int
    let revision: Int
  }

  var body: some View {
    if let edge {
      content(pixels: Self.pixels(edge, scale: displayScale))
    } else {
      let scale = displayScale
      content(pixels: pixels)
        .onGeometryChange(for: Int.self) { geometry in
          Self.pixels(max(geometry.size.width, geometry.size.height), scale: scale)
        } action: {
          pixels = $0
        }
    }
  }

  nonisolated private static func pixels(_ edge: CGFloat, scale: CGFloat) -> Int {
    let scaled = min(2048, edge * scale)
    let step: CGFloat = scaled <= 128 ? 16 : 32
    return Int((scaled / step).rounded(.up) * step)
  }

  private func content(pixels: Int) -> some View {
    let request = Request(item: item, pixels: pixels, revision: covers?.revision ?? 0)
    return Rectangle()
      .fill(backdrop)
      .overlay { art }
      .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
      .task(id: request) {
        guard request.pixels > 0 else { return }
        let decoded = await covers?.load(request.item, pixels: request.pixels, from: host)
        if !Task.isCancelled { picture = decoded }
      }
      .onDisappear { picture = nil }
  }

  @ViewBuilder private var art: some View {
    if let picture {
      let image = picture.image
      if case .audio = item.kind, let squareInset {
        GeometryReader { frame in
          let side = frame.size.height * (1 - squareInset * 2)
          ZStack {
            if let wash = picture.wash {
              Image(nsImage: wash).resizable().scaledToFill()
                .frame(width: frame.size.width, height: frame.size.height)
            }
            let square = RoundedRectangle(cornerRadius: squareCorner, style: .continuous)
            Image(nsImage: image).resizable().scaledToFill()
              .frame(width: side, height: side)
              .clipShape(square)
              .background { SoftShadow(shape: square, opacity: 0.35, radius: side * 0.05, y: side * 0.025, steps: 4) }
          }
          .frame(width: frame.size.width, height: frame.size.height)
        }
        .saturation(dimmed ? 0.7 : 1).brightness(dimmed ? -0.2 : 0)
      } else if item.kind == .book, squareInset != nil {
        GeometryReader { frame in
          ZStack {
            if let wash = picture.wash {
              Image(nsImage: wash).resizable().scaledToFill()
                .frame(width: frame.size.width, height: frame.size.height)
            }
            let page = RoundedRectangle(cornerRadius: 2, style: .continuous)
            Image(nsImage: image).resizable().scaledToFit()
              .clipShape(page)
              .background { SoftShadow(shape: page, opacity: 0.35, radius: 6, y: 3, steps: 4) }
              .padding(.vertical, frame.size.height * 0.08)
          }
          .frame(width: frame.size.width, height: frame.size.height)
        }
      } else {
        Image(nsImage: image).resizable().scaledToFill()
          .saturation(dimmed ? 0.7 : 1).brightness(dimmed ? -0.2 : 0)
      }
    } else if item.kind == .book {
      BookPaperCover(item: item)
    } else {
      PaperCover(item: item)
    }
  }
}

/// A square cover alone, as the podcast page shows it.
struct SquareCover: View {
  let item: Item
  let corner: CGFloat

  var body: some View {
    Cover(item: item, corner: corner, squareInset: nil)
  }
}
