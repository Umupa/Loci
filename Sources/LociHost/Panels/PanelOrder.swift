import LociModel

/// The order of the panel column. The person's order comes first; 「接着读」 starts at the top, and a panel
/// the order does not know yet, such as one written by hand or one a project just pinned, goes to the bottom.
enum PanelOrder {
  /// Every place in the column, top to bottom, for these panel names and pinned places.
  static func places(_ order: [PanelPlace], panels names: [String], pinned: [PanelPlace] = []) -> [PanelPlace] {
    let present = Set(names.map(PanelPlace.panel)).union([.reading]).union(pinned)
    var places: [PanelPlace] = []
    for place in order where present.contains(place) && !places.contains(place) { places.append(place) }
    if !places.contains(.reading) { places.insert(.reading, at: 0) }
    for name in names.sorted() where !places.contains(.panel(name)) { places.append(.panel(name)) }
    for place in pinned where !places.contains(place) { places.append(place) }
    return places
  }

  static func movingToTop(
    _ place: PanelPlace, in order: [PanelPlace], panels names: [String], pinned: [PanelPlace] = []
  ) -> [PanelPlace] {
    [place] + places(order, panels: names, pinned: pinned).filter { $0 != place }
  }

  /// The slots to show: 「接着读」 only when something is read partway.
  static func slots(
    _ order: [PanelPlace], panels: [Panel], pinned: [PanelPlace: Panel] = [:], reading: [ReadingNow]
  ) -> [PanelSlot] {
    let byName = Dictionary(panels.map { ($0.name, $0) }) { first, _ in first }
    let pinnedPlaces = pinned.keys.sorted { "\($0)" < "\($1)" }
    return places(order, panels: panels.map(\.name), pinned: pinnedPlaces).compactMap { place in
      switch place {
      case .reading: reading.isEmpty ? nil : .reading(reading)
      case .panel(let name): byName[name].map(PanelSlot.panel)
      case .pinned(let project, _): pinned[place].map { .pinned(project, $0) }
      }
    }
  }
}
