import SwiftUI

/// The top of the panel beside an item: Loci's face and name, the pages of the panel, and folding it away.
struct CompanionHeader<Tab: Hashable>: View {
  @Binding var tab: Tab
  let tabs: [(value: Tab, title: LocalizedStringResource)]
  let collapse: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      LociAvatar(size: TalkScale.companion.face + 4)
      Text(verbatim: "Loci").font(.system(size: 15, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
      Spacer(minLength: Spacing.xs)
      CapsulePicker(selection: $tab, options: tabs, compact: true)
      PanelButton(title: .loci("panel.collapse"), action: collapse)
    }
    .padding(.horizontal, 18)
    .frame(height: 60)
  }
}
