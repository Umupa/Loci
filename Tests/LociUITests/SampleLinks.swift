import Foundation
import LociModel

/// The three microVM projects the design's link cards show, and a page that says nothing about itself.
enum SampleLinks {
  static let kata = URL(string: "https://github.com/kata-containers/kata-containers")!
  static let e2b = URL(string: "https://github.com/e2b-dev/infra")!
  static let firecracker = URL(string: "https://github.com/firecracker-microvm/firecracker")!
  static let bare = URL(string: "https://lwn.net/Articles/970000/")!

  static func preview(of url: URL) -> LinkPreview {
    let site = url.host() ?? ""
    switch url {
    case kata: return LinkPreview(url: url, title: "kata-containers", site: site, summary: "用轻量虚拟机跑容器", image: url)
    case e2b: return LinkPreview(url: url, title: "e2b-dev/infra", site: site, summary: "E2B 的沙箱运行时", image: url)
    case firecracker:
      return LinkPreview(url: url, title: "firecracker-microvm", site: site, summary: "安全、快速的 microVM", image: url)
    default:
      return LinkPreview(url: url, title: "Isolation is a stack, not a layer", site: site, summary: nil, image: nil)
    }
  }

  static func image(of url: URL) -> Data? {
    switch url {
    case kata: SampleLibrary.picture("kata-containers-kata-containers")
    case e2b: SampleLibrary.picture("e2b-dev-infra")
    case firecracker: SampleLibrary.picture("firecracker-microvm-firecracker")
    default: nil
    }
  }
}
