import LociModel

extension MediaInfo {
  /// The size of what a download at each quality would fetch, choosing formats the way the download does:
  /// H.264 first, then the tallest picture under the limit, with the best sound added when the picture has
  /// none. A format without a size is reckoned from its bitrate and the duration.
  static func sizes(of offered: [Raw.Format], seconds: Double?) -> [ImportChoice.Quality: Int64] {
    let formats = offered.filter { !($0.formatId ?? "").contains("drc") }
    func bytes(_ format: Raw.Format) -> Double? {
      if let size = format.filesize ?? format.filesizeApprox { return size }
      guard let tbr = format.tbr, let seconds else { return nil }
      return tbr * 1000 / 8 * seconds
    }
    let sounds = formats.filter { !$0.hasVideo && bytes($0) != nil }
    let sound = sounds.max { lhs, rhs in
      (lhs.ext == "m4a" ? 1 : 0, lhs.tbr ?? 0) < (rhs.ext == "m4a" ? 1 : 0, rhs.tbr ?? 0)
    }
    var sizes: [ImportChoice.Quality: Int64] = [:]
    if let sound, let size = bytes(sound) { sizes[.audio] = Int64(size) }
    for quality in ImportChoice.Quality.allCases {
      guard let limit = quality.height else { continue }
      let pictures = formats.filter { $0.hasVideo && ($0.height ?? 0) <= limit && bytes($0) != nil }
      let best = pictures.max { lhs, rhs in
        (lhs.isH264 ? 1 : 0, lhs.height ?? 0, lhs.tbr ?? 0) < (rhs.isH264 ? 1 : 0, rhs.height ?? 0, rhs.tbr ?? 0)
      }
      guard let best, let picture = bytes(best) else { continue }
      let withSound = best.acodec == "none" ? sound.flatMap(bytes) ?? 0 : 0
      sizes[quality] = Int64(picture + withSound)
    }
    return sizes
  }
}
