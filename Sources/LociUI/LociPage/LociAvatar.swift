import AppKit
import SwiftUI

/// Loci's face in a circle, the same face everywhere.
struct LociAvatar: View {
  /// How much of the drawing a circle this size shows.
  enum Framing {
    /// Head and shoulders cropped close, with a light ring, for the sidebar and beside messages.
    case face
    /// The whole drawing, for Loci's own page, which frames it itself.
    case portrait
  }

  let size: CGFloat
  var framing = Framing.face
  @Environment(\.lociFace) private var face

  var body: some View {
    art
      .frame(width: size, height: size)
      .background(Palette.well)
      .clipShape(Circle())
      .background {
        if framing == .face {
          Circle().fill(Palette.ring).padding(-1).shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
        }
      }
      .accessibilityHidden(true)
  }

  @ViewBuilder private var art: some View {
    switch face {
    case .picture(let picture):
      Image(nsImage: picture).resizable().scaledToFill()
    case .drawn:
      if let drawing = LociFace.drawing {
        let frame = Self.frame(of: framing, in: size)
        Image(nsImage: drawing)
          .resizable()
          .frame(width: frame.width, height: frame.height)
          .offset(x: frame.minX, y: frame.minY)
          .frame(width: size, height: size, alignment: .topLeading)
      }
    }
  }

  /// Where the whole drawing goes so that the part `framing` shows fills a circle `size` across.
  static func frame(of framing: Framing, in size: CGFloat) -> CGRect {
    let shown =
      framing == .face
      ? LociFace.faceCrop : CGRect(x: 0, y: 0, width: LociFace.drawingSide, height: LociFace.drawingSide)
    let scale = size / shown.width
    return CGRect(
      x: -shown.minX * scale, y: -shown.minY * scale, width: LociFace.drawingSide * scale,
      height: LociFace.drawingSide * scale)
  }
}
