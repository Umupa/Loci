import Foundation

/// Where a video or audio item plays from.
public enum Playback: Hashable, Codable, Sendable {
  /// The file is on the host: this Mac plays it from `Host.localFile(.media(item))`, another Mac reads it
  /// in ranges with `ReadMediaBytes`.
  case downloaded
  /// Straight from the site while the download runs.
  case online(OnlineStream)
}

/// An address the player can open directly. Sites hand these out for a few hours; ask again with `refresh`
/// once it stops working, and carry on from the same second.
public struct OnlineStream: Hashable, Codable, Sendable {
  public let url: URL
  /// Headers the site wants with every request, such as a `Referer`.
  public let headers: [String: String]
  /// Only the sound; the picture comes once the download is done.
  public let audioOnly: Bool
  /// When the site said the address stops working, if it said.
  public let expires: Timestamp?

  public init(url: URL, headers: [String: String] = [:], audioOnly: Bool, expires: Timestamp? = nil) {
    self.url = url
    self.headers = headers
    self.audioOnly = audioOnly
    self.expires = expires
  }
}

/// What the reader of a video or audio item sees beside the player.
public struct MediaPage: Hashable, Codable, Sendable {
  /// Grows sentence by sentence while speech is being recognized.
  public let transcript: Transcript?
  /// Only translations that fit the transcript.
  public let translations: [Translation]
  public let outline: Outline?
  public let hasCover: Bool
  /// The media is on the host, so it plays without the network.
  public let downloaded: Bool

  public init(
    transcript: Transcript?, translations: [Translation], outline: Outline?, hasCover: Bool, downloaded: Bool
  ) {
    self.transcript = transcript
    self.translations = translations
    self.outline = outline
    self.hasCover = hasCover
    self.downloaded = downloaded
  }
}

/// The media section of the settings: components, speech models and how sites are signed in to.
public struct MediaSetup: Hashable, Codable, Sendable {
  /// One per component, in `Component.allCases` order.
  public let components: [ComponentStatus]
  /// Components being installed or updated, and those whose last attempt failed.
  public let componentWork: [ComponentWork]
  /// One per model, in `SpeechModel.allCases` order.
  public let speechModels: [SpeechModelStatus]
  /// The model recognition uses.
  public let speechModel: SpeechModel
  public let browserLogin: BrowserLogin

  public init(
    components: [ComponentStatus], componentWork: [ComponentWork], speechModels: [SpeechModelStatus],
    speechModel: SpeechModel, browserLogin: BrowserLogin
  ) {
    self.components = components
    self.componentWork = componentWork
    self.speechModels = speechModels
    self.speechModel = speechModel
    self.browserLogin = browserLogin
  }
}

/// A component being installed, or one that failed to install.
public struct ComponentWork: Hashable, Codable, Sendable {
  public let component: Component
  public let state: Transfer

  public init(component: Component, state: Transfer) {
    self.component = component
    self.state = state
  }
}

public struct SpeechModelStatus: Hashable, Codable, Sendable {
  public let model: SpeechModel
  public let state: State

  public init(model: SpeechModel, state: State) {
    self.model = model
    self.state = state
  }

  public enum State: Hashable, Codable, Sendable {
    case absent
    case transferring(Transfer)
    case ready
  }
}

/// A download in progress, or the reason the last one stopped.
public enum Transfer: Hashable, Codable, Sendable {
  /// `nil` when the size is not known.
  case running(Fraction?)
  case failed(String)
}

/// Whose signed-in cookies yt-dlp borrows for sites that want a signed-in visitor.
public enum BrowserLogin: String, CaseIterable, Hashable, Codable, Sendable {
  case none
  case safari
  case chrome
  case firefox
  case edge
  case brave
  case chromium
  case opera
  case vivaldi
}

/// A cookie from the built-in browser, handed over so fetching can sign in as the reader did.
public struct BrowserCookie: Hashable, Codable, Sendable {
  public let domain: String
  public let path: String
  public let name: String
  public let value: String
  public let secure: Bool
  /// `nil` for a cookie that lasts until the browser closes.
  public let expires: Timestamp?
  /// Pages' scripts cannot read it.
  public let httpOnly: Bool

  public init(
    domain: String, path: String, name: String, value: String, secure: Bool, expires: Timestamp?,
    httpOnly: Bool = false
  ) {
    self.domain = domain
    self.path = path
    self.name = name
    self.value = value
    self.secure = secure
    self.expires = expires
    self.httpOnly = httpOnly
  }
}

extension BrowserCookie {
  private enum CodingKeys: String, CodingKey {
    case domain, path, name, value, secure, expires, httpOnly
  }

  /// A cookie from a Mac that did not send `httpOnly` is readable by scripts, as it was there.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      domain: try container.decode(String.self, forKey: .domain),
      path: try container.decode(String.self, forKey: .path),
      name: try container.decode(String.self, forKey: .name), value: try container.decode(String.self, forKey: .value),
      secure: try container.decode(Bool.self, forKey: .secure),
      expires: try container.decodeIfPresent(Timestamp.self, forKey: .expires),
      httpOnly: try container.decodeIfPresent(Bool.self, forKey: .httpOnly) ?? false)
  }
}

/// How an imported file joins the library.
public enum ImportMode: String, Hashable, Codable, Sendable {
  /// Copied into the item's folder; the original can go.
  case copy
  /// Pointed at where it is; moving or deleting the original breaks the item.
  case link
}
