import Foundation
import LociModel

/// `settings.json` at the top of the Loci folder: choices that belong to this host, not to one mentor.
private struct HostSettings: Codable {
  var newMentors: AgentChoice?
}

extension Store {
  static let settingsFile = "settings.json"

  private var settingsURL: URL { root.appending(path: Self.settingsFile) }

  /// The agent new mentors run on, or `nil` when none has been chosen.
  public func newMentorAgent() throws -> AgentChoice? {
    do {
      return try decodeJSON(HostSettings.self, at: settingsURL).newMentors
    } catch StoreError.notFound {
      return nil
    }
  }

  /// Rewrites `settings.json` with the choice. A file that cannot be read is replaced.
  public func save(newMentorAgent choice: AgentChoice) throws {
    var settings = (try? decodeJSON(HostSettings.self, at: settingsURL)) ?? HostSettings()
    settings.newMentors = choice
    try write(Formats.document(settings), to: settingsURL)
  }
}
