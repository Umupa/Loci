import LociModel
import SwiftUI

/// Tiles sized by weight and coloured by change; a tile too narrow for both shows only its code, written
/// smaller, or upward in a tile taller than it is wide, so the code is never cut.
struct PanelHeat: View {
  let tiles: [PanelHeatTile]
  @Environment(\.panelData) private var data
  private static let height: CGFloat = 150
  private static let gap: CGFloat = 3
  /// Narrower than this, a tile shows only its code.
  private static let roomy: CGFloat = 58

  var body: some View {
    GeometryReader { space in
      let rects = HeatLayout.tiles(tiles.map { data.number($0.weight) ?? 0 }, in: space.size)
      ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
        let rect = rects[index].insetBy(dx: Self.gap / 2, dy: Self.gap / 2)
        if rect.width > 0, rect.height > 0 {
          cell(tile, in: rect.size)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        }
      }
    }
    .frame(height: Self.height)
    .padding(-Self.gap / 2)
    .clipShape(.rect(cornerRadius: 14, style: .continuous))
    .padding(.bottom, Spacing.xxs)
  }

  private func cell(_ tile: PanelHeatTile, in size: CGSize) -> some View {
    let change = data.number(tile.change)
    let strength = min(abs(change ?? 0) / 0.06, 1)
    let flat = abs(change ?? 0) < 0.005
    let roomy = Self.isRoomy(size)
    let fit = Self.fit(tile.code, in: size)
    let code = Text(verbatim: tile.code).font(.system(size: fit.size, weight: .bold)).fixedSize()
    return VStack(alignment: .leading, spacing: 0) {
      if fit.upward {
        let long = Self.width(of: tile.code, size: fit.size) + 1
        let line = fit.size * 1.3
        code.frame(width: long, height: line)
          .rotationEffect(.degrees(-90))
          .frame(width: line, height: long)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        code
        Spacer(minLength: 0)
        if roomy { Text(verbatim: PanelFigures.change(change)).font(.system(size: 11.5, weight: .semibold)) }
      }
    }
    .monospacedDigit()
    .lineLimit(1)
    .foregroundStyle(flat ? Palette.ink : .white)
    .padding(.horizontal, roomy ? 8 : Self.inset)
    .padding(.vertical, roomy ? 6 : Self.inset)
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .background(flat ? Palette.fillStrong : PanelFigures.tone(change).opacity(0.45 + 0.55 * strength))
    .clipped()
  }

  /// How a tile's code is written: its size, and whether it runs upward.
  struct Fit: Equatable {
    let size: CGFloat
    let upward: Bool
  }

  /// The room left on each side of a narrow tile's code.
  static let inset: CGFloat = 4
  /// Below this, a code runs upward when the tile is taller than it is wide.
  static let smallest: CGFloat = 7

  /// A line's height for each point of its size.
  static let lineHeight: CGFloat = 1.25

  static func isRoomy(_ size: CGSize) -> Bool { size.width >= roomy && size.height >= 36 }

  /// The largest size up to the usual that the whole code fits at, across or, in a slim tall tile, upward.
  static func fit(_ code: String, in size: CGSize) -> Fit {
    let largest: CGFloat = isRoomy(size) ? 12 : 10.5
    let padding = isRoomy(size) ? 8 : inset
    let natural = width(of: code, size: largest)
    func fitting(_ length: CGFloat) -> CGFloat {
      let room = length - 2 * padding
      var size = natural > 0 ? min(largest, largest * room / natural) : largest
      while size > 1, width(of: code, size: size) > room { size -= 0.25 }
      return size
    }
    func line(_ room: CGFloat) -> CGFloat { (room - 2 * (isRoomy(size) ? 6 : inset)) / lineHeight }
    let across = min(fitting(size.width), line(size.height))
    if across >= smallest || size.height <= size.width { return Fit(size: max(across, 1), upward: false) }
    return Fit(size: max(min(fitting(size.height), line(size.width)), 1), upward: true)
  }

  static func width(of code: String, size: CGFloat) -> CGFloat {
    NSAttributedString(string: code, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)])
      .size().width
  }
}
