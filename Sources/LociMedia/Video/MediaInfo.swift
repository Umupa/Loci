import Foundation
import LociModel
import NaturalLanguage

/// What `yt-dlp -J` says about a link, reduced to what an item needs.
public struct MediaInfo: Hashable, Sendable {
  public let title: String
  /// The show, channel or uploader, as it names itself.
  public let site: String?
  public let published: Date?
  public let duration: Duration?
  public let thumbnail: URL?
  public let chapters: [Outline.Chapter]
  /// The language the subtitles to use are in; `nil` when the site has no subtitles of its own.
  public let subtitleLanguage: String?
  /// The best address to play from while downloading, or `nil` when nothing can be played directly.
  public let stream: OnlineStream?
  /// No format has a picture, so this is something to listen to.
  public let isAudio: Bool

  /// Reads the JSON `yt-dlp -J` prints for one video or episode.
  public init(json: Data) throws(MediaError) {
    let raw: Raw
    do {
      raw = try Self.decoder.decode(Raw.self, from: json)
    } catch {
      throw MediaError(.other, reason: "yt-dlp said something unexpected: \(error)")
    }
    guard let title = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
      throw MediaError(.other, reason: "yt-dlp found no title")
    }
    self.title = title
    site = Self.site(of: raw)
    published =
      (raw.timestamp ?? raw.releaseTimestamp).map { Date(timeIntervalSince1970: $0) }
      ?? raw.uploadDate.flatMap(Self.day)
    duration = raw.duration.flatMap { $0 > 0 ? Duration.milliseconds(Int(($0 * 1000).rounded())) : nil }
    thumbnail = raw.thumbnail.flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) }
    chapters = (raw.chapters ?? []).compactMap { chapter in
      guard let start = chapter.startTime, let title = chapter.title else { return nil }
      return try? Outline.Chapter(start: .milliseconds(Int((start * 1000).rounded())), title: title)
    }
    let formats = raw.formats ?? [raw.asFormat]
    isAudio = formats.allSatisfy { !$0.hasVideo }
    stream = Self.stream(from: formats)
    subtitleLanguage = Self.subtitleLanguage(Array((raw.subtitles ?? [:]).keys), language: raw.language, title: title)
  }

  private static func site(of raw: Raw) -> String? {
    let names = [raw.series, raw.channel, raw.uploader].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
    let domain = raw.webpageUrlDomain ?? ""
    return names.first { !$0.isEmpty && $0 != domain && $0 != "www." + domain }
  }

  private static func day(_ text: String) -> Date? {
    guard text.count == 8, let year = Int(text.prefix(4)), let month = Int(text.dropFirst(4).prefix(2)),
      let day = Int(text.suffix(2))
    else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar.date(from: DateComponents(year: year, month: month, day: day))
  }

  /// Picture and sound in one mp4 the player opens directly, up to 1080p; else an HLS playlist with both;
  /// else only the sound, so the reader can start listening while the picture downloads.
  static func stream(from formats: [Raw.Format]) -> OnlineStream? {
    let usable = formats.filter { $0.url != nil && !($0.formatId ?? "").contains("drc") }
    let together = usable.filter { $0.isH264 && $0.isAAC && $0.ext == "mp4" && $0.isPlainHTTP }
      .filter { ($0.height ?? 0) <= 1080 }
      .max { ($0.height ?? 0) < ($1.height ?? 0) }
    let playlist = usable.filter { $0.isH264 && $0.isAAC && ($0.protocol ?? "").hasPrefix("m3u8") }
      .filter { ($0.height ?? 0) <= 1080 }
      .max { ($0.height ?? 0) < ($1.height ?? 0) }
    let sound = usable.filter { !$0.hasVideo && $0.isPlainHTTP && ($0.isAAC || $0.isMP3) }
      .max { ($0.tbr ?? 0) < ($1.tbr ?? 0) }
    if let format = together ?? playlist { return format.stream(audioOnly: false) }
    return sound?.stream(audioOnly: true)
  }

  /// The subtitles in the spoken language: the one the site names, else the one the title is written in,
  /// else the only one there is.
  static func subtitleLanguage(_ offered: [String], language: String?, title: String) -> String? {
    let real = offered.filter { !["live_chat", "danmaku", "comments"].contains($0) }.sorted()
    func primary(_ tag: String) -> String { String(tag.split(separator: "-").first ?? "").lowercased() }
    if let language, let match = real.first(where: { primary($0) == primary(language) }) { return match }
    if let written = NLLanguageRecognizer.dominantLanguage(for: title)?.rawValue,
      let match = real.first(where: { primary($0) == primary(written) })
    {
      return match
    }
    return real.count == 1 ? real.first : nil
  }

  private static let decoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  struct Raw: Decodable {
    let title: String?
    let series: String?
    let channel: String?
    let uploader: String?
    let webpageUrlDomain: String?
    let timestamp: Double?
    let releaseTimestamp: Double?
    let uploadDate: String?
    let duration: Double?
    let thumbnail: String?
    let language: String?
    let chapters: [Chapter]?
    let subtitles: [String: [Subtitle]]?
    let formats: [Format]?
    let url: String?
    let ext: String?
    let vcodec: String?
    let acodec: String?
    let httpHeaders: [String: String]?

    struct Chapter: Decodable {
      let startTime: Double?
      let title: String?
    }

    struct Subtitle: Decodable {
      let ext: String?
    }

    struct Format: Decodable {
      let formatId: String?
      let url: String?
      let ext: String?
      let vcodec: String?
      let acodec: String?
      let `protocol`: String?
      let height: Int?
      let tbr: Double?
      let httpHeaders: [String: String]?

      var hasVideo: Bool {
        guard let vcodec else { return !Self.audioExtensions.contains(ext ?? "") }
        return vcodec != "none"
      }
      var isH264: Bool { (vcodec ?? "").hasPrefix("avc1") || vcodec == "h264" }
      var isAAC: Bool { (acodec ?? "").hasPrefix("mp4a") || acodec == "aac" || (acodec == nil && ext == "m4a") }
      var isMP3: Bool { acodec == "mp3" || (acodec == nil && ext == "mp3") }
      var isPlainHTTP: Bool { self.protocol.map { $0 == "https" || $0 == "http" } ?? true }

      static let audioExtensions: Set = ["mp3", "m4a", "aac", "wav", "ogg", "opus", "flac"]

      func stream(audioOnly: Bool) -> OnlineStream? {
        guard let url = url.flatMap(URL.init(string:)) else { return nil }
        let expires = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .first { $0.name == "expire" || $0.name == "deadline" }?.value.flatMap(Double.init)
          .map { Timestamp(Date(timeIntervalSince1970: $0)) }
        let headers = (httpHeaders ?? [:]).filter { ["Referer", "User-Agent", "Origin"].contains($0.key) }
        return OnlineStream(url: url, headers: headers, audioOnly: audioOnly, expires: expires)
      }
    }

    /// A page that is itself one file, such as a podcast episode, has no list of formats.
    var asFormat: Format {
      Format(
        formatId: nil, url: url, ext: ext, vcodec: vcodec, acodec: acodec, protocol: nil, height: nil, tbr: nil,
        httpHeaders: httpHeaders)
    }
  }
}
