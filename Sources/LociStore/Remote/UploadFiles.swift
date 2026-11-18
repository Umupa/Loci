import Foundation
import LociModel

/// A file arriving from another Mac in pieces, kept until a command uses it.
public struct IncomingUpload: Sendable {
  public let file: URL
  private let handle: FileHandle

  public func append(_ bytes: Data) throws {
    try handle.write(contentsOf: bytes)
  }

  /// The file is complete and stays where it is until the import that uses it moves or copies it.
  public func finish() throws -> URL {
    try handle.close()
    return file
  }

  public func abandon() {
    try? handle.close()
    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
  }

  init(file: URL) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    self.file = file
    handle = try FileHandle(forWritingTo: file)
  }
}

extension MachineFolder {
  /// A new file named as the sender named it, in a folder of its own so two uploads never collide.
  public func receiveUpload(named name: String, id: EntityID) throws -> IncomingUpload {
    try IncomingUpload(file: uploadsFolder.appending(path: id.description).appending(path: Self.safeName(name)))
  }

  /// Removes files received from other Macs, which their imports have copied by now.
  public func clearUploads() throws {
    guard FileManager.default.fileExists(atPath: uploadsFolder.path(percentEncoded: false)) else { return }
    try FileManager.default.removeItem(at: uploadsFolder)
  }

  /// Gives a received file the name the sender used, in the same folder.
  public func rename(_ file: URL, to name: String) throws -> URL {
    let named = file.deletingLastPathComponent().appending(path: Self.safeName(name))
    guard named != file else { return file }
    try FileManager.default.moveItem(at: file, to: named)
    return named
  }

  static func safeName(_ name: String) -> String {
    let last = name.split(separator: "/").last.map(String.init) ?? ""
    return last.isEmpty || last == ".." || last == "." ? "upload" : last
  }

  /// A file on this Mac in pieces of at most `size` bytes, read as they are sent.
  public static func pieces(of file: URL, size: Int) throws -> AsyncThrowingStream<Data, any Error> {
    let handle = try FileHandle(forReadingFrom: file)
    return AsyncThrowingStream {
      guard let piece = try handle.read(upToCount: size), !piece.isEmpty else {
        try handle.close()
        return nil
      }
      return piece
    }
  }
}
