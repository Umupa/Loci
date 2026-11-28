import AppKit
import LociModel
import SwiftUI

/// Pictures on the web that a panel or a follow shows, read through the host by their address and kept for the
/// window.
@MainActor
@Observable
final class WebPictures {
  private var images: [URL: NSImage] = [:]
  private var asked: Set<URL> = []

  func image(of url: URL) -> NSImage? { images[url] }

  func load(_ url: URL, from host: any LociModel.Host) async {
    guard asked.insert(url).inserted else { return }
    guard let data = try? await host.run(ReadWebPicture(url: url)) ?? nil, let image = NSImage(data: data) else {
      asked.remove(url)
      return
    }
    images[url] = image
  }
}

extension EnvironmentValues {
  /// Set by the window; without it, pictures on the web leave their places blank.
  @Entry var webPictures: WebPictures?
}
