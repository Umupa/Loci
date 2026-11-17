/// The Whisper models Loci offers for recognizing speech. Each is downloaded once, when first chosen.
public enum SpeechModel: String, CaseIterable, Codable, Hashable, Sendable {
  case tiny
  case base
  case small
  case medium
  case largeV3TurboQuantized
  case largeV3Turbo
  case largeV3

  /// Used until the reader picks another.
  public static let recommended = SpeechModel.largeV3TurboQuantized

  /// The download size in bytes.
  public var size: Int64 {
    switch self {
    case .tiny: 77_700_000
    case .base: 148_000_000
    case .small: 487_600_000
    case .medium: 1_530_000_000
    case .largeV3TurboQuantized: 574_000_000
    case .largeV3Turbo: 1_620_000_000
    case .largeV3: 3_100_000_000
    }
  }

  /// From 1, slowest, to 5, fastest.
  public var speed: Int {
    switch self {
    case .tiny, .base: 5
    case .small, .largeV3TurboQuantized: 4
    case .largeV3Turbo: 3
    case .medium: 2
    case .largeV3: 1
    }
  }

  /// From 1, most mistakes, to 5, fewest.
  public var accuracy: Int {
    switch self {
    case .tiny: 1
    case .base: 2
    case .small: 3
    case .medium, .largeV3TurboQuantized, .largeV3Turbo: 4
    case .largeV3: 5
    }
  }
}
