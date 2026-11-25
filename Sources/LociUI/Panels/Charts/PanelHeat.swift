import LociModel
import SwiftUI

/// Tiles sized by weight and coloured by change; a tile too narrow for both shows only its code.
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
          cell(tile, roomy: rect.width >= Self.roomy && rect.height >= 36)
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

  private func cell(_ tile: PanelHeatTile, roomy: Bool) -> some View {
    let change = data.number(tile.change)
    let strength = min(abs(change ?? 0) / 0.06, 1)
    let flat = abs(change ?? 0) < 0.005
    return VStack(alignment: .leading, spacing: 0) {
      Text(verbatim: tile.code).font(.system(size: roomy ? 12 : 10.5, weight: .bold))
      Spacer(minLength: 0)
      if roomy { Text(verbatim: PanelFigures.change(change)).font(.system(size: 11.5, weight: .semibold)) }
    }
    .monospacedDigit()
    .lineLimit(1)
    .minimumScaleFactor(0.6)
    .foregroundStyle(flat ? Palette.ink : .white)
    .padding(.horizontal, roomy ? 8 : 5)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(flat ? Palette.fillStrong : PanelFigures.tone(change).opacity(0.45 + 0.55 * strength))
  }
}
