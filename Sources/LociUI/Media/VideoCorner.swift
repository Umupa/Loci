import AVKit
import LociModel
import SwiftUI

/// The corner of the window a video left while playing goes on in.
enum Corner: String, CaseIterable {
  case topLeading, topTrailing, bottomLeading, bottomTrailing

  /// Where it is remembered on this Mac.
  static let key = "videoCorner"

  /// The corner whose quarter of `size` holds `point`.
  static func nearest(to point: CGPoint, in size: CGSize) -> Corner {
    let leading = point.x < size.width / 2
    let top = point.y < size.height / 2
    switch (top, leading) {
    case (true, true): return .topLeading
    case (true, false): return .topTrailing
    case (false, true): return .bottomLeading
    case (false, false): return .bottomTrailing
    }
  }

  var alignment: Alignment {
    switch self {
    case .topLeading: .topLeading
    case .topTrailing: .topTrailing
    case .bottomLeading: .bottomLeading
    case .bottomTrailing: .bottomTrailing
    }
  }
}

/// A video left while playing, small in a corner of the window, its sound and subtitles going on. It can be
/// dragged to another corner; under the pointer it offers to pause, go back to the video, go into the system's
/// picture in picture, or close, which stops it. A double click goes back to the video.
struct VideoCorner: View {
  @Environment(\.reducesMotion) private var reduceMotion
  let item: Item
  let player: Player
  /// The video is in the system's picture in picture, so the corner keeps out of sight.
  let inSystem: Bool
  let open: () -> Void
  let close: () -> Void
  let handOver: (Bool) -> Void
  @AppStorage(Corner.key) private var corner = Corner.bottomTrailing
  @AppStorage("subtitlesShown") private var subtitlesShown = true
  @AppStorage(SubtitleMode.key) private var mode = SubtitleMode.both
  @AppStorage(SubtitleStyle.key) private var style = SubtitleStyle.standard
  @State private var media: Feed<MediaPage>?
  @State private var drag = CGSize.zero
  @State private var hovering = false
  @State private var systemAsked = 0

  var body: some View {
    GeometryReader { frame in
      picture
        .frame(width: Size.videoCorner.width, height: Size.videoCorner.height)
        .offset(drag)
        .gesture(moving(in: frame.size))
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
    }
    .opacity(inSystem ? 0 : 1)
    .allowsHitTesting(!inSystem)
    .subscribing(ItemMedia(item: item.id), into: $media)
  }

  private var picture: some View {
    ZStack {
      Cover(item: item, corner: Radius.card)
      CornerSurface(player: player.engine, systemAsked: systemAsked, handOver: handOver)
      if subtitlesShown, let readable {
        CornerSubtitles(transcript: readable, player: player, mode: mode, style: style)
      }
      if hovering {
        controls
          .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
          .transition(.opacity)
      }
    }
    .overlay(
      RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        .strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
    )
    .background(
      RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        .fill(.black)
        .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
    )
    .contentShape(Rectangle())
    .onHover { over in withAnimation(reduceMotion ? nil : Motion.quick) { hovering = over } }
    .onTapGesture(count: 2, perform: open)
  }

  private var controls: some View {
    ZStack {
      Color.black.opacity(0.32)
      VStack {
        HStack {
          CornerButton(symbol: Symbols.cancel, title: .loci("player.close"), action: close)
          Spacer()
          CornerButton(symbol: Symbols.pictureInPicture, title: .loci("player.pictureInPicture")) {
            systemAsked += 1
          }
        }
        Spacer()
        HStack(spacing: Spacing.m) {
          CornerButton(
            symbol: player.playing ? Symbols.pause : Symbols.play,
            title: player.playing ? .loci("player.pause") : .loci("player.play"), size: 20
          ) { player.toggle() }
          CornerButton(symbol: Symbols.openOut, title: .loci("player.backToVideo"), action: open)
        }
        Spacer()
      }
      .padding(Spacing.xs)
    }
  }

  private var readable: ReadableTranscript? {
    guard let transcript = media?.value?.transcript, !transcript.segments.isEmpty else { return nil }
    return ReadableTranscript(
      transcript: transcript, translations: media?.value?.translations ?? [], language: Locale.preferredLanguages.first)
  }

