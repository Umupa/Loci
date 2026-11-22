import Foundation
import LociModel

struct CourseDirectory {
  let descriptor: Int32
  let path: String
  let course: EntityID

  func directory<Value>(
    _ name: String, create: Bool = false, _ body: (CourseDirectory) throws -> Value
  ) throws -> Value {
    let child = CourseDirectory(descriptor: descriptor, path: path.isEmpty ? name : "\(path)/\(name)", course: course)
    if create, mkdirat(descriptor, name, 0o755) != 0, errno != EEXIST { throw child.failure(errno) }
    let fd = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw child.failure(errno) }
    defer { close(fd) }
    return try body(CourseDirectory(descriptor: fd, path: child.path, course: course))
  }

  func read(_ name: String) throws -> Data {
    let file = try regularFile(name, flags: O_RDONLY)
    defer { try? file.close() }
    return try file.readToEnd() ?? Data()
  }

  func append(_ data: Data, to name: String) throws {
    let file = try regularFile(name, flags: O_RDWR | O_APPEND | O_CREAT)
    defer { try? file.close() }
    let size = try file.seekToEnd()
    var line = data
    if size > 0 {
      try file.seek(toOffset: size - 1)
      if try file.read(upToCount: 1) != Data("\n".utf8) { line.insert(UInt8(ascii: "\n"), at: 0) }
    }
    try file.write(contentsOf: line)
  }

  func replace(_ data: Data, at name: String, ifUnchanged version: Data? = nil) throws -> Bool {
    let temporary = ".\(UUID().uuidString).tmp"
    let file = try regularFile(temporary, flags: O_WRONLY | O_CREAT | O_EXCL)
    defer { _ = unlinkat(descriptor, temporary, 0) }
    do {
      try file.write(contentsOf: data)
      try file.close()
    } catch {
      try? file.close()
      throw error
    }
    if let version {
      guard try read(name) == version else { return false }
    } else {
      var details = stat()
      if fstatat(descriptor, name, &details, AT_SYMLINK_NOFOLLOW) == 0 {
        guard details.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw invalid(name) }
      } else if errno != ENOENT {
        throw failure(errno)
      }
    }
    guard renameat(descriptor, temporary, descriptor, name) == 0 else { throw failure(errno) }
    return true
  }

  private func regularFile(_ name: String, flags: Int32) throws -> FileHandle {
    let fd = openat(descriptor, name, flags | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o644)
    guard fd >= 0 else { throw failure(errno, name: name) }
    var details = stat()
    guard fstat(fd, &details) == 0, details.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
      close(fd)
      throw invalid(name)
    }
    return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
  }

  private func failure(_ code: Int32, name: String? = nil) -> any Error {
    let target = name.map { "\(path)/\($0)" } ?? path
    switch code {
    case ENOENT: return StoreError.notFound(target)
    case ELOOP, ENOTDIR, EISDIR: return invalid(name)
    default: return NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
  }

  private func invalid(_ name: String?) -> StoreError {
    let target = name.map { "\(path)/\($0)" } ?? path
    return .invalid(
      FileProblem(
        path: target, kind: .invalid, reason: "course files need regular files and directories",
        subject: .course(course)))
  }
}

extension Store {
  func inCourseDirectory<Value>(
    _ id: EntityID, create: Bool = false, _ body: (CourseDirectory) throws -> Value
  ) throws -> Value {
    if create {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    let fd = open(root.path(percentEncoded: false), O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard fd >= 0 else {
      let code = errno
      if code == ENOENT { throw StoreError.notFound(id.description) }
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
    defer { close(fd) }
    let directory = CourseDirectory(descriptor: fd, path: "", course: id)
    return try directory.directory(Self.coursesFolder, create: create) { courses in
      try courses.directory(id.description, create: create, body)
    }
  }
}
