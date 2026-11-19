import SwiftUI

/// Loci's face in a circle, the same face everywhere.
struct LociAvatar: View {
  /// Whether the circle draws its own ring.
  enum Framing {
    /// A ring for the sidebar and beside messages.
    case face
    /// Loci's own page frames the portrait itself.
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
    if let picture = face.image {
      Image(nsImage: picture).resizable().scaledToFill()
    }
  }
}
