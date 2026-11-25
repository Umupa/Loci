import Foundation
import LociModel

/// Reads a source's pages and connector calls with what the companion's own reads use: a page of a
/// connected website with its sign-in and GET only, any other page as `loci read` reads it, and a connector's
/// read-only tools with their checks. Each call is recorded as the source's.
struct SourceReader: SourceReading {
  let source: SourceKey
  let connectors: ConnectorKeeper
  let pages: SourceService

  func read(_ request: SourceRequest) async throws(SourceProblems) -> String {
    do throws(HostError) {
      switch request {
      case .get(let get):
        throw .invalidRequest("\(get.url.absoluteString) is a plain GET, which the source sends itself")
      case .page(let url):
        if let site = await connectors.signedInSite(for: url) {
          return try await connectors.readSite(url, record: site, by: .source(source))
        }
        return try await pages.read(url, fresh: true)
      case .connector(let call):
        return try await connectors.call(
          CallConnector(call.connector, tool: call.tool, arguments: call.arguments.text), by: .source(source))
      }
    } catch {
      throw SourceProblems("", JobRun.describe(error))
    }
  }
}
