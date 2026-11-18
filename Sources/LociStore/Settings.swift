import Foundation
import LociModel

/// `settings.json` at the top of the Loci folder: choices that belong to this host.
public struct HostSettings: Hashable, Sendable {
  /// What Loci runs on; `nil` until one is chosen.
  public var runtime: Runtime?
  /// The Whisper model recognition uses; `nil` until one is chosen.
  public var speechModel: SpeechModel?
  public var browserLogin: BrowserLogin = .none

  public init() {}
}

extension HostSettings: Codable {
  private enum CodingKeys: String, CodingKey {
    case runtime, speechModel, browserLogin
  }

  /// A setting that cannot be read is left unchosen rather than losing the others.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    runtime = try? container.decodeIfPresent(Runtime.self, forKey: .runtime)
    speechModel = try? container.decodeIfPresent(SpeechModel.self, forKey: .speechModel)
    browserLogin = (try? container.decodeIfPresent(BrowserLogin.self, forKey: .browserLogin)) ?? BrowserLogin.none
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(runtime, forKey: .runtime)
    try container.encodeIfPresent(speechModel, forKey: .speechModel)
    if browserLogin != .none { try container.encode(browserLogin, forKey: .browserLogin) }
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
