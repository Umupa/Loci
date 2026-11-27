import LociMedia
import LociModel
import os

/// Why an update step failed: the kind the person is told, and the details only the log keeps.
struct UpdateError: Error {
  let failure: UpdateFailure
  let detail: String

  init(_ failure: UpdateFailure, _ detail: String) {
    self.failure = failure
    self.detail = detail
  }

  private static let log = Logger(subsystem: "com.loci.native.dev", category: "updates")

  func log(_ release: AppRelease) {
    Self.log.error("updating to \(release.version.description, privacy: .public) failed: \(detail, privacy: .public)")
  }

  /// Runs `body`, counting what it throws as `failure`.
  static func on<T>(_ failure: UpdateFailure, _ body: () throws -> T) throws(UpdateError) -> T {
    do {
      return try body()
    } catch {
      throw UpdateError(failure, error.localizedDescription)
    }
  }

  /// Runs `body`, counting the program or network failure it throws as `failure`.
  nonisolated(nonsending) static func on<T>(
    _ failure: UpdateFailure, _ body: () async throws(FetchError) -> T
  ) async throws(UpdateError) -> T {
    do {
      return try await body()
    } catch {
      throw UpdateError(failure, error.reason)
    }
  }
}
