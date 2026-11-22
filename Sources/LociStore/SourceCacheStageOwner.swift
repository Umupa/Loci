import Darwin
import Foundation

enum SourceCacheStageOwner {
  static func current() throws -> String {
    guard let owner = try identity(of: getpid()) else { throw POSIXError(.ESRCH) }
    return owner
  }

  static func isAlive(_ owner: String) throws -> Bool {
    guard let prefix = owner.split(separator: "/", maxSplits: 1).first, let pid = Int32(prefix), pid > 0 else {
      return false
    }
    return try identity(of: pid) == owner
  }

  private static func identity(of pid: Int32) throws -> String? {
    var request = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var bytes = MemoryLayout<kinfo_proc>.size
    if sysctl(&request, u_int(request.count), &info, &bytes, nil, 0) != 0 {
      if errno == ESRCH { return nil }
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard bytes == MemoryLayout<kinfo_proc>.size else { return nil }
    let started = info.kp_proc.p_starttime
    return "\(pid)/\(started.tv_sec)/\(started.tv_usec)"
  }
}
