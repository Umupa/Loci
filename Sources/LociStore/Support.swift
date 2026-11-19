import Foundation
import LociModel

/// Loci's folder in Application Support: the components it manages, the speech models, the cookies the
/// built-in browser handed over, and downloads on their way in. None of it is the reader's content, so it
/// stays out of the Loci folder.
public struct Support: Sendable {
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  public var components: URL { root.appending(path: "components", directoryHint: .isDirectory) }
  public var models: URL { root.appending(path: "models", directoryHint: .isDirectory) }
  public var cookies: URL { root.appending(path: "cookies.txt") }
  var downloads: URL { root.appending(path: "downloads", directoryHint: .isDirectory) }

  public func isExecutable(_ file: URL) -> Bool {
    FileManager.default.isExecutableFile(atPath: file.path(percentEncoded: false))
  }

  /// A new empty folder for unpacking or downloading into, removed by `discard` or by installing it.
  public func scratchFolder() throws -> URL {
    let folder = downloads.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  /// Removes a download or scratch folder that is no longer needed.
  public func discard(_ leftover: URL) {
    try? FileManager.default.removeItem(at: leftover)
  }

  /// Puts the app at `staged` where `installed` is, in place of the copy there.
  public func replaceApp(_ installed: URL, with staged: URL) throws {
    _ = try FileManager.default.replaceItemAt(installed, withItemAt: staged)
  }

  /// Replaces a component's folder with `unpacked` and makes `executable` inside it runnable.
  public func installComponent(_ component: Component, unpacked: URL, executable: String) throws {
    let target = components.appending(path: component.rawValue, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: components, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
      try FileManager.default.removeItem(at: target)
    }
    try FileManager.default.moveItem(at: unpacked, to: target)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: target.appending(path: executable).path(percentEncoded: false))
  }

  /// Puts a downloaded file into a scratch folder under `name`, ready to install as a whole folder.
  public func stage(_ file: URL, as name: String) throws -> URL {
    let folder = try scratchFolder()
    try FileManager.default.moveItem(at: file, to: folder.appending(path: name))
    return folder
  }

  public func modelFile(_ name: String) -> URL {
    models.appending(path: name)
  }

  public func hasModel(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: modelFile(name).path(percentEncoded: false))
  }

  public func installModel(_ file: URL, as name: String) throws {
    try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
    let target = modelFile(name)
    if FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
      try FileManager.default.removeItem(at: target)
    }
    try FileManager.default.moveItem(at: file, to: target)
  }

  public func deleteModel(_ name: String) throws {
    let target = modelFile(name)
    guard FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else { return }
    try FileManager.default.removeItem(at: target)
  }

  /// Writes the built-in browser's cookies in the Netscape format yt-dlp reads.
  public func saveCookies(_ given: [BrowserCookie]) throws {
    var lines = ["# Netscape HTTP Cookie File"]
    for cookie in given {
      let domain = cookie.domain
      let everySubdomain = domain.hasPrefix(".") ? "TRUE" : "FALSE"
      let expires = cookie.expires.map { String($0.millisecondsSince1970 / 1000) } ?? "0"
      let fields = [
        domain, everySubdomain, cookie.path, cookie.secure ? "TRUE" : "FALSE", expires, cookie.name, cookie.value,
      ]
      lines.append(fields.joined(separator: "\t"))
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: cookies, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cookies.path(percentEncoded: false))
  }

  public var hasCookies: Bool {
    FileManager.default.fileExists(atPath: cookies.path(percentEncoded: false))
  }
}
