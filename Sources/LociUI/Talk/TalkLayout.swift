import Foundation

/// How the main page is laid out on this Mac: lanes of panels on either side of the one conversation, each
/// lane holding panels by key, top to bottom. The conversation cannot be left out or doubled: it is not a lane
/// in a list but the place the two lists meet.
struct TalkLayout: Codable, Equatable {
  /// Lanes left of the conversation, leftmost first.
  var leading: [PanelLane]
  var conversationWidth: CGFloat
  /// Lanes right of the conversation, nearest first.
  var trailing: [PanelLane]

  /// Where this Mac keeps the layout.
  static let key = "talkLayout"
  static let gutter: CGFloat = 24
  static let conversationWidths: ClosedRange<CGFloat> = 440...760
  static let panelWidths: ClosedRange<CGFloat> = 300...520
  /// A lane folded to its panels' marks where the window has no room for it.
  static let rail: CGFloat = 52
  /// The narrowest the conversation gets before lanes fold away.
  static let conversationLeast: CGFloat = 320

  static let standard = TalkLayout(
    leading: [], conversationWidth: 600, trailing: [PanelLane(id: "right", width: 360, keys: [])])

  /// Every lane left to right, the conversation among them.
  var lanes: [Lane] {
    leading.map(Lane.panels) + [.conversation] + trailing.map(Lane.panels)
  }

  var panelLanes: [PanelLane] { leading + trailing }

  /// The layout holding exactly `keys`: gone panels leave, and new ones join the lane nearest the conversation on
  /// the right, or on the left when there is none there. A lane left empty goes.
  func holding(_ keys: [String]) -> TalkLayout {
    let wanted = Set(keys)
    var next = self
    next.leading = leading.map { $0.keeping(wanted) }
    next.trailing = trailing.map { $0.keeping(wanted) }
    let placed = Set(next.panelLanes.flatMap(\.keys))
    let arriving = keys.filter { !placed.contains($0) }
    if !arriving.isEmpty {
      if let first = next.trailing.indices.first {
        next.trailing[first].keys += arriving
      } else if let last = next.leading.indices.last {
        next.leading[last].keys += arriving
      } else {
        next.trailing = [PanelLane(id: next.freshID(), width: Self.standard.trailing[0].width, keys: arriving)]
      }
    }
    return next.withoutEmptyLanes()
  }

  /// Where a panel can be put down: at a place in a lane, or in a new lane at the far end of one side.
  enum Drop: Equatable {
    case lane(String, at: Int)
    case newLane(Side)
  }

  enum Side: Equatable {
    case leading, trailing
  }

  /// The layout with the panel `key` put down at `drop`. A lane it leaves empty stays while `keepingEmpty`, so
  /// the lane a drag started from is still there until the drag ends.
  func moving(_ key: String, to drop: Drop, keepingEmpty: Bool = false) -> TalkLayout {
    var next = self
    next.leading = leading.map { $0.without(key) }
    next.trailing = trailing.map { $0.without(key) }
    switch drop {
    case .lane(let id, let index):
      next.update(id) { lane in
        lane.keys.insert(key, at: min(max(index, 0), lane.keys.count))
      }
    case .newLane(.leading):
      next.leading.insert(PanelLane(id: next.freshID(), width: 340, keys: [key]), at: 0)
    case .newLane(.trailing):
      next.trailing.append(PanelLane(id: next.freshID(), width: 340, keys: [key]))
    }
    return keepingEmpty ? next : next.withoutEmptyLanes()
  }

  /// The layout with `key` first in its lane.
  func raising(_ key: String) -> TalkLayout {
    guard let lane = panelLanes.first(where: { $0.keys.contains(key) }) else { return self }
    return moving(key, to: .lane(lane.id, at: 0))
  }

  /// The layout with the conversation after the first `place` panel lanes, counted left to right.
  func movingConversation(to place: Int) -> TalkLayout {
    let all = panelLanes
    let cut = min(max(place, 0), all.count)
    return TalkLayout(leading: Array(all[..<cut]), conversationWidth: conversationWidth, trailing: Array(all[cut...]))
  }

  /// Where the conversation is among the lanes, counted from the left.
  var conversationPlace: Int { leading.count }

  /// The layout with lane `lane` (or the conversation, when `nil`) given `width`, kept within what it allows.
  func resizing(_ lane: String?, to width: CGFloat) -> TalkLayout {
    var next = self
    if let lane {
      next.update(lane) { $0.width = Self.clamp(width, to: Self.panelWidths) }
    } else {
      next.conversationWidth = Self.clamp(width, to: Self.conversationWidths)
    }
    return next
  }

  /// The arrangements the layout button offers. Each keeps the panels in their order.
  enum Arrangement: CaseIterable, Equatable {
    case panelsRight, panelsLeft, panelsBothSides
  }

