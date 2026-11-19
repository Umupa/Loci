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

  @Test func aCallReadsBackAsItWasSent() throws {
    let call = LocalCall(conversation: .item(Fixture.item), request: .itemFolder(Fixture.item))
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
