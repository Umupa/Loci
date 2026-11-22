import Foundation
import LociHost
import LociModel
import LociStore
import Synchronization
import Testing

struct BundledPiSetupTests {
  @Test func withoutACliAFirstLaunchNeedsModelSettings() async throws {
    let place = Place()
    defer { place.remove() }
    let probes = Mutex(0)
    let host = try await LocalHost.start(
      root: place.root, database: place.database,
      environment: environment(installations: [.missing(.codex)]) { probes.withLock { $0 += 1 } })
    #expect(probes.withLock { $0 } == 0)
    #expect(await host.needsModelSetup())
    #expect(try await host.run(ReadRuntime()).provider == .bundledPi)
    #expect(await host.detectAgents(again: false).contains(.missing(.bundledPi)))
    await host.close()
  }

  @Test func codexIsAvailableAndChoosingBundledPiDoesNotReplaceIt() async throws {
    let place = Place()
    defer { place.remove() }
    let codex = AgentInstallation.installed(
      .init(
        provider: .codex, executable: HostPath(URL(filePath: "/bin/codex")), version: "1", signIn: .unknown))
    let host = try await LocalHost.start(
      root: place.root, database: place.database, environment: environment(installations: [codex]))
    #expect(await host.needsModelSetup() == false)
    #expect(try await host.run(ReadRuntime()).provider == .codex)
    #expect(try await host.run(SetRuntime(Runtime(provider: .bundledPi))).provider == .bundledPi)
    #expect(await host.detectAgents(again: false) == [.missing(.bundledPi), codex])
    #expect(try place.store.settings().runtime?.provider == .bundledPi)
    await host.close()
  }

  @Test func aSavedSystemPiStillMeansTheExternalProgram() async throws {
    let place = Place()
    defer { place.remove() }
    try place.store.changeSettings { $0.runtime = Runtime(provider: .pi) }
    let host = try await LocalHost.start(
      root: place.root, database: place.database, environment: environment(installations: []))
    #expect(await host.needsModelSetup() == false)
    #expect(try await host.run(ReadRuntime()).provider == .pi)
    await host.close()
  }

  private func environment(
    installations: [AgentInstallation], onDetect: @escaping @Sendable () -> Void = {}
  ) -> HostEnvironment {
    HostEnvironment(
      newID: { EntityID() }, now: { TestWorld.instant }, defaultRuntime: Runtime(provider: .codex),
      discard: .permanently, agents: { _ in nil },
      detectAgents: { _ in
        onDetect()
        return installations
      },
      bundledPi: BundledPiEnvironment(variables: [:]))
  }
}
