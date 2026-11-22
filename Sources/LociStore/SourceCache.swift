import CryptoKit
import Foundation
import LociModel

/// Anonymous text and pinned checkouts kept apart from the library and the agent's working folder.
public struct SourceCache: Sendable {
  public enum Key: Sendable {
    case text(URL)
    case page(URL)
    case repository(URL, CommitID)

    fileprivate var location: (group: Group, name: String) {
      let group: Group
      let identity: String
      switch self {
      case .text(let url):
        group = .anonymous
        identity = url.absoluteString
      case .page(let url):
        group = .anonymous
        identity = "page\n\(url.absoluteString)"
      case .repository(let url, let commit):
        group = .repositories
        identity = "\(url.absoluteString)\n\(commit)"
      }
      let name = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
      return (group, name)
    }
  }

  /// A staging folder stays active while the caller holds it.
  public final class Stage: Sendable {
    public let url: URL
    fileprivate let directory: SourceCacheDirectory

    fileprivate init(url: URL, directory: SourceCacheDirectory) {
      self.url = url
      self.directory = directory
    }

    deinit { try? directory.removeFile(Self.ownerFile) }

    fileprivate static let ownerFile = "active-owner"

    public func text(named name: String) throws -> String? {
      try directory.text(fileName(name))
    }

    public func removeFile(named name: String) throws {
      try directory.removeFile(fileName(name))
    }

    private func fileName(_ name: String) throws -> String {
      guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.utf8.contains(0) else {
        throw POSIXError(.EINVAL)
      }
      return name
    }
  }

  fileprivate enum Group: String, CaseIterable {
    case anonymous
    case repositories = "repos"
    case legacy = "text"
    case staging = ".staging"

    func recognizes(_ name: String) -> Bool {
      self == .staging ? EntityID(canonical: name) != nil : name.utf8.count == 64 && CommitID(name) != nil
    }
  }

  private let root: URL
  private static let lifetime: TimeInterval = 14 * 24 * 60 * 60
  private static let marker = "last-used"

  public init(root: URL) { self.root = root }

  public func text(for key: Key, at now: Timestamp) throws -> String? {
    guard let entry = try directory(for: key), let marker = try marker(in: entry),
      let text = try entry.text("body")
    else { return nil }
    try SourceCacheDirectory.touch(marker, at: now.date)
    return text
  }

  public func repository(for key: Key, at now: Timestamp) throws -> URL? {
    guard case .repository(_, let commit) = key, let entry = try directory(for: key),
      let marker = try marker(in: entry), try checkout(in: entry, at: commit) != nil
    else { return nil }
    try SourceCacheDirectory.touch(marker, at: now.date)
    return path(for: key).appending(path: "checkout", directoryHint: .isDirectory)
  }

  public func stage(id: EntityID, at now: Timestamp) throws -> Stage {
    guard let staging = try group(.staging, create: true) else { throw POSIXError(.ENOENT) }
    let name = id.description
    let directory = try staging.makeDirectory(name)
    do {
      let owner = try SourceCacheStageOwner.current()
      try directory.write(Data(owner.utf8), as: Stage.ownerFile)
      try directory.write(Data(now.description.utf8), as: Self.marker)
      try touch(directory, at: now)
      return Stage(url: root.appending(path: ".staging/\(name)", directoryHint: .isDirectory), directory: directory)
    } catch {
      try? staging.remove(name, directory: directory)
      throw error
    }
  }

  public func publish(text: String, for key: Key, from stage: Stage, at now: Timestamp) throws {
    try stage.directory.write(Data(text.utf8), as: "body")
    try publish(stage, for: key, at: now) { try $0.text("body") != nil }
  }

  public func publishRepository(for key: Key, from stage: Stage, at now: Timestamp) throws -> URL {
    guard case .repository(_, let commit) = key, let checkout = try checkout(in: stage.directory, at: commit)
    else { throw POSIXError(.EINVAL) }
    try checkout.freeze()
    try publish(stage, for: key, at: now) { try self.checkout(in: $0, at: commit) != nil }
    guard let result = try repository(for: key, at: now) else { throw POSIXError(.ENOENT) }
    return result
  }

  public func discardStage(_ stage: Stage) throws {
    try group(.staging)?.remove(stage.url.lastPathComponent, directory: stage.directory)
  }

