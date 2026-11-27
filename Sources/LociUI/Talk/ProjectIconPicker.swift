import LociModel
import SwiftUI

/// Grid of curated monochrome symbols from `ProjectIcon.catalog` to pick for a project.
struct ProjectIconPicker: View {
  let selected: String
  let pick: (String) -> Void
  @State private var hovered: String?

  private let columns = Array(repeating: GridItem(.fixed(32), spacing: 4), count: 8)

  var body: some View {
    LazyVGrid(columns: columns, spacing: 4) {
      ForEach(ProjectIcon.symbols, id: \.self) { symbol in
        let isSelected = symbol == selected
        let isHovered = symbol == hovered
        Button {
          pick(symbol)
        } label: {
          Image(systemName: symbol)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Palette.accentInk : isHovered ? Palette.ink : Palette.inkMuted)
            .frame(width: 32, height: 32)
            .background(
              RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(isSelected ? Palette.tint : isHovered ? Palette.fill : .clear)
            )
            .overlay(
              RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(isSelected ? Palette.accentLine : .clear, lineWidth: Size.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? symbol : (hovered == symbol ? nil : hovered) }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(10)
  }
}
