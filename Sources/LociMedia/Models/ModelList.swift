import Foundation
import LociModel

extension ModelClient {
  /// The ids of the models the provider at `address` offers. Anthropic's list comes a page at a time.
  public func models(api: ModelAPI, at address: ModelAddress, key: String) async throws(FetchError) -> [String] {
    let url = api.route("models", at: address)
    guard api == .anthropic else {
      return try await page(url, api: api, key: key).data.map(\.id)
    }
    var found: [String] = []
    var after: String?
    repeat {
      var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
      parts?.queryItems =
        [URLQueryItem(name: "limit", value: "1000")] + (after.map { [URLQueryItem(name: "after_id", value: $0)] } ?? [])
      guard let next = parts?.url else { throw FetchError(reason: "The model list address is not valid.") }
      let page = try await page(next, api: api, key: key)
      found += page.data.map(\.id)
      after = page.hasMore == true ? page.lastID : nil
    } while after != nil
    return found
  }

  private func page(_ url: URL, api: ModelAPI, key: String) async throws(FetchError) -> ModelPage {
    var request = Self.request(url, api: api, key: key, timeout: 20)
    request.httpMethod = "GET"
    let data = try await send(request, key: key)
    do {
      return try JSONDecoder().decode(ModelPage.self, from: data)
    } catch {
      throw FetchError(reason: "The model service returned an unreadable model list.")
    }
  }

  private struct ModelPage: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
    let hasMore: Bool?
    let lastID: String?

    private enum CodingKeys: String, CodingKey {
      case data
      case hasMore = "has_more"
      case lastID = "last_id"
    }
  }
}
