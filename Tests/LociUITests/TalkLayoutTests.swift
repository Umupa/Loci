import Foundation
import Testing

@testable import LociUI

/// P-S1, P-S12–P-S16: how the main page's lanes hold panels, move, resize and fit the window.
struct TalkLayoutTests {
  static func lane(_ id: String, _ keys: [String], width: CGFloat = 380) -> PanelLane {
    PanelLane(id: id, width: width, keys: keys)
  }

  static let twoSides = TalkLayout(
    leading: [lane("left", ["/reading", "radar"], width: 340)], conversationWidth: 600,
    trailing: [lane("right", ["follow"], width: 340)])

  @Test func newPanelsJoinTheLaneNearestTheConversationOnTheRight() {
    let held = Self.twoSides.holding(["/reading", "radar", "follow", "jobs"])
    #expect(held.trailing[0].keys == ["follow", "jobs"])
    #expect(held.leading[0].keys == ["/reading", "radar"])
  }

  @Test func withNoLaneOnTheRightNewPanelsJoinTheNearestOnTheLeft() {
    let left = TalkLayout(
      leading: [Self.lane("a", ["x"]), Self.lane("b", ["y"])], conversationWidth: 600, trailing: [])
    #expect(left.holding(["x", "y", "z"]).leading.map(\.keys) == [["x"], ["y", "z"]])
  }

  @Test func theFirstPanelsOpenALaneOnTheRight() {
    let empty = TalkLayout(leading: [], conversationWidth: 600, trailing: [])
    #expect(empty.holding(["radar"]).trailing.map(\.keys) == [["radar"]])
  }

  @Test func aPanelThatIsGoneLeavesAndItsEmptyLaneGoes() {
    let held = Self.twoSides.holding(["/reading", "radar"])
    #expect(held.trailing.isEmpty)
    #expect(held.leading[0].keys == ["/reading", "radar"])
  }

  @Test func aPanelMovesToAPlaceInAnotherLane() {
    let moved = Self.twoSides.moving("radar", to: .lane("right", at: 0))
    #expect(moved.leading[0].keys == ["/reading"])
    #expect(moved.trailing[0].keys == ["radar", "follow"])
  }

  @Test func aPanelHeldPastTheConversationOpensANewLaneThere() {
    let right = TalkLayout.standard.holding(["a", "b"])
    let moved = right.moving("b", to: .newLane(.leading))
    #expect(moved.leading.map(\.keys) == [["b"]])
    #expect(moved.trailing.map(\.keys) == [["a"]])
  }

  @Test func theLaneADragStartedFromStaysUntilTheDragEnds() {
    let moving = Self.twoSides.moving("follow", to: .lane("left", at: 2), keepingEmpty: true)
    #expect(moving.trailing.map(\.keys) == [[]])
    #expect(moving.withoutEmptyLanes().trailing.isEmpty)
  }

  @Test func movingToTheTopPutsAPanelFirstInItsOwnLane() {
    #expect(Self.twoSides.raising("radar").leading[0].keys == ["radar", "/reading"])
  }

  @Test func theConversationMovesBetweenLanes() {
    let moved = Self.twoSides.movingConversation(to: 2)
    #expect(moved.leading.map(\.id) == ["left", "right"])
    #expect(moved.trailing.isEmpty)
    #expect(moved.conversationPlace == 2)
    #expect(Self.twoSides.movingConversation(to: 0).trailing.map(\.id) == ["left", "right"])
  }

  @Test func widthsStayWithinWhatEachLaneAllows() {
    #expect(Self.twoSides.resizing("left", to: 900).leading[0].width == TalkLayout.panelWidths.upperBound)
    #expect(Self.twoSides.resizing(nil, to: 100).conversationWidth == TalkLayout.conversationWidths.lowerBound)
  }

  @Test func theDividerMovesTheSameDistanceWhetherThePointerGetsThereAtOnceOrInSteps() {
    let layout = Self.twoSides
    let handle = TalkLayout.WidthDrag.Handle.gap(layout.lanes[0], .conversation)
    var direct = TalkLayout.WidthDrag(handle, layout: layout, fit: layout.fit(in: 1600))
    var slowly = direct
    direct.move(by: 30)
    for distance: CGFloat in [10, 20, 30] { slowly.move(by: distance) }

    #expect(slowly.preview == direct.preview)
    #expect(slowly.preview.leading[0].width == 370)
    #expect(slowly.preview.conversationWidth == 570)
    #expect(slowly.preview.trailing == layout.trailing)
  }

