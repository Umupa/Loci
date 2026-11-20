/// I-S12: whether an item's page opens with the panel beside it. It starts closed, opens only from the button
/// at the top right, and every item's page then opens as the last one was left.
enum PanelMemory {
  static let key = "itemPanelShown"
  static let shownAtFirst = false
}
