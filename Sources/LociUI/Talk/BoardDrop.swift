import SwiftUI

/// Where things are on the main page while something is dragged across it, in the page's own coordinates.
struct BoardFrames: Equatable {
  var lanes: [String: CGRect] = [:]
  var panels: [String: CGRect] = [:]
}

/// The frames the lanes and panels last reported. Only a drag reads them, so a report, made on every scroll and
/// every step of an animation, draws nothing again.
@MainActor
final class BoardFrameReports {
  var frames = BoardFrames()
}

/// Where the pointer is while something is dragged across the page. Only what follows it is drawn again as it
/// moves, not the lanes under it.
@MainActor @Observable
final class BoardPointer {
  var location = CGPoint.zero
  var conversationShift: CGFloat = 0
}

extension View {
  /// Puts the view's top left corner under the pointer, `grab` short of it.
  func underPointer(_ pointer: BoardPointer, grab: CGSize) -> some View {
    modifier(UnderPointer(pointer: pointer, grab: grab))
  }

  /// Shifts the view sideways as far as the conversation is dragged.
  func shiftedWithConversation(_ pointer: BoardPointer, y: CGFloat = 0) -> some View {
    modifier(ShiftedWithConversation(pointer: pointer, y: y))
  }
}

private struct UnderPointer: ViewModifier {
  let pointer: BoardPointer
  let grab: CGSize

  func body(content: Content) -> some View {
    content.offset(x: pointer.location.x - grab.width, y: pointer.location.y - grab.height)
  }
}

private struct ShiftedWithConversation: ViewModifier {
  let pointer: BoardPointer
  let y: CGFloat

  func body(content: Content) -> some View {
    content.offset(x: pointer.conversationShift, y: y)
  }
}

extension TalkLayout {
  /// How far past the row's outer edge a panel has to be dragged to start a lane there.
  static let edgeReach: CGFloat = 10
  /// How far either side of a lane a panel still counts as over it.
  static let laneReach: CGFloat = 12

  /// Where the panel `key` dragged to `point` would be put down: in the open lane under it, before the first
  /// panel whose middle is below the point; or, past the conversation at either end of the row, in a new lane
  /// there. `nil` where it would go nowhere new.
  func drop(of key: String, at point: CGPoint, frames: BoardFrames, folded: Set<String>) -> Drop? {
    let row = lanes.compactMap { frames.lanes[$0.id] }.reduce(CGRect.null) { $0.union($1) }
    if !row.isNull {
      if leading.isEmpty, point.x < row.minX + Self.edgeReach { return .newLane(.leading) }
      if trailing.isEmpty, point.x > row.maxX - Self.edgeReach { return .newLane(.trailing) }
    }
    let open = panelLanes.filter { !folded.contains($0.id) }
    guard
      let lane = open.first(where: { lane in
        guard let frame = frames.lanes[lane.id] else { return false }
        return point.x >= frame.minX - Self.laneReach && point.x <= frame.maxX + Self.laneReach
      })
    else { return nil }
    let others = lane.keys.filter { $0 != key }
    let index = others.prefix { other in
      guard let frame = frames.panels[other] else { return true }
      return point.y > frame.midY
    }.count
    return .lane(lane.id, at: index)
  }

  /// How many panel lanes go left of the conversation while it is dragged to sit over `conversation`: a lane
  /// changes sides once the conversation's near edge passes the lane's middle.
  func conversationPlace(over conversation: CGRect, frames: BoardFrames) -> Int {
    let all = panelLanes
    var place = 0
    for (index, lane) in all.enumerated() {
      guard let frame = frames.lanes[lane.id] else {
        if index < conversationPlace { place += 1 }
        continue
      }
      let onLeft = index < conversationPlace
      if onLeft ? conversation.minX > frame.midX : conversation.maxX > frame.midX { place += 1 }
    }
    return place
  }
}
