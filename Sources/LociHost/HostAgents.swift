import Foundation
import LociAgents
import LociModel
import LociStore

struct HostAgents: Sendable {
  let store: Store
  let environment: HostEnvironment
  let library: LibraryContext

  struct Selection: Sendable {
    let runtime: Runtime
    var credential: ModelServices.PiCredential?

    var instructionsScope: String {
      guard runtime.provider == .bundledPi else { return "" }
      guard let credential else { return "\nbundled-pi: unconfigured" }
      return "\nbundled-pi: \(credential.service.endpoint.absoluteString) \(credential.key != nil)"
    }
  }

  var savedRuntime: Runtime? { (try? store.settings())?.runtime }
  var provisionalRuntime: Runtime { savedRuntime ?? environment.defaultRuntime }

  func chosen() async -> Runtime {
    if let savedRuntime { return savedRuntime }
    guard environment.bundledPi != nil else { return environment.defaultRuntime }
    let installed = await environment.detectAgents(false).compactMap { candidate -> Provider? in
      guard case .installed(let found) = candidate, found.provider != .fx else { return nil }
      return found.provider
    }
    if installed.contains(environment.defaultRuntime.provider) { return environment.defaultRuntime }
    return Runtime(provider: installed.first ?? .bundledPi)
  }

  func selection(_ preferred: Runtime? = nil) async -> Selection {
    let runtime = if let preferred { preferred } else { await chosen() }
    guard runtime.provider == .bundledPi, let credential = try? await library.models.piCredential() else {
      return Selection(runtime: runtime)
    }
    let service = credential.service
    let prefix = service.provider.piProvider + "/"
    let selected = runtime.model.flatMap { $0.hasPrefix(prefix) ? $0 : nil }
    let model = service.provider == .compatible ? prefix + service.model : (selected ?? prefix + service.model)
    return Selection(
      runtime: Runtime(provider: .bundledPi, model: model, effort: runtime.effort), credential: credential)
  }

  func driver(for selection: Selection) async -> (any AgentDriver)? {
    if selection.runtime.provider != .bundledPi {
      return await environment.agents(selection.runtime.provider)
    }
    return bundledDriver(credential: selection.credential)
  }

  func failure(for provider: Provider) async -> AgentStartFailure {
    if provider == .bundledPi {
      return library.equipment.support.activePi() == nil ? .notInstalled : .wouldNotStart
    }
    return await environment.unavailability(provider)
  }

  func installations(again: Bool) async -> [AgentInstallation] {
    let external = await environment.detectAgents(again)
    guard environment.bundledPi != nil else { return external }
    let bundled: AgentInstallation
    if let active = library.equipment.support.activePi() {
      let credential = try? await library.models.piCredential()
      bundled = .installed(
        .init(
          provider: .bundledPi, executable: HostPath(active.executable), version: active.version,
          signIn: credential?.key == nil ? .signedOut : .signedIn))
    } else {
      bundled = .missing(.bundledPi)
    }
    let order = Provider.allCases
    return ([bundled] + external).sorted {
      (order.firstIndex(of: $0.provider) ?? order.count) < (order.firstIndex(of: $1.provider) ?? order.count)
    }
  }

  func models(of provider: Provider) async -> [String] {
    guard provider == .bundledPi else { return await environment.models(provider) }
    guard let credential = try? await library.models.piCredential() else { return [] }
    let prefix = credential.service.provider.piProvider
    let configured = prefix + "/" + credential.service.model
    guard let driver = bundledDriver(credential: credential) else { return [configured] }
    let found = await driver.models(in: store.agentFolder, matching: prefix)
    return found.contains(configured) ? found : [configured] + found
  }

  private func bundledDriver(credential: ModelServices.PiCredential?) -> PiDriver? {
    guard let environment = environment.bundledPi, let credential, credential.key != nil,
      let active = library.equipment.support.activePi(),
      let configuration = try? library.equipment.support.preparePiConfiguration(for: credential.service)
    else { return nil }
    return environment.driver(
      executable: active.executable, directory: configuration, tool: self.environment.tool, credential: credential)
  }
}
