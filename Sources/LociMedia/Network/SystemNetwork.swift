import Foundation
import LociModel

/// The internet through `URLSession`, which follows the system's proxy settings.
public struct SystemNetwork: Network {
  private let session: URLSession
  /// How long a download may go without a byte before it counts as broken.
  private let stall: Duration

  public init(session: URLSession = .shared, stall: Duration = .seconds(30)) {
    self.session = session
    self.stall = stall
  }

  public static func anonymous() -> Self {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    config.urlCredentialStorage = nil
    return Self(session: URLSession(configuration: config))
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
    let part = URL.temporaryDirectory.appending(path: "loci-download-\(UUID().uuidString)")
    return try await download(request, keepingPartAt: part, progress: progress)
  }

  /// Asks for the bytes after those already in `part` and appends them when the server sends that range; a
  /// server that sends the whole file or the wrong range has it written from the start. The download fails
  /// only when no byte arrives for `stall`, however long it takes overall.
  public func download(
    _ request: URLRequest, keepingPartAt part: URL, progress: @escaping @Sendable (Fraction?) -> Void
  ) async throws(FetchError) -> URL {
    let had = PartFile.size(of: part)
    if had > 0, try await receive(request, into: part, after: had, progress: progress) { return part }
    guard try await receive(request, into: part, after: 0, progress: progress) else {
      throw FetchError(reason: "the server did not send the file from its start")
    }
    return part
  }

  /// Whether the server sent what was asked for; `false` when it answered a range with another one.
  private func receive(
    _ request: URLRequest, into part: URL, after had: Int64, progress: @escaping @Sendable (Fraction?) -> Void
  ) async throws(FetchError) -> Bool {
    var asked = request
    asked.timeoutInterval = stall.timeInterval
    if had > 0 { asked.setValue("bytes=\(had)-", forHTTPHeaderField: "Range") }
    let writer = PartWriter(part: part, had: had, progress: progress)
    let outcome = await writer.run(asked, on: session)
    switch outcome {
    case .finished(let response):
      _ = try Self.checked(response)
      return true
    case .wrongRange:
      return false
    case .failed(let error):
      throw Self.failure(error)
    }
  }

  static func checked(_ response: URLResponse) throws(FetchError) -> HTTPURLResponse {
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
