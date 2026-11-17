import Foundation
import LociModel

/// The automatic half of the score: what can be counted without a judge.
struct Checks: Hashable, Codable, Sendable {
  let plannedLessons: Int
  let writtenLessons: Int
  let lessonsInRange: Bool
  /// Links in lesson sources and bodies, and how many of them are on the scenario's first-party sites.
  let links: Int
  let firstPartyLinks: Int
  /// `loci://` locators in lesson bodies: citations the reader can open.
  let locators: Int
  let catalogAfterSeconds: Double?
  let firstLessonAfterSeconds: Double?
  let stoppedFirstTurn: Bool
  let failedTurns: Int
  let permissionAsks: Int
  let probeAnswered: Bool

  init(_ evidence: Evidence) {
    plannedLessons = evidence.catalog?.chapters.reduce(0) { $0 + $1.lessons.count } ?? 0
    writtenLessons = evidence.lessons.count
    lessonsInRange = evidence.scenario.lessons.contains(plannedLessons)
    let links = evidence.lessons.flatMap { $0.sources.filter(Self.isLink) + Self.links(in: $0.body) }
    self.links = links.count
    firstPartyLinks = links.count { Self.isFirstParty($0, evidence.scenario.firstParty) }
    locators = evidence.lessons.reduce(0) { $0 + $1.body.matches(of: /loci:\/\/[^\s)\]>"]+/).count }
    catalogAfterSeconds = evidence.catalogAfter
    firstLessonAfterSeconds = evidence.firstLessonAfter
    stoppedFirstTurn = evidence.stoppedFirstTurn
    failedTurns = evidence.conversation.count { if case .ended(.failed) = $0.body { true } else { false } }
    permissionAsks = evidence.conversation.count { if case .permission = $0.body { true } else { false } }
    probeAnswered = !evidence.probeAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  static func isLink(_ text: String) -> Bool {
    text.hasPrefix("http://") || text.hasPrefix("https://")
  }

  static func links(in text: String) -> [String] {
    text.matches(of: /https?:\/\/[^\s)\]>"'`]+/).map { String($0.output) }
  }

  /// Whether the link is on one of the sites, given as a host suffix or a host and path prefix.
  static func isFirstParty(_ link: String, _ sites: [String]) -> Bool {
    guard let url = URL(string: link), let host = url.host()?.lowercased() else { return false }
    let address = host + url.path()
    return sites.contains { site in
      if site.contains("/") { return address.hasPrefix(site) }
      return host == site || host.hasSuffix("." + site)
    }
  }
}
