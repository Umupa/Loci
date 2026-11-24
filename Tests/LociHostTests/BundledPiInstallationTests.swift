import Foundation
import LociAgents
import LociHost
import LociMedia
import LociModel
import LociStore
import Synchronization
import Testing

struct BundledPiInstallationTests {
  @Test func savingAKeyInstallsOnceAndStartsLociWithThatKeyAndItsTools() async throws {
    try await withPiHost { host, support, platform, provider in
      _ = try await host.saveModelSettings(ModelSettings(providers: [provider]))
      let saved = try await host.setModelKey("fixture-value", for: provider.id)
      #expect(saved.keys == [provider.id])
      _ = try await host.run(InstallComponent(.bundledPi))
      let ready = await value(host.subscribe(MediaSettings())) { setup in
        setup.components.contains(ComponentStatus(component: .bundledPi, installation: .managed(version: "1.6.0")))
          && !setup.componentWork.contains { $0.component == .bundledPi }
      }
      _ = try #require(ready)
      let active = try #require(support.activePi())
      #expect(platform.downloads == 1)
      #expect(platform.commands.contains { $0.arguments.starts(with: ["--force", "-s", "-"]) })
      #expect(
        FileManager.default.fileExists(
          atPath: active.executable.deletingLastPathComponent().appending(path: "LICENSE").path))
      #expect(await host.needsModelSetup() == false)
      #expect(
        try Store(root: support.root.deletingLastPathComponent(), discard: .permanently).settings().runtime?.provider
          == .bundledPi)
      let model = ModelChoice(provider: provider.id, model: "test-model").runtimeModel
      #expect(try await host.runtime().model == model)
      #expect(await host.agentModels(of: .bundledPi) == [model, provider.id.rawValue + "/other-model"])

      _ = try await host.run(SendMessage(to: .main, text: "Reply."))
      _ = try #require(
        await value(host.subscribe(OneConversation(.main))) { conversation in
          conversation.turn == nil
            && conversation.entries.contains { entry in
              guard case .message(let message) = entry, case .reply(let text) = message.body else { return false }
              return text.contains("bundled response")
            }
        })
      let launch = try #require(
        platform.invocations.last { $0.arguments.contains("--mode") && !$0.arguments.contains("--no-session") })
      let environment = try #require(launch.environment)
      #expect(launch.executable == active.executable)
      #expect(launch.arguments.contains("loci-model/test-model"))
      #expect(environment["LOCI_MODEL_API_KEY"] == "fixture-value")
      #expect(environment["OPENAI_API_KEY"] == nil)
      #expect(environment["LOCI"]?.hasSuffix("/loci") == true)
      #expect(environment["LOCI_SOCKET"] != nil)
      #expect(environment["LOCI_SESSION"] != nil)
      #expect(environment["PI_CODING_AGENT_DIR"]?.contains("/bundled-pi/") == true)
    }
  }

  /// M-S13
  @Test func theCompanionRunsOnTheModelChosenForItWhateverTranslationUses() async throws {
    try await withPiHost { host, _, platform, provider in
      var settings = ModelSettings(providers: [provider])
      settings.uses = ModelUses(
        translation: ModelChoice(provider: provider.id, model: "test-model"),
        transcripts: ModelChoice(provider: provider.id, model: "test-model"))
      _ = try await host.saveModelSettings(settings)
      _ = try await host.setModelKey("fixture-value", for: provider.id)
      _ = try await host.run(InstallComponent(.bundledPi))
      _ = try #require(
        await value(host.subscribe(MediaSettings())) { setup in
          !setup.componentWork.contains { $0.component == .bundledPi }
            && setup.components.contains { $0.component == .bundledPi && $0.installation != .missing }
        })
      let companion = ModelChoice(provider: provider.id, model: "other-model").runtimeModel
      _ = try await host.setRuntime(SetRuntime(Runtime(provider: .bundledPi, model: companion)))
      #expect(try await host.runtime().model == companion)
      #expect(try await host.readModelSettings().settings.uses == settings.uses)

      _ = try await host.run(SendMessage(to: .main, text: "Reply."))
      _ = try #require(await value(host.subscribe(OneConversation(.main))) { $0.turn == nil && $0.entries.count > 1 })
      let launch = try #require(
        platform.invocations.last { $0.arguments.contains("--mode") && !$0.arguments.contains("--no-session") })
      #expect(launch.arguments.contains("loci-model/other-model"))
    }
  }

  @Test(arguments: [true, false])
  func aBadDigestOrRejectedRpcLeavesTheOldBundleActive(badDigest: Bool) async throws {
    try await withPiHost(badDigest: badDigest, rejectsRPC: !badDigest) { host, support, platform, provider in
      let old = try support.scratchFolder()
      try Data("older build".utf8).write(to: old.appending(path: "pi"))
      try support.activatePi(old, version: "1.5.0", generation: EntityID())
      let before = Support(root: support.root).activePi()?.executable
      _ = try await host.saveModelSettings(ModelSettings(providers: [provider]))
      _ = try await host.setModelKey("fixture-value", for: provider.id)
      let failed = await value(host.subscribe(MediaSettings())) { setup in
        setup.componentWork.contains {
          if case .failed = $0.state { return $0.component == .bundledPi }
          return false
        }
      }
      _ = try #require(failed)
      #expect(support.activePi()?.executable == before)
      #expect(platform.downloads == 1)
      #expect(platform.invocations.isEmpty == badDigest)
      #expect(platform.commands.isEmpty == badDigest)
    }
  }

  private func withPiHost(
    badDigest: Bool = false, rejectsRPC: Bool = false,
    _ body: (LocalHost, Support, PiInstallationPlatform, ModelProvider) async throws -> Void
  ) async throws {
    let root = URL(filePath: "/tmp/loci-fixture-" + UUID().uuidString.prefix(8))
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let platform = PiInstallationPlatform(root: root, rejectsRPC: rejectsRPC)
    let bytes = root.appending(path: "digest-input")
    try PiInstallationPlatform.archive.write(to: bytes)
    let support = Support(root: root.appending(path: "support"))
    let digest = badDigest ? "wrong" : try support.sha256(of: bytes)
    let url = try #require(URL(string: "https://downloads.example.test/pi.tar.gz"))
    let package = PiPackage(version: "1.6.0", url: url, sha256: digest, architecture: .x64)
    var provider = ModelProvider(custom: EntityID(), api: .openAI)
    provider.address = ModelAddress("https://models.example.test/v1")
    provider.models = [ProviderModel(id: "test-model", checked: true), ProviderModel(id: "other-model", checked: true)]
    let media = MediaEnvironment(
      support: support.root, runner: platform, network: platform, transcriber: FakeTranscriber([]),
      searchPaths: [], readerLanguage: "en")
    let environment = HostEnvironment(
      newID: { EntityID() }, now: { TestWorld.instant }, defaultRuntime: Runtime(provider: .codex),
      discard: .permanently, agents: { _ in nil }, media: media,
      tool: AgentTool(folder: root.appending(path: "Helpers"), socket: root.appending(path: "loci.sock")),
      modelKeys: MemoryModelKeys(),
      bundledPi: BundledPiEnvironment(
        launcher: platform, variables: ["OPENAI_API_KEY": "unrelated"], package: { _ in package }))
    let host = try await LocalHost.start(
      root: root, database: root.appending(path: "loci.sqlite"), environment: environment)
    do {
      try await body(host, support, platform, provider)
    } catch {
      await host.close()
      throw error
    }
    await host.close()
  }
}

