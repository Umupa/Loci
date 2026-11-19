import AppKit
import LociModel
import SwiftUI

/// Item covers the window has already read from the host, so scrolling and reopening do not ask again.
@MainActor
@Observable
final class Covers {
  private var images: [EntityID: NSImage] = [:]
  private var asked: Set<Item> = []

  func image(of item: EntityID) -> NSImage? {
    images[item]
  }

  /// Shows a cover just chosen at once, rather than waiting for the item to change.
  func replace(_ item: EntityID, with image: NSImage) {
    images[item] = image
  }

  /// Reads the cover once per version of the item: a link's cover arrives after its title and length do.
  func load(_ item: Item, from host: any LociModel.Host) async {
    guard images[item.id] == nil, asked.insert(item).inserted else { return }
    guard let data = try? await host.run(ReadCover(item: item.id)), let image = NSImage(data: data) else { return }
    images[item.id] = image
  }
}

extension EnvironmentValues {
  /// Set by the window; views outside one read every cover afresh.
  @Entry var covers: Covers?
}

/// An item's cover in a frame of the given shape. Video and articles fill it; a podcast's square cover sits in
/// the middle over a blurred wash of itself. Without a cover the frame shows the kind's symbol.
struct Cover: View {
  @Environment(\.host) private var host
  @Environment(\.covers) private var covers
  let item: Item
  var corner: CGFloat = Radius.cover
  /// How far the square art of a podcast stays from the top and bottom, as a share of the height.
  var squareInset: CGFloat = 0.08
  var squareCorner: CGFloat = 4
  var dimmed = false
  /// The kind's symbol shown while there is no cover.
  var symbolSize = Size.thumbnailSymbol

  var body: some View {
    Rectangle()
      .fill(Palette.coverBackdrop)
      .overlay { art }
      .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
      .task(id: item) { await covers?.load(item, from: host) }
  }

  @ViewBuilder private var art: some View {
    if let image = covers?.image(of: item.id) {
      if case .audio = item.kind {
        GeometryReader { frame in
          let side = frame.size.height * (1 - squareInset * 2)
          ZStack {
            Image(nsImage: image).resizable().scaledToFill()
              .frame(width: frame.size.width * 1.36, height: frame.size.height * 1.36)
              .blur(radius: 16).saturation(1.3).brightness(-0.15)
            Image(nsImage: image).resizable().scaledToFill()
              .frame(width: side, height: side)
              .clipShape(RoundedRectangle(cornerRadius: squareCorner, style: .continuous))
              .shadow(color: .black.opacity(0.4), radius: side * 0.04, y: side * 0.02)
          }
          .frame(width: frame.size.width, height: frame.size.height)
        }
        .saturation(dimmed ? 0.7 : 1).brightness(dimmed ? -0.2 : 0)
      } else {
        Image(nsImage: image).resizable().scaledToFill()
          .saturation(dimmed ? 0.7 : 1).brightness(dimmed ? -0.2 : 0)
      }
    } else {
      Image(systemName: Symbols.kind(ItemKind(item.kind)))
        .font(.system(size: symbolSize, weight: .light))
        .foregroundStyle(Palette.inkFaint)
    }
  }
}

/// A square cover alone, as the podcast page shows it.
struct SquareCover: View {
  @Environment(\.host) private var host
  @Environment(\.covers) private var covers
  let item: Item
  let corner: CGFloat

  var body: some View {
    Group {
      if let image = covers?.image(of: item.id) {
        Image(nsImage: image).resizable().scaledToFill()
      } else {
        Palette.coverBackdrop.overlay {
          Image(systemName: Symbols.kind(.audio))
            .font(.system(size: Size.emptySymbol, weight: .light))
            .foregroundStyle(Palette.inkFaint)
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    .task(id: item) { await covers?.load(item, from: host) }
  }
}
