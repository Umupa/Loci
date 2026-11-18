import Foundation
import LociMedia
import LociModel
import Synchronization

/// Answers requests from a table of addresses, and remembers what was asked.
final class FakeNetwork: Network {
  struct Answer {
    let status: Int
    let type: String
    let body: Data
  }

  private let answers: [String: Answer]
  private let asked = Mutex<[URL]>([])

  init(_ answers: [String: Answer]) {
    self.answers = answers
  }

  var requests: [URL] { asked.withLock { $0 } }

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    guard let url = request.url else { throw FetchError(reason: "no address") }
    asked.withLock { $0.append(url) }
    guard let answer = answers[url.absoluteString] else { throw FetchError(reason: "offline") }
    guard
      let response = HTTPURLResponse(
        url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": answer.type])
    else { throw FetchError(reason: "bad response") }
    return (answer.body, response)
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    throw FetchError(reason: "downloads are not part of these tests")
  }
}

extension FakeNetwork.Answer {
  static func image(_ bytes: String = "PNG", type: String = "image/png") -> Self {
    Self(status: 200, type: type, body: Data(bytes.utf8))
  }

  static func page(_ text: String, status: Int = 200) -> Self {
    Self(status: status, type: "text/html", body: Data(text.utf8))
  }

  static func pdf(_ data: Data, status: Int = 200) -> Self {
    Self(status: status, type: "application/pdf", body: data)
  }

  static func atom(_ text: String) -> Self {
    Self(status: 200, type: "application/atom+xml", body: Data(text.utf8))
  }
}
