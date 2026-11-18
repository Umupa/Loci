import Foundation
import LociModel

/// The internet through `URLSession`, which follows the system's proxy settings.
public struct SystemNetwork: Network {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw Self.failure(error)
    }
    return (data, try Self.checked(response))
  }

  public func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void)
    async throws(FetchError) -> URL
  {
    let (file, response): (URL, URLResponse)
    do {
      (file, response) = try await session.download(for: request, delegate: ProgressDelegate(progress: progress))
    } catch {
      throw Self.failure(error)
    }
    _ = try Self.checked(response)
    return file
  }

  private static func checked(_ response: URLResponse) throws(FetchError) -> HTTPURLResponse {
    guard let response = response as? HTTPURLResponse else { throw FetchError(reason: "not an HTTP response") }
    switch response.statusCode {
    case 200..<300: return response
    case 401, 403:
      throw FetchError(reason: "HTTP \(response.statusCode)", needsLogin: true)
    default:
      throw FetchError(reason: "HTTP \(response.statusCode)")
    }
  }

  private static func failure(_ error: any Error) -> FetchError {
    FetchError(reason: (error as? URLError)?.localizedDescription ?? error.localizedDescription)
  }
}

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
  let progress: @Sendable (Fraction?) -> Void

  init(progress: @escaping @Sendable (Fraction?) -> Void) {
    self.progress = progress
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    progress(
      totalBytesExpectedToWrite > 0 ? Fraction(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : nil)
  }
}
