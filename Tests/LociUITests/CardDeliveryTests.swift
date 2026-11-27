import LociModel
import Testing

@testable import LociUI

/// WT-S7, WT-S8: a card to deal with is notified once when it comes up, withdrawn once it leaves the deck, and
/// the notification opens its card where it is.
@MainActor
struct CardDeliveryTests {
  @Test func onlyNewNeedsAttentionCardsAreSentAndAnExpiredOneIsWithdrawn() async throws {
    let studio = RecordingCardCenter()
    let delivery = CardDelivery(center: studio, defaults: nil)
    let card = NextUpSnapshots.cards[0]
    let kept = NextUpSnapshots.cards[1].with(place: .kept)
    await delivery.update([card, kept])
    await delivery.update([card.with(what: "Updated")])
    #expect(studio.sent.map(\.card) == [card.id])
    await delivery.update([])
    #expect(studio.removed == studio.sent.map(\.identifier))
  }

  @Test func aCardBackFromLaterIsSentAgainAndOneRefusedByTheSystemIsTriedAgain() async throws {
    let studio = RecordingCardCenter()
    let delivery = CardDelivery(center: studio, defaults: nil)
    let card = NextUpSnapshots.cards[0]
    studio.allowed = false
    await delivery.update([card])
    #expect(studio.sent.isEmpty)

    studio.allowed = true
    await delivery.update([card])
    await delivery.update([])
    await delivery.update([card.with(place: .new, shownAt: Timestamp(millisecondsSince1970: 9_000_000_000_000))])
    #expect(studio.sent.map(\.card) == [card.id, card.id])
  }

  @Test func aCardStillOnTheDeckIsNotSentAgainWhenClickedMovedChangedOrKept() async throws {
    let studio = RecordingCardCenter()
    let delivery = CardDelivery(center: studio, defaults: nil)
    let card = NextUpSnapshots.cards[0]
    await delivery.update([card])
    studio.clicked(CardNotice(card: card).identifier)
    let later = Timestamp(millisecondsSince1970: card.shownAt.millisecondsSince1970 + 4_000)

    await delivery.update([card.with(version: card.version + 1, shownAt: later)])
    await delivery.update([card.with(what: "put again", version: card.version + 2, shownAt: later)])
    await delivery.update([card.with(place: .kept)])
    await delivery.update([card.with(place: .new)])

    #expect(studio.sent.count == 1)
  }

  @Test func decksThatComeWhileOneIsBeingTakenSendTheCardOnce() async throws {
    let studio = RecordingCardCenter()
    let delivery = CardDelivery(center: studio, defaults: nil)
    let card = NextUpSnapshots.cards[0]
    studio.holding = true
    let first = Task { await delivery.update([card]) }
    while studio.asked == 0 { await Task.yield() }
    await delivery.update([card.with(version: card.version + 1)])
    await delivery.update([card.with(version: card.version + 2)])
    studio.holding = false
    await first.value

    #expect(studio.sent.count == 1)
    #expect(studio.asked == 1)
  }

  @Test func aNotificationOpensItsExactCardAndHome() {
    let delivery = CardDelivery(center: RecordingCardCenter(), defaults: nil)
    let card = NextUpSnapshots.cards[0]
    var opened = 0
    delivery.bringForward = { opened += 1 }

    let notice = CardNotice(card: card)
    delivery.open(notice.route)
    #expect(opened == 1)
    #expect(delivery.waiting?.card == card.id)
    #expect(delivery.waiting?.home == card.home)
  }
}

@MainActor
private final class RecordingCardCenter: CardNoticeCenter {
  var sent: [CardNotice] = []
  var removed: [String] = []
  /// Notifications the person clicked, which the system takes out of the center.
  var gone: Set<String> = []
  /// Whether the person let Loci notify them.
  var allowed = true
  /// Holds each send, as the system does while it asks the person to allow notifications.
  var holding = false
  var asked = 0

  func send(_ notice: CardNotice) async -> Bool {
    asked += 1
    while holding { await Task.yield() }
    guard allowed else { return false }
    sent.append(notice)
    return true
  }

  func clicked(_ identifier: String) { gone.insert(identifier) }

  func remove(_ identifiers: [String]) { removed += identifiers }
  func existing() async -> Set<String> { Set(sent.map(\.identifier)).subtracting(removed).subtracting(gone) }
}
