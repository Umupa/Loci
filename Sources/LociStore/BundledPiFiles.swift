import CryptoKit
import Foundation
import LociModel

extension Support {
  public struct ActivePi: Sendable {
    public let version: String
    public let executable: URL
  }

  private struct PiActivation: Codable {
    let version: String
    let generation: EntityID
  }

  private var piComponent: URL {
    components.appending(path: Component.bundledPi.rawValue, directoryHint: .isDirectory)
  }

  private var activation: URL { piComponent.appending(path: "active.json") }

  private func piFolder(_ generation: EntityID) -> URL {
    piComponent.appending(path: generation.description, directoryHint: .isDirectory)
  }

  public func activePi() -> ActivePi? {
    guard let data = try? Data(contentsOf: activation),
      let active = try? JSONDecoder().decode(PiActivation.self, from: data)
    else { return nil }
    let file = piFolder(active.generation).appending(path: "pi")
    return isExecutable(file) ? ActivePi(version: active.version, executable: file) : nil
  }

  public func activatePi(_ folder: URL, version: String, generation: EntityID) throws {
    try makePiExecutable(in: folder)
    try FileManager.default.createDirectory(at: piComponent, withIntermediateDirectories: true)
    let destination = piFolder(generation)
    try FileManager.default.moveItem(at: folder, to: destination)
    do {
      let data = try Formats.document(PiActivation(version: version, generation: generation))
      try data.write(to: activation, options: .atomic)
    } catch {
      discard(destination)
      throw error
    }
  }

  public func makePiExecutable(in folder: URL) throws {
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: "pi").path(percentEncoded: false))
  }

  public func copyPiLicense(_ license: URL, into folder: URL) throws {
    let data = try Data(contentsOf: license)
    try data.write(to: folder.appending(path: "LICENSE"), options: .atomic)
  }

  public func sha256(of archive: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: archive)
    defer { try? handle.close() }
    var hash = SHA256()
    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
      hash.update(data: chunk)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
