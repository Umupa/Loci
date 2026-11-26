import Foundation
import Testing

@testable import LociModel

/// A Mac paired with one a version older or newer still reads a conversation: what the companion says on its
/// own reaches an older Mac as an ordinary reply, and a conversation from an older host reads as it was.
struct ConversationCompatibilityTests {
  /// A conversation as 1.8.3 sends it.
  static let olderConversation = """
    {"ref":{"main":{}},"entries":[{"message":{"_0":{"id":"019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e0f",
     "at":"2025-11-17T01:00:00.000Z","body":{"reply":{"_0":"好"}}}}}]}
    """

  /// The kinds of message body 1.8.3 can read.
  static let olderBodies: Set<String> = [
    "prompt", "reply", "thinking", "tool", "savedToNote", "savedItem", "notice", "ended", "startedOver",
  ]

  static let id = EntityID("019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e0f") ?? EntityID()
  static let at = Timestamp(millisecondsSince1970: 1_763_341_200_000)

  @Test func aConversationFromAnOlderHostReadsAsItWas() throws {
    let conversation = try JSONDecoder().decode(Conversation.self, from: Data(Self.olderConversation.utf8))

    #expect(conversation.entries == [.message(Message(id: Self.id, at: Self.at, body: .reply("好")))])
  }

  @Test func anOlderMacsRequestIsAnsweredWithWhatTheCompanionToldAsAReply() throws {
    let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(OneConversation(.main)))
    var older = try #require(sent as? [String: Any])
    #expect(older.removeValue(forKey: "shape") != nil)
    let request = try JSONDecoder().decode(
      OneConversation.self, from: JSONSerialization.data(withJSONObject: older))
    #expect(request.shape == nil && request.conversation == .main)

    let conversation = Conversation(
      ref: .main,
      entries: [.message(Message(id: Self.id, at: Self.at, body: .told("修好了溢价的数据源。")))], turn: nil)
    let shown = try JSONSerialization.jsonObject(with: JSONEncoder().encode(conversation.forOlderMacs))
    let entries = try #require((shown as? [String: Any])?["entries"] as? [[String: Any]])
    let bodies = entries.compactMap {
      (($0["message"] as? [String: Any])?["_0"] as? [String: Any])?["body"] as? [String: Any]
    }

    #expect(Set(bodies.flatMap(\.keys)).isSubset(of: Self.olderBodies))
    #expect(
      conversation.forOlderMacs.entries == [.message(Message(id: Self.id, at: Self.at, body: .reply("修好了溢价的数据源。")))])
  }
}
