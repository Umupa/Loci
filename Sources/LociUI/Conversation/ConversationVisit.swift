import LociModel
import SwiftUI

@MainActor @Observable
final class ConversationVisit {
  @ObservationIgnored var reading: TalkRow.ID?
}

@MainActor
final class ConversationVisits {
  private var visits: [Home: ConversationVisit] = [:]

  func visit(for home: Home) -> ConversationVisit {
    if let visit = visits[home] { return visit }
    let visit = ConversationVisit()
    visits[home] = visit
    return visit
  }
}
