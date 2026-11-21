import Foundation
import LociModel

extension LocalHost {
  public func linkPreview(of url: URL) async throws(HostError) -> LinkPreview {
    await links.preview(of: url)
  }

  public func linkImage(of url: URL) async throws(HostError) -> Data? {
    await links.image(of: url)
  }

  public func webPicture(at url: URL) async throws(HostError) -> Data? {
    await links.picture(at: url)
  }
}
