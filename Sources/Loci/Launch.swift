import Foundation
import LociHost
import LociModel
import LociUI
import SwiftUI
import os

/// Starting the host behind the window. The window opens at once and takes input; the host joins it when
/// it is ready, or the person is asked what to do about a database that cannot be used.
@MainActor
@Observable
final class Launch {
  enum State {
    case running
    case problem(StartupProblem)
  }

  private(set) var state = State.running
  /// Moves on each time the host starts over, so the window is built again over the new one.
  private(set) var generation = 0
  /// Why the last reset did not go through.
  var resetFailure: HostError?
  let host = DeferredHost()
  /// This Mac's companion in the menu bar, which stays while every window is closed.
  let companion: MenuBarCompanion
  /// The connector the browser came back from, for the window to turn to.
  let signInReturns = SignInReturns()
  private var local: LocalHost?
  /// The Macs the window can show: this one and the ones paired through the relay, or only this one in a build
  /// without a relay or when the device key cannot be kept.
  let machines: any Machines
  let folder: URL
  let updater = AppUpdater(environment: .system())
  /// This Mac's other browsers, for the built-in browser to start signed in.
  let signIns = LocalSignIns.onThisMac()
  private var reportedStart = false

  private static let log = Logger(subsystem: "com.loci.native.dev", category: "launch")

  init() {
    companion = MenuBarCompanion(host: host)
    let service: MachinesService?
    let choice = DataFolder.choose(environment: ProcessInfo.processInfo.environment, home: URL.homeDirectory)
    switch choice {
    case .use(let root):
      folder = root
      service = Self.service(serving: host)
    case .refuse(let path):
      folder = URL(filePath: path)
      service = nil
    }
    machines = service ?? SingleMachine(name: ThisMac.name, model: ThisMac.model, host: host)
    switch choice {
    case .use: start(replacingDatabase: false)
    case .refuse(let path): state = .problem(.refusedFolder(path))
    }
    if let service { Task { await service.start() } }
    Task { [updater] in await updater.watch() }
  }

  /// The relay's address and key are written into the app's Info.plist when it is built.
  private static func service(serving host: DeferredHost) -> MachinesService? {
    guard let address = (Bundle.main.object(forInfoDictionaryKey: "LociRelayURL") as? String).flatMap(URL.init),
      let key = Bundle.main.object(forInfoDictionaryKey: "LociRelayKey") as? String, !key.isEmpty
    else { return nil }
    return MachinesService.onThisMac(
      relay: address, registrationKey: key, local: host,
      support: URL.applicationSupportDirectory.appending(path: DataFolder.name))
  }

  /// The `loci` command in the app's bundle, which `script/bundle` puts in `Contents/Helpers`; `nil` when
  /// the app runs outside its bundle.
  private static func tool(root: URL) -> AgentTool? {
    let bundle = Bundle.main.bundleURL
    guard bundle.pathExtension == "app" else { return nil }
    return AgentTool(folder: bundle.appending(path: "Contents/Helpers"), socket: DataFolder.socket(in: root))
  }

  func rebuild() {
    state = .running
    start(replacingDatabase: true)
  }

  /// Resets the data folder (`LocalHost.reset()`) and starts again over it. Nothing reaches the old host
  /// meanwhile; a reset that fails leaves the folder as it was, and the host starts over it all the same.
  func reset() async {
    guard let current = local else { return }
    local = nil
    await host.suspend()
    do throws(HostError) {
      try await current.reset()
    } catch {
      resetFailure = error
    }
    await open(replacingDatabase: false)
    generation += 1
  }

  /// Records how long the process took to reach a main conversation that can be typed into.
  func talkShown() {
    guard !reportedStart, let elapsed = ProcessClock.millisecondsSinceStart() else { return }
    reportedStart = true
    Self.log.notice("main conversation shown \(elapsed, privacy: .public) ms after launch")
  }

  private func start(replacingDatabase: Bool) {
    Task { await open(replacingDatabase: replacingDatabase) }
  }

  private func open(replacingDatabase: Bool) async {
    let root = folder
    let database = DataFolder.database(in: root)
    let cache = DataFolder.sourceCache(
      in: .cachesDirectory, appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
    let returns = signInReturns
    let environment = HostEnvironment.system(
      defaultRuntime: Runtime(provider: .pi), tool: Self.tool(root: root), sourceCache: cache,
      browserReturned: { await returns.returned(from: $0) },
      inFront: { await MainActor.run { NSApplication.shared.isActive } })
    do throws(HostStartError) {
      let started =
        replacingDatabase
        ? try await LocalHost.startReplacingDatabase(root: root, database: database, environment: environment)
        : try await LocalHost.start(root: root, database: database, environment: environment)
      local = started
      await host.resolve(started)
    } catch {
      state = .problem(.database(error))
    }
  }
}

enum ProcessClock {
  /// Time since the kernel started this process, so the measure includes everything before `main`.
  static func millisecondsSinceStart() -> Int? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&request, u_int(request.count), &info, &size, nil, 0) == 0 else { return nil }
    let started = info.kp_proc.p_starttime
    let startedAt = Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000
    return Int((Date().timeIntervalSince1970 - startedAt) * 1000)
  }
}
