import LociModel
import SwiftUI

/// The stages of an item's work as one ruler: each stage a segment as long as the work in it, finished ones
/// solid with a check, the one under way filling in amber with its share and a sheen running across it, a
/// paused one hatched, a failed or blocked one red.
struct StageRuler: View {
  let segments: [Segment]
  var size = Scale.card

  struct Segment: Equatable {
    let stage: Job.Stage
    let weight: Double
    let mark: Mark
  }

  enum Mark: Equatable {
    case upcoming
    case done
    /// `nil` when how far along cannot be told.
    case running(Fraction?)
    /// With how far it had got, when that was known.
    case paused(Fraction?)
    /// Failed, or waiting for the reader.
    case stopped
  }

  enum Scale {
    case card, page

    var bar: CGFloat { self == .card ? 4 : 5 }
    var font: CGFloat { self == .card ? 11 : 12 }
  }

  /// The segments of `job`'s stages for an item of `kind`. Reading the link is quick and shows as part of
  /// the first segment; a job with no stages shows the one it is at.
  static func segments(of job: Job, kind: Item.Kind) -> [Segment] {
    let listed = job.stages.isEmpty ? [job.stage] : job.stages
    let shown = listed.count > 1 ? listed.filter { $0 != .resolve } : listed
    let current = job.stage == .resolve ? shown.first : job.stage
    let at = current.flatMap { shown.firstIndex(of: $0) } ?? 0
    return shown.enumerated().map { index, stage in
      let mark: Mark =
        if job.state == .done || index < at {
          .done
        } else if index > at {
          .upcoming
        } else {
          switch job.state {
          case .queued, .done: .upcoming
          case .running(let progress, _): .running(job.stage == .resolve ? nil : progress)
          case .paused(let progress): .paused(progress)
          case .waiting, .failed: .stopped
          }
        }
      return Segment(stage: stage, weight: weight(of: stage, kind: kind), mark: mark)
    }
  }

  /// How much of the work a stage is, roughly, against the others.
  static func weight(of stage: Job.Stage, kind: Item.Kind) -> Double {
    let audio: Bool = if case .audio = kind { true } else { false }
    return switch stage {
    case .resolve: 0.6
    case .fetchPage: 1
    case .findCover: 0.9
    case .extract: 1
    case .download: audio ? 1.6 : 3
    case .transcribe: audio ? 3 : 2.4
    case .diarize: 1.5
    case .translate: 1.4
    case .outline: 1
    }
  }

  var body: some View {
    Weighted(weights: segments.map(\.weight), spacing: 3) {
      ForEach(segments, id: \.stage) { segment in
        VStack(alignment: .leading, spacing: size == .card ? 6 : 7) {
          SegmentBar(mark: segment.mark, height: size.bar)
          label(segment)
            .lineLimit(1)
            .fixedSize(horizontal: !segments.contains(where: { $0.stage == .fetchPage }), vertical: true)
        }
      }
    }
  }

  @ViewBuilder private func label(_ segment: Segment) -> some View {
    let name = Text(segment.stage.name)
    let font = Font.system(size: size.font)
    switch segment.mark {
    case .upcoming:
      name.font(font).foregroundStyle(Palette.inkFaint)
    case .done:
      HStack(spacing: 3) {
        Image(systemName: "checkmark").font(.system(size: size.font - 2, weight: .bold))
        name
      }
      .font(font).foregroundStyle(Palette.inkMuted)
    case .running(let progress):
      HStack(spacing: 4) {
        name.font(font.weight(.semibold)).foregroundStyle(Palette.ink)
        if let progress {
          Text(verbatim: Self.percent(progress)).font(font.monospaced()).foregroundStyle(Palette.accentInk)
        }
      }
    case .paused(let progress):
      HStack(spacing: 4) {
        name.font(font).foregroundStyle(Palette.inkMuted)
        if let progress {
          Text(verbatim: Self.percent(progress)).font(font.monospaced()).foregroundStyle(Palette.inkMuted)
        }
      }
    case .stopped:
      name.font(font.weight(.semibold)).foregroundStyle(Palette.failure)
    }
  }

  static func percent(_ share: Fraction) -> String {
    "\(Int((share.value * 100).rounded()))%"
  }
}

/// One segment's bar.
private struct SegmentBar: View {
  @Environment(\.reducesMotion) private var reduceMotion
  let mark: StageRuler.Mark
  let height: CGFloat

  var body: some View {
    let shape = Capsule()
    shape
      .fill(fill)
      .overlay(alignment: .leading) {
        if case .running(let progress) = mark {
          GeometryReader { frame in
            shape.fill(Palette.accent).frame(width: frame.size.width * (progress?.value ?? 0))
            if !reduceMotion { sheen(width: frame.size.width) }
          }
        } else if case .paused(let progress) = mark {
          GeometryReader { frame in
            Hatch().foregroundStyle(Palette.inkFaint).opacity(0.8)
              .frame(width: frame.size.width * (progress?.value ?? 1))
          }
        }
      }
      .clipShape(shape)
      .frame(height: height)
  }

  private var fill: Color {
    switch mark {
    case .done: Palette.accentLine
    case .stopped: Palette.failure.opacity(0.55)
    case .upcoming, .running, .paused: Palette.fillStrong
    }
  }

  /// A band of light running left to right, over and over.
  private func sheen(width: CGFloat) -> some View {
    TimelineView(.animation) { context in
      let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
      LinearGradient(
        colors: [.white.opacity(0), .white.opacity(0.6), .white.opacity(0)], startPoint: .leading, endPoint: .trailing
      )
      .frame(width: width * 0.4)
      .offset(x: -width * 0.4 + width * 1.5 * phase)
    }
    .allowsHitTesting(false)
  }
}

/// Diagonal stripes, for paused work.
struct Hatch: Shape {
  var gap: CGFloat = 6

  func path(in rect: CGRect) -> Path {
    var path = Path()
    var x = rect.minX - rect.height
    while x < rect.maxX {
      path.move(to: CGPoint(x: x, y: rect.maxY))
      path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
      path.addLine(to: CGPoint(x: x + rect.height + gap / 2, y: rect.minY))
      path.addLine(to: CGPoint(x: x + gap / 2, y: rect.maxY))
      path.closeSubpath()
      x += gap
    }
    return path
  }
}

/// Lays its children out in a row, each as wide as its share of the weights.
private struct Weighted: Layout {
  let weights: [Double]
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 240
    let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }.max() ?? 0
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let total = max(weights.reduce(0, +), 0.0001)
    let room = bounds.width - spacing * CGFloat(max(subviews.count - 1, 0))
    var x = bounds.minX
    for (index, subview) in subviews.enumerated() {
      let width = room * (weights.indices.contains(index) ? weights[index] : 0) / total
      subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
      x += width + spacing
    }
  }
}

extension Job.Stage {
  /// What the stage is called on the ruler.
  var name: LocalizedStringResource {
    switch self {
    case .resolve: .loci("stage.resolve")
    case .fetchPage: .loci("stage.fetchPage")
    case .findCover: .loci("stage.findCover")
    case .extract: .loci("stage.extract")
    case .download: .loci("stage.download")
    case .transcribe: .loci("stage.transcribe")
    case .diarize: .loci("stage.diarize")
    case .translate: .loci("stage.translate")
    case .outline: .loci("stage.outline")
    }
  }
}
