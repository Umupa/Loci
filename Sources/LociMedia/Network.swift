import Foundation
import LociModel

/// The way out to the internet, so tests can answer in its place. Proxies follow the system's settings.
public protocol Network: Sendable {
  /// The whole body of a response, for pages, metadata, subtitles and images.
  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse)
  /// A large file, saved to a temporary file that the caller moves into place. `progress` hears the share
  /// done so far, or `nil` when the size is unknown.
  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
}
