import Foundation
import LociModel
import Testing

@testable import LociHost

/// C-S5: a link card asks the host what the page says about itself, and the host fetches it once.
struct LinkPreviewScenarioTests {
  @Test func aLinkCardsPreviewIsFetchedThroughTheHostOnce() async throws {
    try await withMediaHost { host, world in
      let link = try #require(URL(string: "https://www.firecracker-microvm.io/"))

      let preview = try await host.run(ReadLinkPreview(url: link))
      let again = try await host.run(ReadLinkPreview(url: link))

      #expect(preview == again)
      #expect(preview.site == "firecracker-microvm.io")
      #expect(try await host.run(ReadLinkImage(url: link)) == nil)
      #expect(world.network.requests == [link])
    }
  }
}
