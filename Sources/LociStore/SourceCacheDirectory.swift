import Darwin
import Foundation

struct SourceCacheDirectory: Sendable {
  private let handle: FileHandle

  private var fd: Int32 { handle.fileDescriptor }
  private static let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC

  static func root(at url: URL, create: Bool) throws -> Self? {
    let root = url.standardizedFileURL
    let parent = root.deletingLastPathComponent()
    let trusted = parent.deletingLastPathComponent()
    let descriptor = open(trusted.path(percentEncoded: false), directoryFlags)
    guard let base = try Self.opened(descriptor) else { return nil }
    let container =
      if parent.path == trusted.path { base } else {
        try base.directory(parent.lastPathComponent, create: create)
      }
    return try container?.directory(root.lastPathComponent, create: create)
  }

  func directory(_ name: String, create: Bool = false) throws -> Self? {
    if create, mkdirat(fd, name, 0o700) < 0, errno != EEXIST { throw Self.failure() }
    return try Self.opened(openat(fd, name, Self.directoryFlags))
  }

  func makeDirectory(_ name: String) throws -> Self {
    guard mkdirat(fd, name, 0o700) == 0 else { throw Self.failure() }
    guard let directory = try directory(name) else { throw POSIXError(.ENOENT) }
    return directory
  }

  func isSame(as other: Self) throws -> Bool {
    let current = try Self.status(fd)
    let expected = try Self.status(other.fd)
    return current.st_dev == expected.st_dev && current.st_ino == expected.st_ino
  }

  func names() throws -> [String] {
    let descriptor = openat(fd, ".", Self.directoryFlags)
    guard descriptor >= 0 else { throw Self.failure() }
    guard let stream = fdopendir(descriptor) else {
      let error = Self.failure()
      close(descriptor)
      throw error
    }
    defer { closedir(stream) }
    var names: [String] = []
    while let entry = readdir(stream) {
      let name = withUnsafeBytes(of: &entry.pointee.d_name) { bytes in
        String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
      }
      if name != "." && name != ".." { names.append(name) }
    }
    return names
  }

  func regularFile(_ name: String) throws -> FileHandle? {
    let descriptor = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    if descriptor < 0, [ENOENT, ELOOP].contains(errno) { return nil }
    guard descriptor >= 0 else { throw Self.failure() }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    let status = try Self.status(descriptor)
    return Self.isRegular(status) && status.st_nlink == 1 ? file : nil
  }

  func text(_ name: String) throws -> String? {
    guard let data = try regularFile(name)?.readToEnd() else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func write(_ data: Data, as name: String) throws {
    let descriptor = openat(fd, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw Self.failure() }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    try file.write(contentsOf: data)
    try file.close()
  }

  static func useTime(_ file: FileHandle) throws -> TimeInterval {
    let time = try status(file.fileDescriptor).st_mtimespec
    return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
  }

  static func touch(_ file: FileHandle, at date: Date) throws {
    let time = date.timeIntervalSince1970
    let seconds = floor(time)
    let timestamp = timespec(tv_sec: Int(seconds), tv_nsec: Int((time - seconds) * 1_000_000_000))
    let times = [timestamp, timestamp]
    guard futimens(file.fileDescriptor, times) == 0 else { throw failure() }
  }

  func move(_ name: String, to directory: Self, as replacement: String) throws {
    guard renameatx_np(fd, name, directory.fd, replacement, UInt32(RENAME_EXCL)) == 0 else {
      throw Self.failure()
    }
  }

  func removeFile(_ name: String) throws {
    if unlinkat(fd, name, 0) < 0, errno != ENOENT { throw Self.failure() }
  }

  func remove(_ name: String, directory: Self) throws {
    guard let current = try self.directory(name), try directory.isSame(as: current) else { return }
    try directory.empty()
    guard unlinkat(fd, name, AT_REMOVEDIR) == 0 else { throw Self.failure() }
  }

  func bytes() throws -> Int64 {
    try names().reduce(0) { total, name in
      guard let status = try entry(name) else { return total }
      if Self.isDirectory(status), let directory = try directory(name) {
        return try total + directory.bytes()
      }
      return total + (Self.isRegular(status) ? Int64(status.st_blocks) * 512 : 0)
    }
  }

  func freeze() throws {
    for name in try names() {
      guard let status = try entry(name) else { continue }
      if Self.isDirectory(status) {
        try directory(name)?.freeze()
      } else if Self.isRegular(status) {
        guard let file = try regularFile(name) else { throw POSIXError(.EPERM) }
        try Self.chmod(file.fileDescriptor, removing: 0o222)
      }
    }
    try Self.chmod(fd, removing: 0o222)
  }

  private func empty() throws {
    let mode = try Self.status(fd).st_mode
    guard fchmod(fd, mode | 0o700) == 0 else { throw Self.failure() }
    for name in try names() {
      guard let status = try entry(name) else { continue }
      if Self.isDirectory(status), let child = try directory(name) {
        try remove(name, directory: child)
      } else {
        try removeFile(name)
      }
    }
  }

  private func entry(_ name: String) throws -> stat? {
    var status = stat()
    if fstatat(fd, name, &status, AT_SYMLINK_NOFOLLOW) == 0 { return status }
    if errno == ENOENT { return nil }
    throw Self.failure()
  }

  private static func opened(_ descriptor: Int32) throws -> Self? {
    if descriptor < 0, errno == ENOENT { return nil }
    guard descriptor >= 0 else { throw failure() }
    return Self(handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
  }

  private static func status(_ descriptor: Int32) throws -> stat {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else { throw failure() }
    return status
  }

  private static func chmod(_ descriptor: Int32, removing bits: mode_t) throws {
    let mode = try status(descriptor).st_mode
    guard fchmod(descriptor, mode & ~bits) == 0 else { throw failure() }
  }

  private static func isRegular(_ status: stat) -> Bool {
    status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
  }

  private static func isDirectory(_ status: stat) -> Bool {
    status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
  }

  private static func failure() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
}
