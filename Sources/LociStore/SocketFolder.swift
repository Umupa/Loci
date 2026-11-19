import Foundation

/// The folder a unix socket is made in. Only this Mac's user may enter it, so only they can reach the
/// socket, whatever permissions the socket itself has.
public enum SocketFolder {
  /// Makes the socket's folder private to the user and removes a socket an earlier run left behind.
  public static func prepare(for socket: URL) throws {
    let folder = socket.deletingLastPathComponent()
    let manager = FileManager.default
    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path(percentEncoded: false))
    if manager.fileExists(atPath: socket.path(percentEncoded: false)) { try manager.removeItem(at: socket) }
  }
}
