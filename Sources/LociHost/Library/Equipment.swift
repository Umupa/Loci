import Foundation
import LociMedia
import LociModel
import LociStore

/// The components and speech models on this Mac, and the installs and downloads under way. Each step of an
/// install is reported as a `.media` change, so the settings show it as it goes.
actor Equipment {
  private let environment: MediaEnvironment
  private let support: Support
  private let notify: @Sendable (Set<ContentChange>) async -> Void
  private var located: [Component: LocatedComponent] = [:]
  private var componentWork: [Component: Transfer] = [:]
  private var modelWork: [SpeechModel: Transfer] = [:]

  init(environment: MediaEnvironment, notify: @escaping @Sendable (Set<ContentChange>) async -> Void) {
    self.environment = environment
    support = Support(root: environment.support)
    self.notify = notify
  }

  private var locator: ComponentLocator {
    let support = support
    return ComponentLocator(
      managed: support.components, searchPaths: environment.searchPaths, isExecutable: { support.isExecutable($0) },
      runner: environment.runner)
  }

  /// Every component; `again` looks afresh instead of trusting what was found before.
  func components(again: Bool) async -> [LocatedComponent] {
    var found: [LocatedComponent] = []
    for component in Component.allCases { found.append(await locate(component, again: again)) }
    return found
  }

  /// The program to run for a component, or `nil` when it is missing or being installed.
  func executable(_ component: Component) async -> URL? {
    if case .running = componentWork[component] { return nil }
    return await locate(component, again: false).executable
  }

  private func locate(_ component: Component, again: Bool) async -> LocatedComponent {
    if !again, let known = located[component] { return known }
    let found = await locator.locate(component)
    located[component] = found
    return found
  }

  /// Downloads the latest version into Loci's folder. Returns once it is installed or has failed; either
  /// way the settings hear of it.
  func install(_ component: Component) async {
    if case .running = componentWork[component] { return }
    await report(component, .running(nil))
    do throws(FetchError) {
      try await download(component)
      componentWork[component] = nil
      located[component] = await locator.locate(component)
      await notify([.media])
    } catch {
      await report(component, .failed(error.reason))
    }
  }

  private func download(_ component: Component) async throws(FetchError) {
    let package = ComponentPackage.of(component, arm: environment.arm)
    var lastFailure = FetchError(reason: "no address to download \(component.rawValue) from")
    for url in package.urls {
      do throws(FetchError) {
        let file = try await environment.network.download(URLRequest(url: url)) { [weak self] share in
          Task { await self?.progress(component, share) }
        }
        defer { support.discard(file) }
        try await place(file, as: component, archive: package.isArchive)
        return
      } catch {
        lastFailure = error
      }
    }
    throw lastFailure
  }

  private func place(_ file: URL, as component: Component, archive: Bool) async throws(FetchError) {
    do {
      if archive {
        let folder = try support.scratchFolder()
        do throws(FetchError) {
          try await ComponentPackage.unpack(file, into: folder, runner: environment.runner)
        } catch {
          support.discard(folder)
          throw error
        }
        try support.installComponent(component, unpacked: folder, executable: component.managedExecutable)
      } else {
        let folder = try support.stage(file, as: component.managedExecutable)
        try support.installComponent(component, unpacked: folder, executable: component.managedExecutable)
      }
    } catch let error as FetchError {
      throw error
    } catch {
      throw FetchError(reason: error.localizedDescription)
    }
  }

  private func progress(_ component: Component, _ share: Fraction?) async {
    guard case .running(let before) = componentWork[component], Self.moved(from: before, to: share) else { return }
    await report(component, .running(share))
  }

  private func report(_ component: Component, _ state: Transfer) async {
    componentWork[component] = state
    await notify([.media])
  }

  func modelFile(_ model: SpeechModel) -> URL? {
    if case .transferring(.running) = modelState(model) { return nil }
    return support.hasModel(model.fileName) ? support.modelFile(model.fileName) : nil
  }

  private func modelState(_ model: SpeechModel) -> SpeechModelStatus.State {
    if let work = modelWork[model] {
      if case .failed = work, support.hasModel(model.fileName) { return .ready }
      return .transferring(work)
    }
    return support.hasModel(model.fileName) ? .ready : .absent
  }

  /// Returns once the model is in place or the download has failed.
  func download(_ model: SpeechModel) async {
    if case .running = modelWork[model] { return }
    await report(model, .running(nil))
    do throws(FetchError) {
      let file = try await environment.network.download(URLRequest(url: model.source)) { [weak self] share in
        Task { await self?.progress(model, share) }
      }
      do {
        try support.installModel(file, as: model.fileName)
      } catch {
        support.discard(file)
        throw FetchError(reason: error.localizedDescription)
      }
      modelWork[model] = nil
      await notify([.media])
    } catch {
      await report(model, .failed(error.reason))
    }
  }

  /// The models on the disk, with what each takes.
  func modelSpace() -> [ModelSpace] {
    SpeechModel.allCases.compactMap { model in
      guard let file = modelFile(model),
        let size = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
      else { return nil }
      return ModelSpace(model: model, bytes: Int64(size.totalFileAllocatedSize ?? size.fileSize ?? 0))
    }
  }

  func delete(_ model: SpeechModel) async throws {
    try support.deleteModel(model.fileName)
    modelWork[model] = nil
    await notify([.media])
  }

  private func progress(_ model: SpeechModel, _ share: Fraction?) async {
    guard case .running(let before) = modelWork[model], Self.moved(from: before, to: share) else { return }
    await report(model, .running(share))
  }

  private func report(_ model: SpeechModel, _ state: Transfer) async {
    modelWork[model] = state
    await notify([.media])
  }

  func saveCookies(_ cookies: [BrowserCookie]) throws {
    try support.saveCookies(cookies)
  }

  var cookies: URL? { support.hasCookies ? support.cookies : nil }

  func setup(speechModel: SpeechModel, browserLogin: BrowserLogin) async -> MediaSetup {
    let components = await components(again: false).map(\.status)
    let work = Component.allCases.compactMap { component in
      componentWork[component].map { ComponentWork(component: component, state: $0) }
    }
    return MediaSetup(
      components: components, componentWork: work,
      speechModels: SpeechModel.allCases.map { SpeechModelStatus(model: $0, state: modelState($0)) },
      speechModel: speechModel, browserLogin: browserLogin)
  }

  /// Progress is told when it moves a whole percent, so a large download does not flood the settings.
  static func moved(from before: Fraction?, to after: Fraction?) -> Bool {
    switch (before, after) {
    case (nil, nil): false
    case (let before?, let after?): Int(after.value * 100) != Int(before.value * 100)
    default: true
    }
  }
}
