import Foundation
import Testing

@testable import LociModel

/// Projects carry their home on the wire and in the inbox so that what an older Mac or an older database
/// wrote reads as the chat's.
struct ProjectTests {
  static let project = Fixture.id(40)

  @Test func eventSourceWrittenBeforeProjectsReadsAsTheChat() throws {
    let schedule = try Fixture.decode(Event.Source.self, #"{"schedule":{"_0":"\#(Fixture.item)"}}"#)
    let panel = try Fixture.decode(Event.Source.self, #"{"panel":{"_0":"news","asked":true}}"#)
    let review = try Fixture.decode(Run.Kind.self, #"{"review":{"_0":"2026-11-20"}}"#)

    #expect(schedule == .schedule(Fixture.item, project: nil))
    #expect(panel.panel == PanelRef("news"))
    #expect(review.home == .chat)
  }

  @Test func theChatsEventKeysStayAsTheyWere() {
    let due = Fixture.instant
    let event = Event(id: Fixture.id(2), source: .panel(PanelRef("news"), asked: false), due: due)

    #expect(event.key == "panel/news/\(due)")
  }

  @Test func aProjectsPanelEventHasItsOwnKey() {
    let due = Fixture.instant
    let chat = Event(id: Fixture.id(2), source: .panel(PanelRef("news"), asked: false), due: due)
    let project = Event(
      id: Fixture.id(3), source: .panel(PanelRef("news", in: .project(Self.project)), asked: false), due: due)

    #expect(project.key != chat.key)
    #expect(project.source.home == .project(Self.project))
    #expect(project.source.schedule?.key == "projects/\(Self.project)/panel/news")
  }

  @Test func panelCommandsFromAnOlderMacActOnTheChat() throws {
    let refresh = try Fixture.decode(RefreshPanel.self, #"{"panel":"news"}"#)
    let column = try Fixture.decode(WatchPanelColumn.self, "{}")

    #expect(refresh.ref == PanelRef("news"))
    #expect(column.home == .chat)
  }

  @Test func aProjectsPanelCommandSurvivesTheWire() throws {
    let command = EditPanel(PanelRef("plan", in: .project(Self.project)), .remove("a"))

    #expect(try Fixture.roundTrip(command).ref == command.ref)
  }

  @Test func aProjectsSealIsTheFirstCharacterOfItsName() {
    let made = Project(id: Self.project, name: " investing", createdAt: Fixture.instant)

    #expect(made.seal == "I")
    #expect(made.with(name: "投资").seal == "投")
    #expect(made.with(name: .some(nil)).seal == "")
  }

  @Test func aProjectsConversationNotesUnderItsOwnTag() {
    let conversation = ConversationRef.project(Self.project)

    #expect(conversation.tag == "projects/\(Self.project)")
    #expect(ConversationRef(tag: conversation.tag) == conversation)
    #expect(conversation.home == .project(Self.project))
    #expect(ConversationRef.item(Fixture.item).home == .chat)
  }
}
