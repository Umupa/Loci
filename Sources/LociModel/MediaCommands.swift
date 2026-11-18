/// The media section of the settings as it is now.
public struct ReadMediaSetup: Command {
  public static let name = "media.setup"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> MediaSetup {
    try await handler.mediaSetup()
  }
}

/// Where each component is and which version; `again` looks afresh, for one installed since.
public struct DetectComponents: Command {
  public static let name = "media.components"
  public let again: Bool

  public init(again: Bool) {
    self.again = again
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> [ComponentStatus] {
    await handler.detectComponents(again: again)
  }
}

/// Downloads the latest version into Loci's own folder, installing or updating it. Returns at once; the
/// progress is in `MediaSettings`, and jobs waiting for it carry on when it is done.
public struct InstallComponent: Command {
  public static let name = "media.installComponent"
  public let component: Component

  public init(_ component: Component) {
    self.component = component
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.installComponent(component)
  }
}

/// Downloads a speech model. Returns at once; the progress is in `MediaSettings`, and jobs waiting for it
/// carry on when it is done.
public struct DownloadSpeechModel: Command {
  public static let name = "media.downloadModel"
  public let model: SpeechModel

  public init(_ model: SpeechModel) {
    self.model = model
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.downloadSpeechModel(model)
  }
}

public struct DeleteSpeechModel: Command {
  public static let name = "media.deleteModel"
  public let model: SpeechModel

  public init(_ model: SpeechModel) {
    self.model = model
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.deleteSpeechModel(model)
  }
}

/// The model recognition uses from now on.
public struct SetSpeechModel: Command {
  public static let name = "media.setModel"
  public let model: SpeechModel

  public init(_ model: SpeechModel) {
    self.model = model
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> MediaSetup {
    try await handler.setSpeechModel(model)
  }
}

/// Which browser's signed-in cookies fetching borrows; jobs waiting for a sign-in try again.
public struct SetBrowserLogin: Command {
  public static let name = "media.setBrowserLogin"
  public let login: BrowserLogin

  public init(_ login: BrowserLogin) {
    self.login = login
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> MediaSetup {
    try await handler.setBrowserLogin(login)
  }
}

/// The built-in browser's cookies, so fetching signs in as the reader did there. Replaces those handed over
/// before; jobs waiting for a sign-in try again.
public struct HandOverBrowserCookies: Command {
  public static let name = "media.cookies"
  public let cookies: [BrowserCookie]

  public init(_ cookies: [BrowserCookie]) {
    self.cookies = cookies
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.handOverBrowserCookies(cookies)
  }
}
