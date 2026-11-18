import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func mediaSetup() async throws(HostError) -> MediaSetup {
    let settings = try attempt { try store.settings() }
    return await library.context.equipment.setup(
      speechModel: settings.speechModel ?? .recommended, browserLogin: settings.browserLogin)
  }

  public func detectComponents(again: Bool) async -> [ComponentStatus] {
    let found = await library.context.equipment.components(again: again).map(\.status)
    if again {
      await library.queue.wake { if case .component = $0 { true } else { false } }
      await follow([.media])
    }
    return found
  }

  public func installComponent(_ component: Component) async throws(HostError) -> Done {
    let library = library
    await hub.hold(
      Task {
        await library.context.equipment.install(component)
        await library.queue.wake { if case .component = $0 { true } else { false } }
      })
    return Done()
  }

  public func downloadSpeechModel(_ model: SpeechModel) async throws(HostError) -> Done {
    let library = library
    await hub.hold(
      Task {
        await library.context.equipment.download(model)
        await library.queue.wake { $0 == .speechModel(model) }
      })
    return Done()
  }

  public func deleteSpeechModel(_ model: SpeechModel) async throws(HostError) -> Done {
    do {
      try await library.context.equipment.delete(model)
    } catch {
      throw HostError(error)
    }
    return Done()
  }

  public func setSpeechModel(_ model: SpeechModel) async throws(HostError) -> MediaSetup {
    _ = try attempt { try store.changeSettings { $0.speechModel = model } }
    await library.queue.wake { if case .speechModel = $0 { true } else { false } }
    await follow([.media])
    return try await mediaSetup()
  }

  public func setBrowserLogin(_ login: BrowserLogin) async throws(HostError) -> MediaSetup {
    _ = try attempt { try store.changeSettings { $0.browserLogin = login } }
    await library.queue.wake { if case .login = $0 { true } else { false } }
    await follow([.media])
    return try await mediaSetup()
  }

  public func handOverBrowserCookies(_ cookies: [BrowserCookie]) async throws(HostError) -> Done {
    do {
      try await library.context.equipment.saveCookies(cookies)
    } catch {
      throw HostError(error)
    }
    await library.queue.wake { if case .login = $0 { true } else { false } }
    return Done()
  }
}
