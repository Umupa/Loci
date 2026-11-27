import Foundation
import LociModel

/// `settings.json` at the top of the Loci folder: choices that belong to this host.
public struct HostSettings: Hashable, Sendable {
  /// What was last chosen in a conversation of each kind; a new conversation of that kind starts on it.
  public var latestRuntimes: [ConversationKind: Runtime] = [:]
  /// The Whisper model recognition uses; `nil` until one is chosen.
  public var speechModel: SpeechModel?
  public var browserLogin: BrowserLogin = .none
  /// The last way something was taken in; `nil` until the first.
  public var importChoice: ImportChoice?
  /// What key points were picked with last; `nil` until they first are.
  public var keyPointChoice: KeyPointChoice?

  public init() {}
}

extension HostSettings: Codable {
  private enum CodingKeys: String, CodingKey {
    case latestRuntimes, runtime, speechModel, browserLogin, importChoice, keyPointChoice
  }

  /// A setting that cannot be read is left unchosen rather than losing the others. The one runtime versions up to
  /// 1.8.5 kept for the whole app is what every kind of conversation last chose.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let latest = try? container.decodeIfPresent([ConversationKind: Runtime].self, forKey: .latestRuntimes) {
      latestRuntimes = latest
    } else if let old = try? container.decodeIfPresent(Runtime.self, forKey: .runtime) {
      latestRuntimes = Dictionary(uniqueKeysWithValues: ConversationKind.allCases.map { ($0, old) })
    }
    speechModel = try? container.decodeIfPresent(SpeechModel.self, forKey: .speechModel)
    browserLogin = (try? container.decodeIfPresent(BrowserLogin.self, forKey: .browserLogin)) ?? BrowserLogin.none
    importChoice = try? container.decodeIfPresent(ImportChoice.self, forKey: .importChoice)
    keyPointChoice = try? container.decodeIfPresent(KeyPointChoice.self, forKey: .keyPointChoice)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if !latestRuntimes.isEmpty { try container.encode(latestRuntimes, forKey: .latestRuntimes) }
    try container.encodeIfPresent(speechModel, forKey: .speechModel)
    if browserLogin != .none { try container.encode(browserLogin, forKey: .browserLogin) }
    try container.encodeIfPresent(importChoice, forKey: .importChoice)
    try container.encodeIfPresent(keyPointChoice, forKey: .keyPointChoice)
  }
}

extension Store {
  static let settingsFile = "settings.json"

  private var settingsURL: URL { root.appending(path: Self.settingsFile) }

  public func settings() throws -> HostSettings {
    do {
      return try decodeJSON(HostSettings.self, at: settingsURL)
    } catch StoreError.notFound {
      return HostSettings()
    }
  }

  /// Rewrites `settings.json` with the change. A file that cannot be read is replaced.
  @discardableResult
  public func changeSettings(_ change: (inout HostSettings) -> Void) throws -> HostSettings {
    var settings = (try? self.settings()) ?? HostSettings()
    change(&settings)
    try write(Formats.document(settings), to: settingsURL)
    return settings
  }
}
