import Foundation
import LociModel

/// What turns the copy of one release into the next, as `script/release-patches` writes it in `patch.json`.
public struct AppPatch: Sendable, Decodable {
  public struct Change: Sendable, Decodable {
    public let path: String
    /// The bsdiff that rebuilds the file, inside the unpacked patch.
    public let diff: String
  }

  public let from: ReleaseVersion
  public let to: ReleaseVersion
  public let changed: [Change]
  /// Files that are new, each kept whole under `files/` in the unpacked patch.
  public let added: [String]
  /// Files and links to remove before anything is added.
  public let removed: [String]
  /// Links that are new or point somewhere else.
  public let links: [AppManifest.Link]

  private enum CodingKeys: String, CodingKey {
    case from, to, changed, added, removed, links
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    from = try container.decodeVersion(.from)
    to = try container.decodeVersion(.to)
    changed = try container.decode([Change].self, forKey: .changed)
    added = try container.decode([String].self, forKey: .added)
    removed = try container.decode([String].self, forKey: .removed)
    links = try container.decode([AppManifest.Link].self, forKey: .links)
  }
}

/// Every file and link of a release's app with what it must be, as `script/release-patches` writes it.
public struct AppManifest: Sendable, Decodable {
  public struct File: Sendable, Decodable {
    public let path: String
    public let sha256: String
    public let executable: Bool
  }

  public struct Link: Sendable, Decodable {
    public let path: String
    public let target: String
  }

  public let version: ReleaseVersion
  public let files: [File]
  public let links: [Link]

  private enum CodingKeys: String, CodingKey {
    case version, files, links
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decodeVersion(.version)
    files = try container.decode([File].self, forKey: .files)
    links = try container.decode([Link].self, forKey: .links)
  }
}

/// Why a patch could not be read or applied, or the patched copy is not the one the release describes.
public struct PatchProblem: LocalizedError, Equatable {
  public let reason: String

  public var errorDescription: String? { reason }

  init(_ reason: String) {
    self.reason = reason
  }
}

extension Support {
  /// The patch unpacked in `folder`. Every path in it must stay inside the app.
  public func readPatch(in folder: URL) throws -> AppPatch {
    let patch = try JSONDecoder().decode(AppPatch.self, from: Data(contentsOf: folder.appending(path: "patch.json")))
    let paths = patch.changed.flatMap { [$0.path, $0.diff] } + patch.added + patch.removed + patch.links.map(\.path)
    if let outside = paths.first(where: { !Self.staysInside($0) }) {
      throw PatchProblem("the patch reaches outside the app: \(outside)")
    }
    if let absolute = patch.links.first(where: { $0.target.hasPrefix("/") }) {
      throw PatchProblem("the patch links outside the app: \(absolute.path)")
    }
    return patch
  }

  public func readManifest(_ file: URL) throws -> AppManifest {
    try JSONDecoder().decode(AppManifest.self, from: Data(contentsOf: file))
  }

  /// Copies the app running to `destination`, a clone on APFS that takes no space until a file changes.
  public func copyApp(_ app: URL, to destination: URL) throws {
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.copyItem(at: app, to: destination)
  }

  /// Brings `app` from the patch's old release to its new one, given each changed file rebuilt into `rebuilt`
  /// by its path: removes, replaces, adds and links, sets which files run as `manifest` says, and drops the
  /// folders left empty.
  public func apply(
    _ patch: AppPatch, unpackedIn folder: URL, rebuilt: [String: URL], to app: URL, manifest: AppManifest
  ) throws {
    let files = FileManager.default
    for path in patch.removed {
      try? files.removeItem(at: app.appending(path: path))
    }
    for change in patch.changed {
      guard let file = rebuilt[change.path] else { throw PatchProblem("\(change.path) was not rebuilt") }
      try place(file, at: app.appending(path: change.path))
    }
    for path in patch.added {
      try place(folder.appending(path: "files").appending(path: path), at: app.appending(path: path))
    }
    for link in patch.links {
      let place = app.appending(path: link.path)
      try? files.removeItem(at: place)
      try files.createDirectory(at: place.deletingLastPathComponent(), withIntermediateDirectories: true)
      try files.createSymbolicLink(atPath: place.path(percentEncoded: false), withDestinationPath: link.target)
    }
    for file in manifest.files {
      let path = app.appending(path: file.path).path(percentEncoded: false)
      guard let mode = (try? files.attributesOfItem(atPath: path))?[.posixPermissions] as? NSNumber else { continue }
      let wanted = file.executable ? mode.intValue | 0o111 : mode.intValue & ~0o111
      if wanted != mode.intValue { try files.setAttributes([.posixPermissions: wanted], ofItemAtPath: path) }
    }
    removeEmptyFolders(in: app)
  }

  /// Fails unless `app` holds exactly the files and links of `manifest`, each file with its checksum and
  /// whether it runs.
  public func check(_ app: URL, against manifest: AppManifest) throws {
    let found = try entries(of: app)
    let expected = Set(manifest.files.map(\.path) + manifest.links.map(\.path))
    if let extra = found.keys.sorted().first(where: { !expected.contains($0) }) {
      throw PatchProblem("\(extra) is not in the release")
    }
    for file in manifest.files {
      guard case .file(let url) = found[file.path] else { throw PatchProblem("\(file.path) is missing") }
      guard try sha256(of: url) == file.sha256 else { throw PatchProblem("\(file.path) does not match its checksum") }
      guard isExecutable(url) == file.executable else { throw PatchProblem("\(file.path) runs when it should not") }
    }
    for link in manifest.links {
      guard case .link(let target) = found[link.path], target == link.target else {
        throw PatchProblem("\(link.path) does not point to \(link.target)")
      }
    }
  }

  private enum Entry {
    case file(URL)
    case link(String)
  }

  /// Every file and link under `app` by its path inside it; links are not followed.
  private func entries(of app: URL) throws -> [String: Entry] {
    let files = FileManager.default
    let base = app.path(percentEncoded: false)
    guard let walk = files.enumerator(atPath: base) else { return [:] }
    var found: [String: Entry] = [:]
    for case let path as String in walk {
      let full = app.appending(path: path)
      switch try files.attributesOfItem(atPath: full.path(percentEncoded: false))[.type] as? FileAttributeType {
      case .typeSymbolicLink?:
        found[path] = .link(try files.destinationOfSymbolicLink(atPath: full.path(percentEncoded: false)))
      case .typeRegular?: found[path] = .file(full)
      default: break
      }
    }
    return found
  }

  private func place(_ file: URL, at destination: URL) throws {
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: file, to: destination)
  }

  private func removeEmptyFolders(in folder: URL) {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
    let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
    for child in children {
      let values = try? child.resourceValues(forKeys: Set(keys))
      guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
      removeEmptyFolders(in: child)
      if (try? FileManager.default.contentsOfDirectory(atPath: child.path(percentEncoded: false)))?.isEmpty == true {
        try? FileManager.default.removeItem(at: child)
      }
    }
  }

  private static func staysInside(_ path: String) -> Bool {
    !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
  }
}

extension KeyedDecodingContainer {
  fileprivate func decodeVersion(_ key: Key) throws -> ReleaseVersion {
    let text = try decode(String.self, forKey: key)
    guard let version = ReleaseVersion(text) else {
      throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "not a version: \(text)")
    }
    return version
  }
}