  private func moving(in size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .global)
      .onChanged { drag = $0.translation }
      .onEnded { ended in
        let start = center(of: corner, in: size)
        let dropped = CGPoint(x: start.x + ended.translation.width, y: start.y + ended.translation.height)
        withAnimation(reduceMotion ? nil : Motion.standard) {
          corner = Corner.nearest(to: dropped, in: size)
          drag = .zero
        }
      }
  }

  private func center(of corner: Corner, in size: CGSize) -> CGPoint {
    let reach = CGSize(
      width: Size.videoCorner.width / 2 + Spacing.m, height: Size.videoCorner.height / 2 + Spacing.m)
    switch corner {
    case .topLeading: return CGPoint(x: reach.width, y: reach.height)
    case .topTrailing: return CGPoint(x: size.width - reach.width, y: reach.height)
    case .bottomLeading: return CGPoint(x: reach.width, y: size.height - reach.height)
    case .bottomTrailing: return CGPoint(x: size.width - reach.width, y: size.height - reach.height)
    }
  }
}

/// The words playing, as the subtitles over the video's own page show them. Only this follows the clock, and
/// the lines are drawn again only when the sentence changes.
private struct CornerSubtitles: View {
  let transcript: ReadableTranscript
  let player: Player
  let mode: SubtitleMode
  let style: SubtitleStyle

  var body: some View {
    CornerLines(lines: lines, style: style).equatable()
  }

  private var lines: [SubtitleLine] {
    guard let index = TranscriptFollow.playing(in: transcript.segments, at: player.time),
      transcript.segments[index].end >= player.time
    else { return [] }
    return transcript.lines(index, mode: mode, order: style.order)
  }
}

private struct CornerLines: View, Equatable {
  let lines: [SubtitleLine]
  let style: SubtitleStyle

  var body: some View {
    if !lines.isEmpty { SubtitleOverlay(lines: lines, style: style, referenceWidth: 600) }
  }

  nonisolated static func == (left: CornerLines, right: CornerLines) -> Bool {
    left.lines == right.lines && left.style == right.style
  }
}

/// A white symbol on the video, in a dark glass circle.
private struct CornerButton: View {
  let symbol: String
  let title: LocalizedStringResource
  var size: CGFloat = 13
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: size * 2.4, height: size * 2.4)
        .background(Circle().fill(.black.opacity(0.35)))
        .contentShape(Circle())
    }
    .buttonStyle(PressStyle())
    .help(Text(title))
    .accessibilityLabel(Text(title))
  }
}

/// The video's frames in a layer the system's picture in picture can take, and give back, rounded by the layer
/// itself so each frame is not masked again.
private struct CornerSurface: NSViewRepresentable {
  let player: AVPlayer
  /// Goes up each time the picture is to go into the system's picture in picture.
  let systemAsked: Int
  let handOver: (Bool) -> Void

  func makeCoordinator() -> SystemPicture { SystemPicture() }

  func makeNSView(context: Context) -> PictureView {
    let view = PictureView()
    view.picture.player = player
    context.coordinator.attach(to: view.picture, asked: systemAsked)
    return view
  }

  func updateNSView(_ view: PictureView, context: Context) {
    context.coordinator.handOver = handOver
    if view.picture.player !== player { view.picture.player = player }
    context.coordinator.ask(systemAsked)
  }
}

/// A view whose own layer shows the video, its corners rounded.
private final class PictureView: NSView {
  let picture = AVPlayerLayer()

  override init(frame: NSRect) {
    super.init(frame: frame)
    picture.videoGravity = .resizeAspect
    picture.cornerRadius = Radius.card
    picture.cornerCurve = .continuous
    picture.masksToBounds = true
    layer = picture
    wantsLayer = true
  }

  required init?(coder: NSCoder) { nil }
}

/// Hands the corner's picture to the system's picture in picture and says when it comes back.
@MainActor
private final class SystemPicture: NSObject, AVPictureInPictureControllerDelegate {
  private var controller: AVPictureInPictureController?
  private var asked = 0
  var handOver: (Bool) -> Void = { _ in }

  func attach(to layer: AVPlayerLayer, asked: Int) {
    self.asked = asked
    controller = AVPictureInPictureController(playerLayer: layer)
    controller?.delegate = self
  }

  func ask(_ count: Int) {
    guard count != asked else { return }
    asked = count
    controller?.startPictureInPicture()
  }

  nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
    MainActor.assumeIsolated { handOver(true) }
  }

  nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
    MainActor.assumeIsolated { handOver(false) }
  }
}
