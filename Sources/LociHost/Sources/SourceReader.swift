import Foundation
import LociMedia
import LociModel

/// Reads a source's pages and connector calls: a page through `SourcePages`, whose every request is the
/// app's own GET, signed in only when its site is connected and then only toward that site; and a
/// connector's read-only tools with their checks. A page is never read through the library's fetching, so
/// nothing the companion fetches holds it up. Each connector call is recorded as the source's.
struct SourceReader: SourceReading {
  let source: SourceKey
  let connectors: ConnectorKeeper
  let pages: SourcePages

  func read(_ request: SourceRequest) async throws(SourceProblems) -> String {
    do throws(HostError) {
      switch request {
      case .get(let get):
        throw .invalidRequest("\(get.url.absoluteString) is a plain GET, which the source sends itself")
      case .page(let url):
        if let site = await connectors.signedInSite(for: url) {
          return try await connectors.readSite(url, record: site, by: .source(source))
        }
        do throws(FetchError) {
          return try await pages.read(url)
        } catch {
          throw .invalidRequest("\(url.absoluteString): \(error.reason)")
        }
      case .connector(let call):
        return try await connectors.call(
          CallConnector(call.connector, tool: call.tool, arguments: call.arguments.text), by: .source(source))
      }
    } catch {
      throw SourceProblems("", JobRun.describe(error))
    }
  }
}
