import LociModel
import SwiftUI

extension CourseStage {
  /// The stages in the order a course goes through them.
  static let inOrder: [CourseStage] = [.goal, .sources, .writing]

  /// Whether the course is past this stage when it is at `other`.
  func isBefore(_ other: CourseStage) -> Bool {
    (Self.inOrder.firstIndex(of: self) ?? 0) < (Self.inOrder.firstIndex(of: other) ?? 0)
  }

  var name: LocalizedStringResource {
    switch self {
    case .goal: .loci("course.stageGoal")
    case .sources: .loci("course.stageSources")
    case .writing: .loci("course.stageWriting")
    }
  }

  /// How long the stage is on the ruler, against the others.
  var weight: CGFloat {
    switch self {
    case .goal: 1
    case .sources: 1.4
    case .writing: 2.6
    }
  }
}

/// A course's stages as one ruler: the stages before the current one solid with a check, the current one
/// filling in amber with a light running across it, the rest an empty track. At the top of the builder the
/// names sit over the segments; under a book, the stage and its share sit under the ruler.
struct CourseStageRuler: View {
  enum Scale { case builder, book }

  let stage: CourseStage
  /// How far the current stage has got, from 0 to 1; `nil` when it cannot be told.
  let fraction: Double?
  var scale = Scale.builder

  var body: some View {
    switch scale {
    case .builder:
      WeightedRow(weights: CourseStage.inOrder.map(\.weight), spacing: 6) {
        ForEach(CourseStage.inOrder, id: \.self) { each in
          VStack(spacing: 7) {
            label(each)
            bar(each, height: 4)
          }
        }
      }
    case .book:
      VStack(spacing: 6) {
        WeightedRow(weights: CourseStage.inOrder.map(\.weight), spacing: 3) {
          ForEach(CourseStage.inOrder, id: \.self) { each in bar(each, height: 4) }
        }
        HStack {
          Text(stage.name)
          Spacer(minLength: 0)
          if let fraction { Text(verbatim: "\(Int((fraction * 100).rounded()))%") }
        }
        .font(Typography.mono.weight(.medium))
        .foregroundStyle(Palette.inkMuted)
      }
    }
  }

  @ViewBuilder private func label(_ each: CourseStage) -> some View {
    HStack(spacing: 4) {
      if each.isBefore(stage) {
        Image(systemName: Symbols.done).font(.system(size: 9, weight: .bold))
      }
      Text(each.name)
    }
    .font(.system(size: 12, weight: .semibold))
    .foregroundStyle(each == stage ? Palette.ink : each.isBefore(stage) ? Palette.inkMuted : Palette.inkFaint)
    .contentTransition(.opacity)
  }

  private func bar(_ each: CourseStage, height: CGFloat) -> some View {
    Capsule()
      .fill(each.isBefore(stage) ? Palette.inkMuted.opacity(0.75) : Palette.fillStrong)
      .overlay(alignment: .leading) {
        if each == stage {
          GeometryReader { frame in
            Capsule().fill(Palette.accent).frame(width: frame.size.width * min(max(fraction ?? 0, 0), 1))
            RunningLight(width: frame.size.width)
          }
        }
      }
      .clipShape(Capsule())
      .frame(height: height)
      .animation(.spring(duration: 0.8, bounce: 0.1), value: fraction)
      .animation(Motion.standard, value: stage)
  }
}

/// A band of light running along a bar, left to right, over and over.
private struct RunningLight: View {
  let width: CGFloat

  var body: some View {
    LightClock(period: 1.8, held: 0.3) { phase in
      if let phase {
        LinearGradient(
          colors: [.white.opacity(0), .white.opacity(0.6), .white.opacity(0)], startPoint: .leading,
          endPoint: .trailing
        )
        .frame(width: width * 0.35)
        .offset(x: -width * 0.35 + width * 1.5 * phase)
      }
    }
    .allowsHitTesting(false)
  }
}

/// Lays its children out in a row, each as wide as its share of the weights, as tall as the tallest.
struct WeightedRow: Layout {
  let weights: [CGFloat]
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 420
    let widths = shares(of: width, count: subviews.count)
    let height =
      zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
      .max() ?? 0
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX
    for (subview, width) in zip(subviews, shares(of: bounds.width, count: subviews.count)) {
      subview.place(
        at: CGPoint(x: x, y: bounds.maxY), anchor: .bottomLeading,
        proposal: ProposedViewSize(width: width, height: nil))
      x += width + spacing
    }
  }

  private func shares(of width: CGFloat, count: Int) -> [CGFloat] {
    let total = max(weights.prefix(count).reduce(0, +), 0.0001)
    let room = width - spacing * CGFloat(max(count - 1, 0))
    return (0..<count).map { room * (weights.indices.contains($0) ? weights[$0] : 0) / total }
  }
}
