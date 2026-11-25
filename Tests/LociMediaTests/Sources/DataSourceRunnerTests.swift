import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociMedia

/// DS-S1, DS-S4: a source fetches with GET only and its script turns what came back into records.
struct DataSourceRunnerTests {
  static let now = Timestamp(millisecondsSince1970: 1_764_000_000_000)

  static let script = """
    function requests(state) {
      return [{ url: "https://qt.gtimg.cn/q=sh513100", referer: "https://gu.qq.com/", encoding: "gbk" }];
    }
    function parse(responses, now) {
      const fields = responses[0].text.split("~");
      return { records: { "513100": { name: fields[1], price: Number(fields[3]) } } };
    }
    """

  static let source = DataSource(name: "quote", title: "行情", every: SourceEvery(minutes: 1)!, script: script)

  static func gbk(_ text: String) -> Data {
    let encoding = String.Encoding(
      rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    return text.data(using: encoding)!
  }

  @Test(.timeLimit(.minutes(1)))
  func aSourceFetchesWithGETAndParsesWhatCameBack() async throws {
    let network = RecordingNetwork { _ in (Self.gbk("v_sh513100=\"1~纳指ETF~513100~1.873~\""), 200) }

    let result = try await DataSourceRunner(network: network).fetch(Self.source, state: nil, now: Self.now)

    #expect(result.records == ["513100": ["name": .text("纳指ETF"), "price": .number(1.873)]])
    #expect(result.sample.responses.first?.text.contains("纳指ETF") == true)
    let sent = try #require(network.requests.first)
    #expect(sent.httpMethod == "GET")
    #expect(sent.value(forHTTPHeaderField: "Referer") == "https://gu.qq.com/")
    #expect(sent.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Mozilla/5.0") == true)
    #expect(sent.httpShouldHandleCookies == false)
  }

  @Test(.timeLimit(.minutes(1)))
  func aSampleIsParsedAgainWithoutTheNetwork() async throws {
    let network = RecordingNetwork { _ in (Self.gbk("v=\"1~纳指ETF~513100~1.873~\""), 200) }
    let fetched = try await DataSourceRunner(network: network).fetch(Self.source, state: nil, now: Self.now)
    let replayer = DataSourceRunner(network: RecordingNetwork { _ in (Data(), 500) })

    let again = try await replayer.replay(
      fetched.sample, script: Self.script.replacing("Number(fields[3])", with: "Number(fields[3]) * 2"))

    #expect(again.records["513100"]?["price"] == .number(3.746))
  }

  @Test(.timeLimit(.minutes(1)))
  func aFailedRequestSaysWhichAndWhy() async {
    let runner = DataSourceRunner(
      network: RecordingNetwork { _ throws(FetchError) in throw FetchError(reason: "HTTP 404") })

    await #expect(throws: SourceProblems("requests[0]", "https://qt.gtimg.cn/q=sh513100: HTTP 404")) {
      try await runner.fetch(Self.source, state: nil, now: Self.now)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func aResponseTooLargeIsRefused() async {
    let runner = DataSourceRunner(network: RecordingNetwork { _ in (Data(count: SourceFetcher.mostBytes + 1), 200) })

    await #expect(throws: SourceProblems("requests[0]", "the response is larger than 2 MB")) {
      try await runner.fetch(Self.source, state: nil, now: Self.now)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func aRequestThatIsNotAGetIsNeverSent() async {
    let network = RecordingNetwork { _ in (Data(), 200) }
    let source = Self.source.running(
      "function requests() { return [{ url: 'https://a.example', method: 'POST' }]; }\nfunction parse() {}")

    await #expect(throws: SourceProblems("requests[0].method", "a source only sends GET")) {
      try await DataSourceRunner(network: network).fetch(source, state: nil, now: Self.now)
    }
    #expect(network.requests.isEmpty)
  }

  @Test func textIsReadInTheEncodingItIsIn() {
    #expect(SourceFetcher.text(of: Self.gbk("纳指"), encoding: nil, declared: "GBK") == "纳指")
    #expect(SourceFetcher.text(of: Data("纳指".utf8), encoding: nil, declared: nil) == "纳指")
    #expect(SourceFetcher.text(of: Data([0xFF, 0xFE, 0xFD]), encoding: .utf8, declared: nil) == nil)
  }
}

final class RecordingNetwork: Network {
  private let answer: @Sendable (URLRequest) throws(FetchError) -> (Data, Int)
  private let sent = Mutex<[URLRequest]>([])

  init(_ answer: @escaping @Sendable (URLRequest) throws(FetchError) -> (Data, Int)) {
    self.answer = answer
  }

  var requests: [URLRequest] { sent.withLock { $0 } }

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    sent.withLock { $0.append(request) }
    let (data, status) = try answer(request)
    guard let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)
    else { throw FetchError(reason: "invalid test response") }
    return (data, response)
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    throw FetchError(reason: "unexpected download")
  }
}
