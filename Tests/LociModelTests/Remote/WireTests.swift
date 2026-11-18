import LociModel
import Testing

struct WireTests {
  @Test func everyCommandAndSubscriptionHasAUniqueWireName() {
    let names = Wire.commands.map(\.name) + Wire.subscriptions.map { $0.name }

    #expect(Set(names).count == names.count)
  }

  @Test func bytesTravelOnTheDataConnection() {
    #expect(Wire.route(of: ReadItemPDF.self)?.lane == .data)
    #expect(Wire.route(of: ReadMediaBytes.self)?.lane == .data)
    #expect(Wire.route(of: SetAvatar.self)?.lane == .data)
    #expect(Wire.route(of: SendMessage.self)?.lane == .control)
  }

  @Test func onlyReadsCanBeAnsweredFromWhatWasSeenBefore() {
    #expect(Wire.route(of: ListItems.self)?.effect == .reads)
    #expect(Wire.route(of: SendMessage.self)?.effect == .writes)
    #expect(Wire.route(of: DeleteItem.self)?.effect == .writes)
  }
}
