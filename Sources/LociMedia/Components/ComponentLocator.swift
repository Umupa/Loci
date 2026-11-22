import Foundation
import LociModel

/// Finds the components on this Mac. A copy in Loci's own folder wins, since it is there only because the
/// reader installed or updated it; otherwise one from Homebrew or the `PATH` is used as it is.
public struct ComponentLocator: Sendable {
  /// Where Loci keeps the components it manages, one folder each.
  let managed: URL
  /// Folders searched for a component already on this Mac, in order.
  let searchPaths: [URL]
  /// Whether a file exists and can be run; the store answers, since only it touches the disk.
  let isExecutable: @Sendable (URL) -> Bool
  let runner: any ProgramRunner

  public init(
    managed: URL, searchPaths: [URL], isExecutable: @escaping @Sendable (URL) -> Bool, runner: any ProgramRunner
  ) {
    self.managed = managed
    self.searchPaths = searchPaths
    self.isExecutable = isExecutable
    self.runner = runner
  }

  /// Homebrew's two prefixes, then the `PATH` this process was given.
  public static func systemSearchPaths(environment: [String: String]) -> [URL] {
    let given = (environment["PATH"] ?? "").split(separator: ":").map { URL(filePath: String($0)) }
    var seen: Set<String> = []
    return ([URL(filePath: "/opt/homebrew/bin"), URL(filePath: "/usr/local/bin")] + given).filter {
      seen.insert($0.path(percentEncoded: false)).inserted
    }
  }

  /// The folder a managed component is installed into.
  public func folder(of component: Component) -> URL {
    managed.appending(path: component.rawValue, directoryHint: .isDirectory)
  }

  public func locate(_ component: Component) async -> LocatedComponent {
    let absent = LocatedComponent(
      status: ComponentStatus(component: component, installation: .missing), executable: nil)
    guard component != .bundledPi else { return absent }
    let own = folder(of: component).appending(path: component.managedExecutable)
    if isExecutable(own) {
      return LocatedComponent(
        status: ComponentStatus(component: component, installation: .managed(version: await version(of: own))),
        executable: own)
    }
    for folder in searchPaths {
      let candidate = folder.appending(path: component.systemExecutable)
      guard isExecutable(candidate) else { continue }
      let installation = ComponentStatus.Installation.system(
        path: candidate.path(percentEncoded: false), version: await version(of: candidate))
      return LocatedComponent(
        status: ComponentStatus(component: component, installation: installation), executable: candidate)
    }
    return absent
  }

  public func locateAll() async -> [LocatedComponent] {
    var found: [LocatedComponent] = []
    for component in Component.allCases { found.append(await locate(component)) }
    return found
  }

  private func version(of executable: URL) async -> String? {
    let component = Component.allCases.first {
      executable.lastPathComponent == $0.managedExecutable || executable.lastPathComponent == $0.systemExecutable
    }
    guard let component,
      let result = try? await runner.run(ProgramCall(executable: executable, arguments: [component.versionFlag]))
    else { return nil }
    return ComponentVersion.read(component, from: result.output + "\n" + result.diagnostics)
  }
}

/// A component as found, with the program to run when there is one.
public struct LocatedComponent: Hashable, Sendable {
  public let status: ComponentStatus
  public let executable: URL?

  public init(status: ComponentStatus, executable: URL?) {
    self.status = status
    self.executable = executable
  }
}

extension Component {
  /// The program inside the managed folder.
  public var managedExecutable: String {
    switch self {
    case .ytDlp: "yt-dlp_macos"
    case .ffmpeg: "ffmpeg"
    case .quickJS: "qjs"
    case .bundledPi: "pi"
    }
  }

  var systemExecutable: String {
    switch self {
    case .ytDlp: "yt-dlp"
    case .ffmpeg: "ffmpeg"
    case .quickJS: "qjs"
    case .bundledPi: "pi"
    }
  }

  var versionFlag: String {
    switch self {
    case .ytDlp, .bundledPi: "--version"
    case .ffmpeg: "-version"
    case .quickJS: "-h"
    }
  }
}

enum ComponentVersion {
  /// `2026.10.26`; `ffmpeg version 9.0.1 Copyright …`; `QuickJS-ng version 0.10.1`.
  static func read(_ component: Component, from said: String) -> String? {
    let lines = said.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
    switch component {
    case .bundledPi:
      return lines.first
    case .ytDlp:
      return lines.first { $0.wholeMatch(of: /\d{4}\.\d{2}\.\d{2}(\.\d+)?/) != nil }
    case .ffmpeg, .quickJS:
      for line in lines {
        if let match = line.firstMatch(of: /[Vv]ersion\s+(\S+)/) { return String(match.1) }
      }
      return nil
    }
  }
}
