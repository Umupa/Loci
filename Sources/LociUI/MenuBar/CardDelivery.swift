import Foundation
import LociModel
import SwiftUI
import UserNotifications

/// Where a clicked notification takes the window: a card, in its home.
struct CardRoute: Equatable {
  let home: Home
  let card: EntityID
}

/// One card's notification, named by the card alone: while the card stays on the deck it is the same
/// notification, however the card is moved, reworded or put again.
struct CardNotice: Sendable {
  static let prefix = "loci.card/"

  let identifier: String
  let card: EntityID
  let home: Home
  let body: String

  init(card: NextUp) {
    self.card = card.id
    home = card.home
    body = card.what
    identifier = Self.prefix + card.id.description
  }

  var route: CardRoute { CardRoute(home: home, card: card) }

  var userInfo: [String: String] {
    ["card": card.description, "project": home.project?.description ?? ""]
  }

  /// The card a delivered notification is for; `nil` for one that is not a card's.
  static func route(of request: UNNotificationRequest) -> CardRoute? {
    guard request.identifier.hasPrefix(prefix), let text = request.content.userInfo["card"] as? String,
      let card = EntityID(canonical: text)
    else { return nil }
    let project = (request.content.userInfo["project"] as? String).flatMap(EntityID.init(canonical:))
    return CardRoute(home: Home(project), card: card)
  }
}

/// The system's notification center, or a stand-in for tests.
@MainActor protocol CardNoticeCenter {
  /// Whether it was delivered: not when the person refused notifications.
  func send(_ notice: CardNotice) async -> Bool
  func remove(_ identifiers: [String])
  func existing() async -> Set<String>
}

/// Notifies this Mac of each card the person has to deal with, a question or an approval, when it comes up on
/// the deck, whether a window is in front, minimized or only the menu bar is left; withdraws it once the card
/// leaves the deck, by being dealt with, put away, its project closed or its deadline passing. Panels and the
/// companion's messages are never notified. Clicking one asks the window to open its card (`waiting`).
@MainActor @Observable
public final class CardDelivery {
  /// The card a click asked for, until the window opened it.
  var waiting: CardRoute?
  var bringForward: (() -> Void)?

  private let center: any CardNoticeCenter
  private let defaults: UserDefaults?
  private let key = "notifiedCards"
  /// The cards notified that are still on the deck.
  private var sent: Set<String>
  private var updating = false
  private var latest: [NextUp]?
  private var observation: Task<Void, Never>?
  @ObservationIgnored private var receiver: CardNoticeReceiver?

  public convenience init() {
    self.init(center: SystemCardNoticeCenter(), defaults: .standard)
  }

  init(center: any CardNoticeCenter, defaults: UserDefaults?) {
    self.center = center
    self.defaults = defaults
    sent = Set(defaults?.stringArray(forKey: key) ?? [])
  }

  /// Takes the clicks on Loci's notifications, and shows them even with Loci in front.
  public func receiveClicks() {
    let receiver = CardNoticeReceiver(delivery: self)
    self.receiver = receiver
    UNUserNotificationCenter.current().delegate = receiver
  }

  /// Follows the decks of every home on `host`, this Mac's.
  public func watch(_ host: any LociModel.Host) {
    observation?.cancel()
    observation = Task { [weak self] in
      for await feed in host.subscribe(WatchNextUps(of: .chat)) {
        guard !Task.isCancelled, let self else { return }
        if let cards = feed.value { await self.update(cards) }
      }
    }
  }

  /// Takes the deck as it is now. A card is notified when it comes onto the deck to be dealt with: new, or back
  /// from later; not again while it stays there, kept, moved to the top or changed. Its notification goes once
  /// it is kept or leaves the deck. Decks that come while one is being taken wait, and only the latest is taken.
  func update(_ cards: [NextUp]) async {
    guard !updating else {
      latest = cards
      return
    }
    updating = true
    var next: [NextUp]? = cards
    while let cards = next {
      await take(cards)
      next = latest
      latest = nil
    }
    updating = false
  }

  private func take(_ cards: [NextUp]) async {
    let open = cards.filter { card in
      switch card.execution {
      case .waiting, .targetGone, .choosing: true
      case .writing, .made, .undoing: false
      }
    }
    let onDeck = Set(open.map { CardNotice(card: $0).identifier })
    let notices = open.filter { $0.place == .new }.map(CardNotice.init)
    let live = Set(notices.map(\.identifier))
    let owned = await center.existing().filter { $0.hasPrefix(CardNotice.prefix) }
    let removed = owned.subtracting(live)
    if !removed.isEmpty { center.remove(Array(removed)) }
    sent.formIntersection(onDeck)
    sent.formUnion(owned.intersection(live))
    for notice in notices where !sent.contains(notice.identifier) {
      if await center.send(notice) { sent.insert(notice.identifier) }
    }
    defaults?.set(Array(sent), forKey: key)
  }

  func open(_ route: CardRoute) {
    waiting = route
    bringForward?()
  }
}

@MainActor
private struct SystemCardNoticeCenter: CardNoticeCenter {
  func send(_ notice: CardNotice) async -> Bool {
    let center = UNUserNotificationCenter.current()
    let status = await center.notificationSettings().authorizationStatus
    if status == .notDetermined, (try? await center.requestAuthorization(options: [.alert])) != true { return false }
    if status == .denied { return false }
    let content = UNMutableNotificationContent()
    content.title = String(localized: .loci("companion.title"))
    content.body = notice.body
    content.userInfo = notice.userInfo
    do {
      try await center.add(UNNotificationRequest(identifier: notice.identifier, content: content, trigger: nil))
      return true
    } catch { return false }
  }

  func remove(_ identifiers: [String]) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  func existing() async -> Set<String> {
    let center = UNUserNotificationCenter.current()
    let pending = await center.pendingNotificationRequests().map(\.identifier)
    let delivered = await center.deliveredNotifications().map(\.request.identifier)
    return Set(pending + delivered)
  }
}

/// Shows a card notification even with Loci in front, and opens the card that was clicked.
final class CardNoticeReceiver: NSObject, UNUserNotificationCenterDelegate, Sendable {
  let delivery: CardDelivery

  init(delivery: CardDelivery) {
    self.delivery = delivery
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list]
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
      let route = CardNotice.route(of: response.notification.request)
    else { return }
    await delivery.open(route)
  }
}

extension View {
  public func openingCardNotifications(_ delivery: CardDelivery) -> some View {
    modifier(CardNotificationWindow(delivery: delivery))
  }
}

private struct CardNotificationWindow: ViewModifier {
  @Environment(\.openWindow) private var openWindow
  let delivery: CardDelivery

  func body(content: Content) -> some View {
    content
      .environment(\.cardDelivery, delivery)
      .onAppear {
        let action = openWindow
        delivery.bringForward = { MainWindow.bringForward(open: action) }
      }
  }
}

extension EnvironmentValues {
  @Entry var cardDelivery: CardDelivery?
}
