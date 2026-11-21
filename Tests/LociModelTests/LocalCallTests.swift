import Foundation
import Testing

@testable import LociModel

struct LocalCallTests {
  @Test func aConversationIsNamedByItsNoteTag() throws {
    let item = Fixture.item
    #expect(ConversationRef.main.tag == "main")
    #expect(ConversationRef.item(item).tag == "library/\(item)")
    #expect(ConversationRef(tag: "main") == .main)
    #expect(ConversationRef(tag: "library/\(item)") == .item(item))
    #expect(ConversationRef(tag: "review") == nil)
    #expect(ConversationRef(tag: "library/x") == nil)
  }

  @Test func aSessionIsNamedByItsTag() throws {
    let refresh = Fixture.id(7)
    #expect(LocalSession(tag: "main") == .conversation(.main))
    #expect(LocalSession(tag: "library/\(Fixture.item)") == .conversation(.item(Fixture.item)))
    #expect(LocalSession.panelRefresh(refresh).tag == "panel-refresh/\(refresh)")
    #expect(LocalSession(tag: "panel-refresh/\(refresh)") == .panelRefresh(refresh))
    #expect(LocalSession(tag: "panel-refresh/radar") == nil)
    #expect(LocalSession(tag: "review") == nil)
    #expect(LocalSession.panelRefresh(refresh).conversation == nil)
  }

  @Test func aCallReadsBackAsItWasSent() throws {
    let call = LocalCall(session: .conversation(.item(Fixture.item)), request: .itemFolder(Fixture.item))
    #expect(
      try HostCodingTests.roundTrips(
        LocalCall(session: .panelRefresh(Fixture.id(7)), request: .itemFolder(Fixture.item))))
    let read = try JSONDecoder().decode(LocalCall.self, from: try JSONEncoder().encode(call))
    #expect(read == call)
  }

  @Test func addingTextFromAnOlderMacStillReads() throws {
    let older = Data(##"{"fileName":"a.md","text":"# A"}"##.utf8)
    let command = try JSONDecoder().decode(AddTextItem.self, from: older)
    #expect(command.title == nil)
    #expect(command.authors.isEmpty)
  }
}
