import SwiftUI

/// The top of the panel beside an item: the pages of the panel in the middle, and folding it away at the end.
struct CompanionHeader<Tab: Hashable>: View {
  @Binding var tab: Tab
  let tabs: [(value: Tab, title: LocalizedStringResource)]
  let collapse: () -> Void

  var body: some View {
    ZStack {
      CapsulePicker(selection: $tab, options: tabs, compact: true)
      HStack {
        Spacer(minLength: 0)
        PanelButton(title: .loci("panel.collapse"), action: collapse)
      }
    }
    .padding(.horizontal, 18)
    .frame(height: 60)
  }
}
