import Foundation
import LociModel

/// Where Loci downloads a component it manages, and how the download unpacks.
public struct ComponentPackage: Hashable, Sendable {
  /// Tried in order; the first that answers is used.
  public let urls: [URL]
  public enum Format: Hashable, Sendable {
    case executable, zip
    case piTarGzip(PiPackage)
  }

  public let format: Format

  public static func pi(_ package: PiPackage) -> ComponentPackage {
    ComponentPackage(urls: [package.url], format: .piTarGzip(package))
  }

  /// The packages Vimpo uses: yt-dlp's standalone build for macOS (unpacked, so it starts quickly), a
  /// static FFmpeg built for macOS, and QuickJS-ng.
  public static func of(_ component: Component, arm: Bool) -> ComponentPackage {
    let arch = arm ? "arm64" : "amd64"
    switch component {
    case .bundledPi:
      return .pi(PiPackage.official(arm: arm))
    case .ytDlp:
      return ComponentPackage(
        urls: [URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos.zip")!],
        format: .zip)
    case .ffmpeg:
      return ComponentPackage(
        urls: ["release", "snapshot"].map {
          URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(arch)/\($0)/ffmpeg.zip")!
        },
        format: .zip)
    case .quickJS:
      return ComponentPackage(
        urls: [
          URL(
            string:
              "https://github.com/quickjs-ng/quickjs/releases/latest/download/qjs-darwin-\(arm ? "arm64" : "x86_64")"
          )!
        ],
        format: .executable)
    }
  }

  /// Unpacks `archive` into `folder` with the system's `ditto`.
  public static func unpack(_ archive: URL, into folder: URL, runner: any ProgramRunner) async throws(FetchError) {
    let call = ProgramCall(
      executable: URL(filePath: "/usr/bin/ditto"),
      arguments: ["-x", "-k", archive.path(percentEncoded: false), folder.path(percentEncoded: false)])
    let result: ProgramResult
    do {
      result = try await runner.run(call)
    } catch {
      throw FetchError(reason: error.reason)
    }
    guard result.succeeded else { throw FetchError(reason: "could not unpack: \(result.diagnostics)") }
  }
}
