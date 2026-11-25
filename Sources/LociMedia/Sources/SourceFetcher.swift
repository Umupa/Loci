import Foundation
import LociModel

/// Reads what a source asks for: plain GETs itself, as no one, with the Referer and User-Agent the script
/// asked for; pages and connectors through `elsewhere`, which holds the sign-ins.
struct SourceFetcher: Sendable {
  let network: any Network
  /// The most a response may hold.
  static let mostBytes = 2_000_000
  static let timeout: TimeInterval = 10
  /// A browser's, naming no one.
  static let userAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

  func fetch(_ requests: [SourceRequest], elsewhere: any SourceReading) async throws(SourceProblems)
    -> [SourceResponse]
  {
    var responses: [SourceResponse] = []
    for (index, request) in requests.enumerated() {
      let path = "requests[\(index)]"
      switch request {
      case .get(let get):
        responses.append(try await fetch(get, at: path))
      case .page, .connector:
        let text: String
        do throws(SourceProblems) {
          text = try await elsewhere.read(request)
        } catch {
          throw SourceProblems(all: error.all.map { SourceProblem(path, $0.description) })
        }
        guard text.utf8.count <= Self.mostBytes else { throw Self.tooLarge(at: path) }
        responses.append(SourceResponse(url: request.address, status: 200, text: text))
      }
    }
    return responses
  }

  private func fetch(_ request: SourceGet, at path: String) async throws(SourceProblems) -> SourceResponse {
    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await network.data(for: Self.urlRequest(request))
    } catch {
      throw SourceProblems(path, "\(request.url.absoluteString): \(error.reason)")
    }
    guard data.count <= Self.mostBytes else { throw Self.tooLarge(at: path) }
    guard let text = Self.text(of: data, encoding: request.encoding, declared: response.textEncodingName) else {
      throw SourceProblems(path, "the response is not text in \(request.encoding?.rawValue ?? "its encoding")")
    }
    return SourceResponse(url: request.url, status: response.statusCode, text: text)
  }

  private static func tooLarge(at path: String) -> SourceProblems {
    SourceProblems(path, "the response is larger than \(mostBytes / 1_000_000) MB")
  }

  static func urlRequest(_ request: SourceGet) -> URLRequest {
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