  @Test func theDividerFollowsThePointerBackFromALimitAndReturnsToItsStartingPosition() {
    let layout = Self.twoSides
    var drag = TalkLayout.WidthDrag(.gap(layout.lanes[0], .conversation), layout: layout, fit: layout.fit(in: 1600))
    drag.move(by: 200)
    #expect(drag.preview.conversationWidth == 440)
    #expect(drag.preview.leading[0].width == 500)

    drag.move(by: 25)
    #expect(drag.preview.leading[0].width == 365)
    drag.move(by: -100)
    #expect(drag.preview.leading[0].width == 300)
    drag.move(by: 0)
    #expect(drag.preview == layout)
  }

  @Test func aDividerStartsFromTheWidthsActuallyShownInATightWindow() {
    let layout = TalkLayout(leading: Self.twoSides.leading, conversationWidth: 600, trailing: [])
    var drag = TalkLayout.WidthDrag(.gap(layout.lanes[0], .conversation), layout: layout, fit: layout.fit(in: 900))
    drag.move(by: 20)
    #expect(drag.preview.leading[0].width == 360)
    #expect(drag.preview.conversationWidth == 516)
  }

  @Test func theOtherLanesStayStillWhenTheDividerMovesInACrowdedWindow() {
    let layout = TalkLayout(
      leading: [Self.lane("far", ["a"], width: 400), Self.lane("near", ["b"], width: 400)],
      conversationWidth: 600, trailing: [Self.lane("right", ["c"], width: 400)])
    let fit = layout.fit(in: 1610)
    var drag = TalkLayout.WidthDrag(.gap(layout.lanes[1], .conversation), layout: layout, fit: fit)
    drag.move(by: -40)
    let moved = drag.preview.fit(in: 1610)
    #expect(moved.widths["far"] == fit.widths["far"])
    #expect(moved.widths["near"] == 358)
    #expect(moved.widths["conversation"] == 480)
    #expect(moved.widths["right"] == fit.widths["right"])
    #expect(moved.inset == fit.inset)
  }

  @Test func anOutsideEdgeFollowsThePointerBackAfterRunningOutOfRoom() {
    let layout = Self.twoSides
    var drag = TalkLayout.WidthDrag(.edge(.trailing, layout.lanes[2]), layout: layout, fit: layout.fit(in: 1400))
    drag.move(by: 50)
    #expect(drag.preview.trailing[0].width == 412)
    drag.move(by: 20)
    #expect(drag.preview.trailing[0].width == 380)
    drag.move(by: -20)
    #expect(drag.preview.trailing[0].width == 300)
    #expect(drag.preview.leading == layout.leading)
    #expect(drag.preview.conversationWidth == layout.conversationWidth)
  }

  @Test func eachArrangementKeepsThePanelsInOrder() {
    let keys = ["/reading", "radar", "follow"]
    #expect(Self.twoSides.arranged(.panelsRight).trailing.map(\.keys) == [keys])
    #expect(Self.twoSides.arranged(.panelsLeft).leading.map(\.keys) == [keys])
    let both = Self.twoSides.arranged(.panelsBothSides)
    #expect(both.leading.map(\.keys) == [["/reading", "radar"]])
    #expect(both.trailing.map(\.keys) == [["follow"]])
    #expect(both.arrangement == .panelsBothSides)
    #expect(Self.twoSides.movingConversation(to: 2).arrangement == nil)
  }

  @Test func theLanesStayTogetherInTheMiddleOfAWidePage() {
    let fit = Self.twoSides.fit(in: 1600)
    #expect(fit.rails.isEmpty)
    #expect(fit.widths["conversation"] == 600)
    #expect(fit.inset == (1600 - (340 + 600 + 340 + 2 * TalkLayout.gutter)) / 2)
  }

