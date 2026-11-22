import LociModel
import SwiftUI

/// Loci at the top, the library under it, settings at the foot.
///
/// The sidebar draws its own selection: an amber wash, the same whether or not the sidebar has keyboard
/// focus. The system's list selection follows the system accent color and turns gray when focus is
/// elsewhere.
struct Sidebar: View {
  @Environment(\.machineChoice) private var machineChoice
  @Binding var place: Place
  /// Whether the main conversation or Loci's page is on screen.
  let lociChosen: Bool
  /// What Loci is working on; `nil` while it is idle.
  let work: LociWork?
  let chooseLoci: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      SidebarLoci(chosen: lociChosen, work: work, choose: chooseLoci)
        .padding(.top, 14)
        .padding(.bottom, Spacing.xs)
      SidebarLabel(text: Text(.loci("sidebar.library")))
      row(.library(nil), Text(.loci("sidebar.allItems")), symbol: Symbols.library)
      ForEach(LibraryCategory.allCases, id: \.self) { category in
        row(.library(category), Text(Messages.name(of: category)), symbol: Symbols.category(category))
      }
      row(.browser, Text(.loci("sidebar.browser")), symbol: Symbols.browser)
      Spacer(minLength: 0)
      SidebarLabel(text: Text(.loci("sidebar.settings")))
      row(.settings(.general), Text(.loci("settings.general")), symbol: Symbols.settings)
      row(.settings(.agents), Text(.loci("settings.agents")), symbol: Symbols.agents)
      if machineChoice?.link == nil {
        row(.settings(.models), Text(.loci("settings.models")), symbol: ModelSettingsPage.symbol)
      }
      row(.settings(.media), Text(.loci("settings.media")), symbol: Symbols.media)
      row(.settings(.remote), Text(.loci("settings.remote")), symbol: Symbols.remote)
    }
    .padding(.horizontal, 10)
  }

  private func row(_ target: Place, _ title: Text, symbol: String) -> some View {
    SidebarRow(selected: place == target, title: title, symbol: symbol) { place = target }
  }
}

/// A destination whose symbol takes the accent when selected.
private struct SidebarRow: View {
  let selected: Bool
  let title: Text
  let symbol: String
  let choose: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: choose) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 14))
          .foregroundStyle(selected ? Palette.sidebarSelectedInk : Palette.sidebarInkMuted)
          .frame(width: 17, height: 17)
        title.lineLimit(1).fontWeight(selected ? .medium : .regular)
        Spacer(minLength: 0)
      }
      .font(.system(size: 13.5))
      .foregroundStyle(Palette.ink)
      .padding(.vertical, 6)
      .padding(.horizontal, 10)
      .background(
        RoundedRectangle(cornerRadius: Radius.sidebarRow, style: .continuous).fill(
          selected ? Palette.tint : hovering ? Palette.fill : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// Above a group of rows.
struct SidebarLabel: View {
  let text: Text

  var body: some View {
    text
      .font(.system(size: 11.5, weight: .medium))
      .foregroundStyle(Palette.sidebarSectionInk)
      .padding(.top, 14)
      .padding(.horizontal, 10)
      .padding(.bottom, 5)
  }
}
