import AppKit
import Foundation
import LociModel
import Testing

@testable import LociUI

/// A-S6, A-S7, A-S10: choosing items, what a right click acts on, and renaming in place.
@MainActor
struct LibraryEditingTests {
  static let ids = (1...5).map { _ in EntityID() }

  @Test func aPlainClickOpensAndLetsGoOfWhatWasChosen() {
    var selection = LibrarySelection()
    _ = selection.click(Self.ids[0], .toggle, in: Self.ids)

    let opens = selection.click(Self.ids[1], .open, in: Self.ids)
    #expect(opens)
    #expect(selection.chosen.isEmpty)
  }

  @Test func commandClickAddsOrTakesAwayOne() {
    var selection = LibrarySelection()

    let opens = selection.click(Self.ids[0], .toggle, in: Self.ids)
    #expect(!opens)
    _ = selection.click(Self.ids[2], .toggle, in: Self.ids)
    #expect(selection.chosen == [Self.ids[0], Self.ids[2]])
    _ = selection.click(Self.ids[0], .toggle, in: Self.ids)
    #expect(selection.chosen == [Self.ids[2]])
  }

  @Test func shiftClickChoosesEverythingBetween() {
    var selection = LibrarySelection()
    _ = selection.click(Self.ids[3], .toggle, in: Self.ids)

    let opens = selection.click(Self.ids[1], .extend, in: Self.ids)
    #expect(!opens)
    #expect(selection.chosen == Set(Self.ids[1...3]))
  }

  @Test func theKeysPressedDecideTheClick() {
    #expect(LibrarySelection.Click([]) == .open)
    #expect(LibrarySelection.Click(.command) == .toggle)
    #expect(LibrarySelection.Click(.shift) == .extend)
  }

  @Test(arguments: [NSEvent.ModifierFlags.command, .shift])
  func theMouseEventsModifiersChooseWithoutOpening(modifiers: NSEvent.ModifierFlags) throws {
    let event = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseUp, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
    var selection = LibrarySelection()

    let opens = selection.click(Self.ids[1], LibrarySelection.Click(event: event), in: Self.ids)
    #expect(!opens)
    #expect(selection.chosen == [Self.ids[1]])
  }

  @Test func aRightClickActsOnTheChosenOnlyWhenTheItemIsOneOfThem() {
    var selection = LibrarySelection()
    _ = selection.click(Self.ids[0], .toggle, in: Self.ids)
    _ = selection.click(Self.ids[1], .toggle, in: Self.ids)

    #expect(Set(selection.acted(on: Self.ids[0])) == [Self.ids[0], Self.ids[1]])
    #expect(selection.acted(on: Self.ids[4]) == [Self.ids[4]])
  }

  @Test func itemsThatLeaveTheLibraryAreLetGo() {
    var selection = LibrarySelection()
    _ = selection.click(Self.ids[0], .toggle, in: Self.ids)
    _ = selection.click(Self.ids[1], .toggle, in: Self.ids)

    selection.keep([Self.ids[1]])

    #expect(selection.chosen == [Self.ids[1]])
  }

  @Test func aRenameKeepsOnlyANewTitleThatIsNotEmpty() {
    #expect(TitleField.kept("  Raft 共识 ", over: "Raft") == "Raft 共识")
    #expect(TitleField.kept("   ", over: "Raft") == nil)
    #expect(TitleField.kept("Raft", over: "Raft") == nil)
  }
}
