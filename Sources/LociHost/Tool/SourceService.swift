import Foundation
import LociMedia
import LociModel
import LociStore
import os

struct SourceService: Sendable {
  private let cache: SourceCache?
  private let context: LibraryContext
  private let gate = Gate(limit: 1)

  init(context: LibraryContext) {
    self.context = context
    cache = context.environment.sourceCache.map(SourceCache.init(root:))
  }

  /// The text of a source. `fresh` fetches it again even when it is kept, and keeps what came, so a run in the
  /// background sees a page as it is today rather than as it was when first read.
  func read(_ url: URL, fresh: Bool = false) async throws(HostError) -> String {
    guard let cache else { throw .invalidRequest("The source cache is not available.") }
    guard url.isWebLink, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.user == nil
    else {
      throw .invalidRequest("Reading a source requires an HTTP or HTTPS link without credentials.")
    }
    if let fragment = parts.percentEncodedFragment, !fragment.hasPrefix("/"), !fragment.hasPrefix("!") {
      parts.fragment = nil
    }
    let address = parts.url ?? url
    let key: SourceCache.Key =
      if let raw = SourceTextReader.rawFile(for: address) {
        .text(raw)
      } else if LinkKind(url) == .article {
        .page(address)
      } else {
        .text(address)
      }
    return try await gate.through { () async throws(HostError) in
      try Self.checkCancellation()
      if !fresh, let text = try attempt({ try cache.text(for: key, at: context.now()) }) { return text }
      let stage = try newStage(in: cache)
      defer { discard(stage, in: cache) }
      let text = try await fetch(address, using: stage)
      try Self.checkCancellation()
      try attempt {
        if fresh {
          try cache.replace(text: text, for: key, from: stage, at: context.now())
        } else {
          try cache.publish(text: text, for: key, from: stage, at: context.now())
        }
      }
      await context.notify([.media])
      return text
    }
  }

  func repository(_ command: FetchSourceRepository) async throws(HostError) -> SourceCheckout {
    guard let cache else { throw .invalidRequest("The source cache is not available.") }
    guard let url = Self.repositoryURL(command.url) else {
      throw .invalidRequest("A repository requires an HTTP or HTTPS URL without credentials.")
    }
    let git = GitRepository(
      runner: context.media.runner, executable: context.environment.gitExecutable, proxy: context.media.proxy())
    return try await gate.through { () async throws(HostError) in
      try Self.checkCancellation()
      let commit: CommitID
      if let pinned = command.commit {
        commit = pinned
      } else {
        do throws(FetchError) {
          commit = try await git.head(of: url)
        } catch {
          throw .invalidRequest(error.reason)
        }
      }
      let key = SourceCache.Key.repository(url, commit)
      let folder: URL
      if let existing = try attempt({ try cache.repository(for: key, at: context.now()) }) {
        folder = existing
      } else {
        let stage = try newStage(in: cache)
        defer { discard(stage, in: cache) }
        do throws(FetchError) {
          try await git.checkout(
            url, commit: commit, into: stage.url.appending(path: "checkout", directoryHint: .isDirectory))
        } catch {
          throw .invalidRequest(error.reason)
        }
        try Self.checkCancellation()
        folder = try attempt { try cache.publishRepository(for: key, from: stage, at: context.now()) }
        await context.notify([.media])
      }
      return SourceCheckout(path: folder.path(percentEncoded: false), commit: commit)
    }
  }

  func bytes() -> Int64? {
    guard let cache else { return nil }
    return try? cache.bytes()
  }

  func clear() async throws(HostError) {
    guard let cache else { throw .invalidRequest("The source cache is not available.") }
    try await gate.through { () async throws(HostError) in
      do throws(HostError) {
        _ = try attempt { try cache.clear() }
      } catch {
        await context.notify([.media])
        throw error
      }
      await context.notify([.media])
    }
  }

  func purge(whenIdle: Bool = false) async -> Bool {
    guard let cache else { return true }
    if whenIdle, await gate.isBusy { return false }
    return await gate.through {
      do {
        if try cache.purge(at: context.now()) { await context.notify([.media]) }
        return true
      } catch {
        Self.log.error("Could not purge the source cache: \(String(describing: error), privacy: .public)")
        return false
      }
    }
  }

  private func fetch(_ url: URL, using stage: SourceCache.Stage) async throws(HostError) -> String {
    let reader = SourceTextReader(network: context.media.sourceNetwork)
    let kind = LinkKind(url)
    if kind == .paper || SourceTextReader.rawFile(for: url) != nil {
      return try await readPage(url, using: reader)
    }
    let knownMedia = kind == .video || kind == .audio
    let tool = try? await context.ytDlp(needing: [.ytDlp], anonymous: true)
    guard let tool else {
      if knownMedia { throw .invalidRequest("Reading this video's subtitles requires yt-dlp.") }
      return try await readPage(url, using: reader)
    }
    let info: MediaInfo?
    do throws(MediaError) {
      info = knownMedia ? try await tool.resolve(url).info : try await tool.recognize(url)?.info
    } catch {
      if knownMedia || error.kind == .needsLogin { throw .invalidRequest(error.reason) }
      return try await readPage(url, using: reader)
    }
    guard let info else { return try await readPage(url, using: reader) }
    guard let language = info.subtitleLanguage ?? info.subtitleLanguages.first else {
      throw .invalidRequest("This video has no transcript from site subtitles.")
    }
    let file: URL
    do throws(MediaError) {
      file = try await tool.subtitles(at: url, language: language, into: stage.url)
    } catch {
      throw .invalidRequest(error.reason)
    }
    guard let subtitles = try attempt({ try stage.text(named: file.lastPathComponent) }) else {
      throw .invalidRequest("The site did not provide a readable subtitle file.")
    }
    let segments = Subtitles.segments(fromWebVTT: subtitles)
    guard !segments.isEmpty else { throw .invalidRequest("The site's subtitles contain no readable transcript.") }
    try attempt { try stage.removeFile(named: file.lastPathComponent) }
    return segments.map(\.text).joined(separator: "\n")
  }

  private func readPage(_ url: URL, using reader: SourceTextReader) async throws(HostError) -> String {
    do throws(FetchError) {
      return try await reader.read(url)
    } catch {
      throw .invalidRequest(error.reason)
    }
  }

  private func newStage(in cache: SourceCache) throws(HostError) -> SourceCache.Stage {
    try attempt { try cache.stage(id: context.environment.newID(), at: context.now()) }
  }

  private func discard(_ stage: SourceCache.Stage, in cache: SourceCache) {
    do {
      try cache.discardStage(stage)
    } catch {
      Self.log.error("Could not remove a source staging folder: \(String(describing: error), privacy: .public)")
    }
  }

  private static func checkCancellation() throws(HostError) {
    if Task.isCancelled { throw .invalidRequest("The source request was cancelled.") }
  }

  private static func repositoryURL(_ url: URL) -> URL? {
    guard url.isWebLink, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.user == nil
    else { return nil }
    parts.scheme = parts.scheme?.lowercased()
    parts.host = parts.host?.lowercased()
    parts.fragment = nil
    if parts.scheme == "https", parts.port == 443 { parts.port = nil }
    if parts.scheme == "http", parts.port == 80 { parts.port = nil }
    if parts.host == "github.com" || parts.host == "www.github.com" {
      let path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
      parts.path = "/" + (path.hasSuffix(".git") ? String(path.dropLast(4)) : path)
      parts.host = "github.com"
      parts.query = nil
    }
    return parts.url
  }

  private static let log = Logger(subsystem: "Loci", category: "source-cache")
}
