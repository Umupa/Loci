import CryptoKit
import Foundation
import LociModel

/// What this Mac keeps about other Macs, outside the Loci folder because none of it is this Mac's
/// material: the roster, what was last seen of each Mac for reading while it is offline, and files on
/// their way in from another Mac.
public struct MachineFolder: Sendable {
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  var rosterFile: URL { root.appending(path: "machines.json") }

  func cacheFolder(of machine: MachineID) -> URL {
    root.appending(path: "Machines", directoryHint: .isDirectory).appending(path: machine.fingerprint)
  }

  var uploadsFolder: URL { root.appending(path: "Uploads", directoryHint: .isDirectory) }

  func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  func read(_ url: URL) -> Data? {
    try? Data(contentsOf: url)
  }
}

/// A Mac in the roster, as it is kept on disk.
public struct PairedPeer: Hashable, Codable, Sendable {
  public let machine: Machine
  public let address: PeerAddress
  public let pairedAt: Timestamp

  public init(machine: Machine, address: PeerAddress, pairedAt: Timestamp) {
    self.machine = machine
    self.address = address
    self.pairedAt = pairedAt
  }
}

extension MachineFolder {
  /// In the order they were paired. An unreadable roster is empty: pairing again is the remedy.
  public func roster() -> [PairedPeer] {
    read(rosterFile).flatMap { try? JSONDecoder().decode([PairedPeer].self, from: $0) } ?? []
  }

  public func saveRoster(_ peers: [PairedPeer]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try write(encoder.encode(peers), to: rosterFile)
  }

  /// What was last seen of a reply or a subscription on another Mac, by its name and request.
  public func cached(_ name: String, request: Data, on machine: MachineID) -> Data? {
    read(cacheFile(name, request: request, on: machine))
  }

  public func cache(_ value: Data, as name: String, request: Data, on machine: MachineID) throws {
    try write(value, to: cacheFile(name, request: request, on: machine))
  }

  /// Everything kept about a Mac that was removed.
  public func forget(_ machine: MachineID) throws {
    let folder = cacheFolder(of: machine)
    guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
    try FileManager.default.removeItem(at: folder)
  }

  private func cacheFile(_ name: String, request: Data, on machine: MachineID) -> URL {
    let key = SHA256.hash(data: Data(name.utf8) + [0] + request).map { String(format: "%02x", $0) }.joined()
    return cacheFolder(of: machine).appending(path: "\(key).json")
  }
}
