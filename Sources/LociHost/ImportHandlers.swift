import Foundation
import LociMedia
import LociModel
import LociStore

extension LocalHost {
  public func probeLink(_ command: ProbeLink) async throws(HostError) -> LinkProbe {
    let url = command.url
    if let saved = try attempt({ try database.items() }).first(where: { $0.source == url }) { return .saved(saved) }
    let context = library.context
    do throws(StageStop) {
      let tool = try await context.ytDlp(needing: [.ytDlp])
      let read: (info: MediaInfo, json: Data)
      do {
        read = try await tool.resolve(url)
      } catch {
        throw await context.stop(error, at: url)
      }
      let cover = await context.cover(at: read.info.thumbnail)
      await context.probes.keep(Probes.Probe(info: read.info, json: read.json, cover: cover), for: url)
      return .media(
        MediaPreview(
          title: read.info.title, site: read.info.site, duration: read.info.duration, cover: cover?.data,
          isAudio: read.info.isAudio, sizes: read.info.sizes, subtitles: read.info.subtitleLanguages,
          spokenSubtitles: read.info.subtitleLanguage))
    } catch {
      switch error {
      case .wait(let need): throw .invalidRequest("waiting for \(need)")
      case .fail(let failure): throw .invalidRequest(failure.reason)
      }
    }
  }

  public func importChoice() async throws(HostError) -> ImportChoice {
    library.context.lastChoice
  }
}
