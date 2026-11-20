import Foundation
import LociModel

/// `settings.json` at the top of the Loci folder: choices that belong to this host.
public struct HostSettings: Hashable, Sendable {
  /// What Loci runs on; `nil` until one is chosen.
  public var runtime: Runtime?
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
    case runtime, speechModel, browserLogin, importChoice, keyPointChoice
  }

  /// A setting that cannot be read is left unchosen rather than losing the others.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    runtime = try? container.decodeIfPresent(Runtime.self, forKey: .runtime)
    speechModel = try? container.decodeIfPresent(SpeechModel.self, forKey: .speechModel)
    browserLogin = (try? container.decodeIfPresent(BrowserLogin.self, forKey: .browserLogin)) ?? BrowserLogin.none
    importChoice = try? container.decodeIfPresent(ImportChoice.self, forKey: .importChoice)
    keyPointChoice = try? container.decodeIfPresent(KeyPointChoice.self, forKey: .keyPointChoice)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(runtime, forKey: .runtime)
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
