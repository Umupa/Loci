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
  let host = DeferredHost()
  let folder: URL
  private var reportedStart = false

  private static let log = Logger(subsystem: "com.loci.native.dev", category: "launch")

  init() {
    switch DataFolder.choose(environment: ProcessInfo.processInfo.environment, home: URL.homeDirectory) {
    case .use(let root):
      folder = root
      start(replacingDatabase: false)
    case .refuse(let path):
      folder = URL(filePath: path)
      state = .problem(.refusedFolder(path))
    }
  }

  func rebuild() {
    state = .running
    start(replacingDatabase: true)
  }

  /// Records how long the process took to reach a start page that can be typed into.
  func startShown() {
    guard !reportedStart, let elapsed = ProcessClock.millisecondsSinceStart() else { return }
    reportedStart = true
    Self.log.notice("start page shown \(elapsed, privacy: .public) ms after launch")
  }

  private func start(replacingDatabase: Bool) {
    let root = folder
    let database = DataFolder.database(in: root)
    let environment = HostEnvironment.system(defaultProvider: .pi)
    Task {
      do throws(HostStartError) {
        let local =
          replacingDatabase
          ? try await LocalHost.startReplacingDatabase(root: root, database: database, environment: environment)
          : try await LocalHost.start(root: root, database: database, environment: environment)
        await host.resolve(local)
      } catch {
        state = .problem(.database(error))
      }
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
