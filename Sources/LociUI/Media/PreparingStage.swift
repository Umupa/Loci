import LociModel
import SwiftUI

/// Where the player will be while a video or episode is still being prepared: its cover blurred, amber light
/// around it, how far along in large figures and how much has arrived, the stage ruler under it, and the real
/// title, channel and length. Paused, the middle offers to carry on; waiting for the reader, it holds the
/// button that helps.
struct PreparingStage: View {
  let item: Item
  let job: Job
  let actions: CardActions

  private var state: CardState { CardState(job) }

  /// The job to show in place of the player: one that is still getting the media ready, while nothing plays.
  static func job(_ job: Job?, playable: Bool) -> Job? {
    guard !playable, let job, CardState(job).isBusy, [.resolve, .download].contains(job.stage) else { return nil }
    return job
  }

  var body: some View {
    GeometryReader { frame in
      let width = min(max(frame.size.width - 112, 0), Size.preparingWidth)
      VStack(alignment: .leading, spacing: 14) {
        picture.frame(width: width, height: width * 9 / 16)
        StageRuler(segments: StageRuler.segments(of: job, kind: item.kind), size: .page)
        VStack(alignment: .leading, spacing: 6) {
          Text(serif: item.title, Typography.preparingTitle)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
          Text(verbatim: Self.line(of: item))
            .font(.system(size: 12).monospaced())
            .foregroundStyle(Palette.inkMuted)
        }
        .padding(.top, 6)
      }
      .frame(width: width)
      .padding(.top, 58)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  }

  /// `Laurie Voss · youtube.com · 16:02`.
  static func line(of item: Item) -> String {
    let host = item.source?.host().map { $0.replacing(/^www\./, with: "") }
    return [item.site, host, item.length.map(MediaTime.text)].compactMap { $0 }.joined(separator: " · ")
  }

  private var picture: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
    return GalleryArt(item: item)
      .blur(radius: 16)
      .scaleEffect(1.15)
      .saturation(state.isPaused ? 0.3 : 0.9)
      .brightness(-0.18)
      .drawingGroup()
      .clipShape(shape)
      .overlay { middle }
      .overlay(alignment: .topTrailing) { corner }
      .overlay { shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline) }
      .background { SoftShadow(shape: shape, opacity: 0.3, radius: 28, y: 20) }
      .amberGlow(state.glows, corner: Radius.card)
  }

  @ViewBuilder private var middle: some View {
    switch state {
    case .working(_, let progress):
      VStack(spacing: 14) {
        if let progress {
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(verbatim: "\(Int((progress.value * 100).rounded()))")
              .font(.system(size: 44, weight: .semibold, design: .serif))
            Text(verbatim: "%").font(.system(size: 22, design: .serif)).opacity(0.7)
          }
        } else {
          ProgressView().controlSize(.regular).tint(.white)
        }
        if case .running(_, let amount?) = job.state, let words = Self.bytes(amount) {
          Text(verbatim: words).font(.system(size: 12).monospaced()).opacity(0.8)
        }
      }
      .foregroundStyle(.white)
      .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    case .queued:
      Text(.loci("job.queued")).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
    case .paused:
      VStack(spacing: 14) {
        GlassRound(symbol: "play.fill", size: 56) { actions.resume(item) }
        Text(.loci("job.paused")).font(.system(size: 12).monospaced()).foregroundStyle(.white.opacity(0.85))
      }
    case .needs(let fix):
      VStack(spacing: 14) {
        Image(systemName: "lock.fill").font(.system(size: 26)).foregroundStyle(.white)
        Button {
          actions.fix(fix, item)
        } label: {
          fix.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background(Capsule().fill(Palette.accent))
            .shadow(color: Palette.accent.opacity(0.4), radius: 10, y: 4)
        }
        .buttonStyle(PressStyle())
        .changesData(fix.changesData)
      }
    case .ready:
      EmptyView()
    }
  }

  @ViewBuilder private var corner: some View {
    HStack(spacing: 8) {
      if state.glows || state == .queued {
        GlassRound(symbol: "pause.fill", size: 32) { actions.pause(item) }
      }
      GlassRound(symbol: "xmark", size: 32) { actions.cancel(item) }
    }
    .padding(14)
  }

  /// `254 / 412 MB`: what has arrived of the whole, both in the unit of the whole.
  static func bytes(_ amount: Job.Amount) -> String? {
    guard let total = amount.total, total > 0 else { return nil }
    let gigabytes = total >= 1_000_000_000
    let unit: Double = gigabytes ? 1_000_000_000 : 1_000_000
    let format: (Int64) -> String = { bytes in
      gigabytes ? String(format: "%.1f", Double(bytes) / unit) : "\(Int((Double(bytes) / unit).rounded()))"
    }
    return "\(format(amount.done)) / \(format(total)) \(gigabytes ? "GB" : "MB")"
  }
}

/// O-S4: where the player would be for another Mac's video that it only watches online and never saved: its
/// cover blurred and quiet, and in the middle that it plays only on that Mac.
struct OnlyThereStage: View {
  let item: Item

  var body: some View {
    GeometryReader { frame in
      let width = min(max(frame.size.width - 112, 0), Size.preparingWidth)
      VStack(alignment: .leading, spacing: 20) {
        GalleryArt(item: item)
          .blur(radius: 16).scaleEffect(1.15).saturation(0.5).brightness(-0.2)
          .drawingGroup()
          .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
          .overlay {
            VStack(spacing: 12) {
              Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 24, weight: .light))
              Text(.loci("player.onlyThere")).font(.system(size: 13.5, weight: .medium))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
          }
          .frame(width: width, height: width * 9 / 16)
        VStack(alignment: .leading, spacing: 6) {
          Text(serif: item.title, Typography.preparingTitle).foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
          Text(verbatim: PreparingStage.line(of: item)).font(.system(size: 12).monospaced())
            .foregroundStyle(Palette.inkMuted)
        }
      }
      .frame(width: width)
      .padding(.top, 58)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  }
}