  func arranged(_ arrangement: Arrangement) -> TalkLayout {
    let keys = panelLanes.flatMap(\.keys)
    switch arrangement {
    case .panelsRight:
      return TalkLayout(leading: [], conversationWidth: 600, trailing: [PanelLane(id: "right", width: 360, keys: keys)])
        .withoutEmptyLanes()
    case .panelsLeft:
      return TalkLayout(leading: [PanelLane(id: "left", width: 360, keys: keys)], conversationWidth: 600, trailing: [])
        .withoutEmptyLanes()
    case .panelsBothSides:
      let half = (keys.count + 1) / 2
      return TalkLayout(
        leading: [PanelLane(id: "left", width: 340, keys: Array(keys[..<half]))], conversationWidth: 580,
        trailing: [PanelLane(id: "right", width: 340, keys: Array(keys[half...]))]
      ).withoutEmptyLanes()
    }
  }

  /// The arrangement the layout is in, when it is one of them.
  var arrangement: Arrangement? {
    switch (leading.count, trailing.count) {
    case (0, 1): .panelsRight
    case (1, 0): .panelsLeft
    case (1, 1): .panelsBothSides
    default: nil
    }
  }

  /// The layout without lanes that hold nothing.
  func withoutEmptyLanes() -> TalkLayout {
    var next = self
    next.leading = leading.filter { !$0.keys.isEmpty }
    next.trailing = trailing.filter { !$0.keys.isEmpty }
    return next
  }

  private mutating func update(_ id: String, _ change: (inout PanelLane) -> Void) {
    if let index = leading.firstIndex(where: { $0.id == id }) { change(&leading[index]) }
    if let index = trailing.firstIndex(where: { $0.id == id }) { change(&trailing[index]) }
  }

  private func freshID() -> String {
    let taken = Set(panelLanes.map(\.id))
    return (1...).lazy.map { "lane-\($0)" }.first { !taken.contains($0) } ?? "lane"
  }

  static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
    min(max(value, range.lowerBound), range.upperBound)
  }
}

/// A lane of panels beside the conversation.
struct PanelLane: Codable, Equatable, Identifiable {
  let id: String
  var width: CGFloat
  /// Its panels by key, top to bottom.
  var keys: [String]

  fileprivate func keeping(_ wanted: Set<String>) -> PanelLane {
    PanelLane(id: id, width: width, keys: keys.filter(wanted.contains))
  }

  fileprivate func without(_ key: String) -> PanelLane {
    PanelLane(id: id, width: width, keys: keys.filter { $0 != key })
  }
}

extension TalkLayout {
  /// One lane, as the page draws them left to right.
  enum Lane: Equatable, Identifiable {
    case conversation
    case panels(PanelLane)

    var id: String {
      switch self {
      case .conversation: "conversation"
      case .panels(let lane): lane.id
      }
    }
  }

  /// How the lanes sit in a page `width` wide: each lane's width or whether it folds to a rail, and how far in
  /// the row starts, so the lanes stay together in the middle of the page.
  struct Fit: Equatable {
    let widths: [String: CGFloat]
    let rails: Set<String>
    let inset: CGFloat

    func width(of lane: Lane) -> CGFloat { widths[lane.id] ?? 0 }
    func folds(_ lane: Lane) -> Bool { rails.contains(lane.id) }
  }

  /// Fits the lanes into `width`: the conversation gives way first, down to its narrowest, then the panel lanes
  /// down to theirs; then the lanes farthest from the conversation fold to rails, one at a time, and the room a
  /// fold leaves goes back to the lanes still open, so a rail sits at the edge of the page.
  func fit(in width: CGFloat) -> Fit {
    let lanes = lanes
    var widths = Dictionary(uniqueKeysWithValues: lanes.map { ($0.id, Self.preferred($0, in: self)) })
    var rails = Set<String>()
    func total() -> CGFloat {
      lanes.reduce(0) { $0 + (rails.contains($1.id) ? Self.rail : widths[$1.id] ?? 0) }
        + Self.gutter * CGFloat(max(lanes.count - 1, 0))
    }
    var over = total() - width
    if over > 0 {
      let give = min(over, conversationWidth - Self.conversationWidths.lowerBound)
      widths[Lane.conversation.id, default: 0] -= max(give, 0)
      over -= max(give, 0)
    }
    for lane in panelLanes where over > 0 {
      let give = min(over, lane.width - Self.panelWidths.lowerBound)
      widths[lane.id, default: 0] -= max(give, 0)
      over -= max(give, 0)
    }
    let place = conversationPlace
    let byDistance = lanes.indices.filter { $0 != place }.sorted { abs($0 - place) > abs($1 - place) }
    for index in byDistance where total() > width {
      rails.insert(lanes[index].id)
    }
    for lane in [.conversation] + panelLanes.map(Lane.panels) where !rails.contains(lane.id) && total() < width {
      let current = widths[lane.id] ?? 0
      widths[lane.id] = min(Self.preferred(lane, in: self), current + width - total())
    }
    if total() > width {
      let least = max(Self.conversationLeast, (widths[Lane.conversation.id] ?? 0) - (total() - width))
      widths[Lane.conversation.id] = least
    }
    return Fit(widths: widths, rails: rails, inset: max(0, (width - total()) / 2))
  }

  private static func preferred(_ lane: Lane, in layout: TalkLayout) -> CGFloat {
    switch lane {
    case .conversation: clamp(layout.conversationWidth, to: conversationWidths)
    case .panels(let panels): clamp(panels.width, to: panelWidths)
    }
  }
}
