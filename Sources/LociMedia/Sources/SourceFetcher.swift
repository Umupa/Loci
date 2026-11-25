import Foundation
import LociModel

/// Sends a source's requests: GET only, as no one, with the Referer and User-Agent the script asked for.
struct SourceFetcher: Sendable {
  let network: any Network
  /// The most a response may hold.
  static let mostBytes = 2_000_000
  static let timeout: TimeInterval = 10
  /// A browser's, naming no one.
  static let userAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

  func fetch(_ requests: [SourceRequest]) async throws(SourceProblems) -> [SourceResponse] {
    var responses: [SourceResponse] = []
    for (index, request) in requests.enumerated() {
      let path = "requests[\(index)]"
      let data: Data
      let response: HTTPURLResponse
      do {
        (data, response) = try await network.data(for: Self.urlRequest(request))
      } catch {
        throw SourceProblems(path, "\(request.url.absoluteString): \(error.reason)")
      }
      guard data.count <= Self.mostBytes else {
        throw SourceProblems(path, "the response is larger than \(Self.mostBytes / 1_000_000) MB")
      }
      guard let text = Self.text(of: data, encoding: request.encoding, declared: response.textEncodingName) else {
        throw SourceProblems(path, "the response is not text in \(request.encoding?.rawValue ?? "its encoding")")
      }
      responses.append(SourceResponse(url: request.url, status: response.statusCode, text: text))
    }
    return responses
  }

  static func urlRequest(_ request: SourceRequest) -> URLRequest {
    var urlRequest = URLRequest(url: request.url, timeoutInterval: timeout)
    urlRequest.httpMethod = "GET"
    urlRequest.httpShouldHandleCookies = false
    urlRequest.setValue(request.userAgent ?? userAgent, forHTTPHeaderField: "User-Agent")
    if let referer = request.referer { urlRequest.setValue(referer, forHTTPHeaderField: "Referer") }
    return urlRequest
  }

  /// GBK is read as GB 18030, which holds all of it.
  static func text(of data: Data, encoding: SourceEncoding?, declared: String?) -> String? {
    let gbk = String.Encoding(
      rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    let chosen: String.Encoding =
      switch encoding {
      case .gbk: gbk
      case .utf8: .utf8
      case nil:
        switch declared?.lowercased() {
        case "gbk", "gb2312", "gb18030": gbk
        default: .utf8
        }
      }
    return String(data: data, encoding: chosen)
  }
}