  public func bytes() throws -> Int64 {
    var total: Int64 = 0
    try visits { kind, _, _, entry, _ in
      if kind != .staging {
        total += try entry.bytes()
      } else if try !activeStage(entry) {
        total += try entry.bytes()
      }
    }
    return total
  }

  @discardableResult
  public func clear() throws -> Bool {
    try remove { _, _ in true }
  }

  @discardableResult
  public func purge(at now: Timestamp) throws -> Bool {
    let cutoff = now.date.timeIntervalSince1970 - Self.lifetime
    return try remove { kind, lastUse in kind == .legacy || kind == .staging || lastUse <= cutoff }
  }

  private func remove(_ shouldRemove: (Group, TimeInterval) -> Bool) throws -> Bool {
    var changed = false
    try visits { kind, parent, name, entry, marker in
      guard try shouldRemove(kind, SourceCacheDirectory.useTime(marker)) else { return }
      if kind == .staging, try activeStage(entry) { return }
      try parent.remove(name, directory: entry)
      changed = true
    }
    return changed
  }

  private func visits(
    _ body: (Group, SourceCacheDirectory, String, SourceCacheDirectory, FileHandle) throws -> Void
  ) throws {
    guard let directory = try SourceCacheDirectory.root(at: root, create: false) else { return }
    for kind in Group.allCases {
      guard let parent = try? directory.directory(kind.rawValue) else { continue }
      for name in try parent.names() where kind.recognizes(name) {
        guard let entry = try? parent.directory(name), let marker = try marker(in: entry) else { continue }
        try body(kind, parent, name, entry, marker)
      }
    }
  }

  private func publish(
    _ stage: Stage, for key: Key, at now: Timestamp, valid: (SourceCacheDirectory) throws -> Bool
  ) throws {
    let (kind, name) = key.location
    let stagedName = stage.url.lastPathComponent
    guard let staging = try group(.staging), let active = try staging.directory(stagedName),
      try active.isSame(as: stage.directory),
      let destination = try group(kind, create: true)
    else { throw POSIXError(.ENOENT) }
    if let existing = try destination.directory(name) {
      guard let marker = try marker(in: existing) else { throw POSIXError(.EEXIST) }
      if try valid(existing) {
        try SourceCacheDirectory.touch(marker, at: now.date)
        return
      }
      try destination.remove(name, directory: existing)
    }
    try touch(stage.directory, at: now)
    do {
      try staging.move(stagedName, to: destination, as: name)
    } catch let error as POSIXError where error.code == .EEXIST {
      guard let winner = try destination.directory(name), try valid(winner) else { throw error }
      try touch(winner, at: now)
    }
  }

  private func path(for key: Key) -> URL {
    let (kind, name) = key.location
    return root.appending(path: "\(kind.rawValue)/\(name)", directoryHint: .isDirectory)
  }

  private func group(_ kind: Group, create: Bool = false) throws -> SourceCacheDirectory? {
    try SourceCacheDirectory.root(at: root, create: create)?.directory(kind.rawValue, create: create)
  }

  private func directory(for key: Key) throws -> SourceCacheDirectory? {
    let (kind, name) = key.location
    return try group(kind)?.directory(name)
  }

  private func checkout(in entry: SourceCacheDirectory, at commit: CommitID) throws -> SourceCacheDirectory? {
    guard let checkout = try? entry.directory("checkout"), let git = try? checkout.directory(".git"),
      let head = try git.text("HEAD"), head.trimmingCharacters(in: .newlines) == commit.description
    else { return nil }
    return checkout
  }

  private func activeStage(_ entry: SourceCacheDirectory) throws -> Bool {
    guard let owner = try entry.text(Stage.ownerFile) else { return false }
    return try SourceCacheStageOwner.isAlive(owner)
  }

  private func marker(in directory: SourceCacheDirectory) throws -> FileHandle? {
    guard let marker = try directory.regularFile(Self.marker),
      let data = try marker.read(upToCount: 128), let text = String(data: data, encoding: .utf8),
      Timestamp(text) != nil
    else { return nil }
    return marker
  }

  private func touch(_ directory: SourceCacheDirectory, at now: Timestamp) throws {
    guard let marker = try marker(in: directory) else { throw POSIXError(.ENOENT) }
    try SourceCacheDirectory.touch(marker, at: now.date)
  }
}
