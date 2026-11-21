import SwiftUI

/// How wide the reading column is: a comfortable measure, or all the room between the sidebar and the panel.
/// A choice for this Mac, kept with its preferences.
enum ReadingWidth: String, CaseIterable {
  case comfortable, full

  static let key = "readingWidth"

  var name: LocalizedStringResource {
    switch self {
    case .comfortable: .loci("width.comfortable")
    case .full: .loci("width.full")
    }
  }

  /// The margin on each side of the column in a reader `width` wide.
  func margin(in width: CGFloat) -> CGFloat {
    switch self {
    case .comfortable: max(Spacing.xxl, (width - Typography.readingWidth) / 2)
    case .full: Spacing.xxl
    }
  }
}

/// A pane beside the text whose width the person drags, within bounds that leave the text room.
struct PaneWidth {
  enum Side {
    case leading, trailing
  }

  let side: Side
  let range: ClosedRange<CGFloat>
  let ideal: CGFloat
  /// Where this Mac keeps the width.
  let key: String

  static let sidebar = PaneWidth(side: .leading, range: 200...360, ideal: Size.sidebarIdeal, key: "sidebarWidth")
  static let panel = PaneWidth(side: .trailing, range: 300...2_000, ideal: Size.panelWidth, key: "panelWidth")
  /// Beside an item: a little narrower than beside other text, as the player or the article wants the room.
  static let itemPanel = PaneWidth(side: .trailing, range: 300...2_000, ideal: Size.mediaPanel, key: "itemPanelWidth")

  func clamped(_ width: CGFloat) -> CGFloat {
    min(max(width, range.lowerBound), range.upperBound)
  }

  /// The width the pane takes when `available` points hold it and the text, leaving the text room to be read.
  func fitting(_ width: CGFloat, in available: CGFloat) -> CGFloat {
    max(range.lowerBound, min(clamped(width), available - Size.readerMinimum))
  }

  /// The width after dragging the pane's inner edge by `distance` points to the right.
  func width(from start: CGFloat, dragged distance: CGFloat) -> CGFloat {
    clamped(side == .leading ? start + distance : start - distance)
  }
}

/// The strip along a pane's inner edge that drags it wider or narrower; a double click puts it back.
struct PaneResizer: View {
  let pane: PaneWidth
  @Binding var width: Double
  /// The widest the pane can be where it is now.
  var maximum = CGFloat.infinity
  @State private var start: CGFloat?

  var body: some View {
    Color.clear
      .frame(width: Size.resizer)
      .contentShape(Rectangle())
      .pointerStyle(.columnResize)
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
          .onChanged { drag in
            let from = start ?? min(CGFloat(width), maximum)
            start = from
            width = Double(min(pane.width(from: from, dragged: drag.translation.width), maximum))
          }
          .onEnded { _ in start = nil }
      )
      .onTapGesture(count: 2) { width = Double(pane.ideal) }
      .accessibilityHidden(true)
  }
}

/// Whether a pane beside a conversation or a text shows. It shows as the person left it, except that in a
/// window narrower than `narrow` a crowded page takes the pane's room, so what is read stays wide enough.
/// Opened again there, it stays until the window changes between narrow and wide.
struct PaneFit: Equatable {
  let narrow: CGFloat

  /// The sidebar steps aside for a page with text and the panel beside it.
  static let sidebar = PaneFit(narrow: 1000)
  /// The panel column steps aside for the main conversation, measured without the sidebar.
  static let panelColumn = PaneFit(narrow: Size.talkColumn + Size.panelColumn + Spacing.xxl)

  private(set) var stepsAside = false
  private var keptOpen = false

  init(narrow: CGFloat) {
    self.narrow = narrow
  }

  mutating func fit(width: CGFloat, crowded: Bool = true) {
    let aside = crowded && width < narrow
    guard aside != stepsAside else { return }
    stepsAside = aside
    keptOpen = false
  }

  func shows(_ preferred: Bool) -> Bool {
    preferred && (!stepsAside || keptOpen)
  }

  /// The person's choice after they toggle the pane. Hiding it where it only stepped aside for now keeps
  /// it wanted elsewhere.
  mutating func toggle(_ preferred: Bool) -> Bool {
    guard stepsAside else { return !preferred }
    if shows(preferred) {
      keptOpen = false
      return preferred
    }
    keptOpen = true
    return true
  }
}
