import AppKit
import LociModel
import SwiftUI

/// A follow's picture: a channel's round, a show's a rounded square.
struct FollowFace: View {
  @Environment(\.host) private var host
  @Environment(\.webPictures) private var pictures
  let picture: URL?
  let isChannel: Bool
  let side: CGFloat
  /// Stands off the page with a soft shadow, cast by its outline rather than by the picture inside it.
  var lifted = false

  static func rounding(_ isChannel: Bool) -> CGFloat { isChannel ? 0.5 : 0.2 }

  /// A channel's circle, or a show's rounded square. Continuous corners at half the side are not a circle: they
  /// leave straight edges that a stroke draws, so the circle has circular corners.
  static func shape(side: CGFloat, rounding: CGFloat) -> RoundedRectangle {
    RoundedRectangle(cornerRadius: side * rounding, style: rounding >= 0.5 ? .circular : .continuous)
  }

  var body: some View {
    let shape = Self.shape(side: side, rounding: Self.rounding(isChannel))
    ZStack {
      Palette.coverPlaceholder
      if let image = picture.flatMap({ pictures?.image(of: $0) }) {
        Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
      }
    }
    .frame(width: side, height: side)
    .clipShape(shape)
    .overlay(shape.strokeBorder(Palette.line, lineWidth: Size.hairline))
    .background {
      if lifted { shape.fill(Palette.canvas).shadow(color: Palette.warmShadow.opacity(0.18), radius: 16, y: 8) }
    }
    .animation(.easeOut(duration: 0.25), value: picture.flatMap { pictures?.image(of: $0) } != nil)
    .task(id: picture) { if let picture { await pictures?.load(picture, from: host) } }
  }
}

/// An episode's picture at 16:9, with its length on the corner when it is known.
struct EpisodeThumbnail: View {
  @Environment(\.host) private var host
  @Environment(\.webPictures) private var pictures
  let episode: Episode
  var fallback: URL?
  var width: CGFloat = 176

  var picture: URL? { episode.picture ?? fallback }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
    ZStack {
      Palette.coverPlaceholder
      if let image = picture.flatMap({ pictures?.image(of: $0) }) {
        Image(nsImage: image).resizable().scaledToFill()
      }
    }
    .frame(width: width, height: width * 9 / 16)
    .clipShape(shape)
    .overlay(alignment: .bottomTrailing) {
      if let length = episode.length {
        Text(verbatim: MediaTime.text(length))
          .font(Typography.clock)
          .foregroundStyle(Palette.onCover)
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.coverShade.opacity(0.72)))
          .padding(6)
      }
    }
    .task(id: picture) { if let picture { await pictures?.load(picture, from: host) } }
  }

  /// The picture as loaded, for a flight.
  @MainActor static func image(of episode: Episode, fallback: URL?, in pictures: WebPictures?) -> NSImage? {
    (episode.picture ?? fallback).flatMap { pictures?.image(of: $0) }
  }
}

/// When an episode came out, as a follow page and the peek write it.
enum EpisodeDate {
  /// `11月24日`, `Nov 24`.
  static func day(_ time: Timestamp) -> Text {
    Text(time.date, format: .dateTime.month().day())
  }

  /// `11·24`, the podcast list's narrow column.
  static func short(_ time: Timestamp, in zone: TimeZone = .current) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let parts = calendar.dateComponents([.month, .day], from: time.date)
    return "\(parts.month ?? 0)·\(String(format: "%02d", parts.day ?? 0))"
  }
}