  @Test func theConversationGivesWayFirstThenThePanels() {
    let fit = Self.twoSides.fit(in: 1150)
    #expect(fit.widths["conversation"] == TalkLayout.conversationWidths.lowerBound)
    #expect(fit.widths["left"]! + fit.widths["right"]! == 1150 - 440 - 2 * TalkLayout.gutter)
    #expect(fit.rails.isEmpty)
  }

  @Test func theLaneFarthestFromTheConversationFoldsFirst() {
    let three = TalkLayout(
      leading: [Self.lane("far", ["a"]), Self.lane("near", ["b"])], conversationWidth: 600,
      trailing: [Self.lane("right", ["c"])])
    let fit = three.fit(in: 1200)
    #expect(fit.rails == ["far"])
    #expect(fit.inset >= 0)
    let narrow = three.fit(in: 700)
    #expect(narrow.rails == ["far", "near", "right"])
    #expect(narrow.widths["conversation"]! >= TalkLayout.conversationLeast)
  }

  /// P-S16: the room a folded lane leaves goes back to the conversation, so the rail sits at the page's edge,
  /// under the buttons in the window's corner.
  @Test func aFoldedLaneSitsAtTheEdgeOfThePage() {
    let fit = TalkLayout.standard.holding(["a", "b"]).fit(in: 640)
    #expect(fit.rails.count == 1)
    #expect(fit.inset == 0)
    #expect(fit.widths["conversation"] == 640 - TalkLayout.rail - TalkLayout.gutter)
  }

  @Test func aPanelHeldOverALaneLandsBeforeTheFirstPanelBelowThePointer() {
    var frames = BoardFrames()
    frames.lanes = [
      "left": CGRect(x: 0, y: 0, width: 340, height: 800),
      "conversation": CGRect(x: 364, y: 0, width: 600, height: 800),
      "right": CGRect(x: 988, y: 0, width: 340, height: 800),
    ]
    frames.panels = [
      "/reading": CGRect(x: 12, y: 12, width: 316, height: 200),
      "radar": CGRect(x: 12, y: 224, width: 316, height: 300),
    ]
    #expect(
      Self.twoSides.drop(of: "follow", at: CGPoint(x: 100, y: 100), frames: frames, folded: []) == .lane("left", at: 0))
    #expect(
      Self.twoSides.drop(of: "follow", at: CGPoint(x: 100, y: 500), frames: frames, folded: []) == .lane("left", at: 2))
    #expect(Self.twoSides.drop(of: "follow", at: CGPoint(x: 600, y: 300), frames: frames, folded: []) == nil)
    #expect(Self.twoSides.drop(of: "follow", at: CGPoint(x: 100, y: 100), frames: frames, folded: ["left"]) == nil)
  }

  @Test func onlyPastTheConversationAtTheEndOfTheRowDoesANewLaneOpen() {
    let right = TalkLayout.standard.holding(["a", "b"])
    var frames = BoardFrames()
    frames.lanes = [
      "conversation": CGRect(x: 100, y: 0, width: 600, height: 800),
      "right": CGRect(x: 724, y: 0, width: 380, height: 800),
    ]
    #expect(right.drop(of: "b", at: CGPoint(x: 95, y: 300), frames: frames, folded: []) == .newLane(.leading))
    #expect(right.drop(of: "b", at: CGPoint(x: 1100, y: 300), frames: frames, folded: []) == .lane("right", at: 1))
  }

  @Test func theConversationTakesALanesPlaceOnceItsEdgePassesTheLanesMiddle() {
    let right = TalkLayout.standard.holding(["a"])
    var frames = BoardFrames()
    frames.lanes = ["right": CGRect(x: 724, y: 0, width: 380, height: 800)]
    #expect(right.conversationPlace(over: CGRect(x: 300, y: 0, width: 600, height: 800), frames: frames) == 0)
    #expect(right.conversationPlace(over: CGRect(x: 400, y: 0, width: 600, height: 800), frames: frames) == 1)
  }

  @Test func theLayoutIsKeptAsItWasLeft() throws {
    let data = try JSONEncoder().encode(Self.twoSides)
    #expect(try JSONDecoder().decode(TalkLayout.self, from: data) == Self.twoSides)
  }
}