private final class PiInstallationPlatform: Network, ProgramLauncher, ProgramRunner {
  static let archive = Data("fixture Pi archive".utf8)
  let root: URL
  let rejectsRPC: Bool
  private let fetched = Mutex(0)
  private let ran = Mutex<[ProgramCall]>([])
  private let launched = Mutex<[Invocation]>([])

  var downloads: Int { fetched.withLock { $0 } }
  var commands: [ProgramCall] { ran.withLock { $0 } }
  var invocations: [Invocation] { launched.withLock { $0 } }

  init(root: URL, rejectsRPC: Bool) {
    self.root = root
    self.rejectsRPC = rejectsRPC
  }

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    throw FetchError(reason: "no data requests")
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    let count = fetched.withLock {
      $0 += 1
      return $0
    }
    progress(Fraction(0.4))
    let file = root.appending(path: "download-\(count)")
    do {
      try Self.archive.write(to: file)
    } catch {
      throw FetchError(reason: "could not write fake download")
    }
    return file
  }

  func run(_ call: ProgramCall, line: @escaping @Sendable (String) -> Void) async throws(ProgramError) -> ProgramResult
  {
    ran.withLock { $0.append(call) }
    switch call.arguments.first {
    case "-tzf": return ProgramResult(status: 0, output: "pi/\npi/pi\n")
    case "-tvzf": return ProgramResult(status: 0, output: "d pi/\n- pi/pi\n")
    case "-xzf":
      do {
        let path = try #require(call.arguments.last)
        let folder = URL(filePath: path).appending(path: "pi")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: folder.appending(path: "pi"))
      } catch {
        throw ProgramError(reason: "fake extraction failed")
      }
      return ProgramResult(status: 0, output: "")
    default: return ProgramResult(status: 0, output: "")
    }
  }

  func launch(_ invocation: Invocation) throws(AgentError) -> RunningProgram {
    launched.withLock { $0.append(invocation) }
    let (output, send) = AsyncStream.makeStream(of: Data.self)
    let diagnostics = AsyncStream<Data> { $0.finish() }
    if invocation.arguments.contains("--version") {
      send.yield(Data("1.6.0\n".utf8))
      send.finish()
    }
    let rejectsRPC = rejectsRPC
    let emit: @Sendable (String) -> Void = { send.yield(Data(($0 + "\n").utf8)) }
    return RunningProgram(
      output: output, diagnostics: diagnostics,
      write: { data in
        guard let request = try JSONSerialization.jsonObject(with: data) as? [String: String],
          let type = request["type"], let id = request["id"]
        else { return }
        switch type {
        case "get_state":
          let data =
            rejectsRPC
            ? #""success":false,"error":"fixture RPC refused""# : #""success":true,"data":{"sessionId":"fixture"}"#
          emit(#"{"id":"\#(id)","type":"response","command":"\#(type)",\#(data)}"#)
        case "prompt":
          emit(#"{"id":"\#(id)","type":"response","command":"prompt","success":true,"data":{"disposition":"started"}}"#)
          emit(#"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"bundled response"}}"#)
          emit(#"{"type":"agent_end","messages":[]}"#)
          emit(#"{"type":"agent_settled","aborted":false}"#)
        default:
          emit(#"{"id":"\#(id)","type":"response","command":"\#(type)","success":true,"data":{}}"#)
        }
      },
      closeInput: { send.finish() }, terminate: { send.finish() }, exit: { 0 })
  }
}
