import CoreServices
import Foundation
import Synchronization

enum FileEvent: Sendable {
  /// Absolute paths, with symbolic links resolved, of files and folders that changed.
  case changed([String])
  /// Events were lost; anything under the root may have changed.
  case rescan
}

/// The bridge to FSEvents, the one place GCD is allowed: FSEvents delivers its callbacks only on a
/// dispatch queue, and each callback goes straight into an `AsyncStream`.
enum FileEvents {
  static func stream(under root: String, latency: TimeInterval = 0.1) -> AsyncStream<FileEvent> {
    let (events, continuation) = AsyncStream.makeStream(of: FileEvent.self)
    let sink = Sink(continuation)
    guard sink.start(watching: root, latency: latency) else {
      continuation.finish()
      return events
    }
    continuation.onTermination = { _ in sink.stop() }
    return events
  }

  private final class Sink: Sendable {
    private static let lostEvents = FSEventStreamEventFlags(
      kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
        | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)

    private let continuation: AsyncStream<FileEvent>.Continuation
    private let stream = Mutex<FSEventStreamRef?>(nil)

    init(_ continuation: AsyncStream<FileEvent>.Continuation) {
      self.continuation = continuation
    }

    static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
      guard let info else { return }
      Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().receive(count: count, paths: paths, flags: flags)
    }

    func start(watching root: String, latency: TimeInterval) -> Bool {
      stream.withLock { current in
        var context = FSEventStreamContext(
          version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(
          kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        guard
          let created = FSEventStreamCreate(
            nil, Self.callback, &context, [root] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency, flags)
        else { return false }
        FSEventStreamSetDispatchQueue(created, DispatchQueue(label: "app.loci.store.file-events"))
        FSEventStreamStart(created)
        current = created
        return true
      }
    }

    func stop() {
      stream.withLock { current in
        guard let held = current else { return }
        FSEventStreamStop(held)
        FSEventStreamInvalidate(held)
        FSEventStreamRelease(held)
        current = nil
      }
    }

    private func receive(count: Int, paths: UnsafeMutableRawPointer, flags: UnsafePointer<FSEventStreamEventFlags>) {
      let cPaths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
      if (0..<count).contains(where: { flags[$0] & Self.lostEvents != 0 }) {
        continuation.yield(.rescan)
      } else {
        continuation.yield(.changed((0..<count).map { String(cString: cPaths[$0]) }))
      }
    }
  }
}
