import LociModel
import SwiftUI

/// What is held against what was meant: a thick ring of the shares held, a thin ring of the targets around
/// it, and a line for each with the drifted ones in amber.
struct PanelAllocationView: View {
  let allocation: PanelAllocation
  @Environment(\.panelData) private var data
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var grown = false
  private static let tones = [Palette.ink, Palette.inkMuted, Palette.accent, Palette.inkFaint]

  var body: some View {
    let slices = allocation.slices.map { (slice: $0, actual: data.number($0.actual), target: data.number($0.target)) }
    HStack(spacing: Spacing.m) {
      ZStack {
        ring(slices.map { $0.actual ?? 0 }, width: 12, inset: 6)
        ring(slices.map { $0.target ?? 0 }, width: 2.5, inset: 0)
        VStack(spacing: 1) {
          if let total = data.number(allocation.total) {
            Text(verbatim: PanelFigures.number(total, style: allocation.style, defaultDigits: 1))
              .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
          }
          if let change = data.number(allocation.change) {
            Text(verbatim: PanelFigures.change(change)).font(.system(size: 11)).foregroundStyle(
              PanelFigures.tone(change))
          }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(Spacing.m)
      }
      .frame(width: 112, height: 112)
      VStack(alignment: .leading, spacing: 7) {
        ForEach(Array(slices.enumerated()), id: \.offset) { index, entry in
          legend(entry.slice, actual: entry.actual, target: entry.target, tone: Self.tones[index % Self.tones.count])
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.bottom, Spacing.xxs)
    .onAppear {
      withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.9, 0.3, 1, duration: 1.1)) { grown = true }
    }
  }

  private func ring(_ shares: [Double], width: CGFloat, inset: CGFloat) -> some View {
    let total = max(shares.reduce(0, +), 1)
    let gap = 0.012
    return ZStack {
      ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
        let start = shares.prefix(index).reduce(0, +) / total
        let end = start + max(share / total - gap, 0)
        Circle()
          .inset(by: inset + width / 2)
          .trim(from: start, to: grown || reduceMotion ? end : start)
          .stroke(Self.tones[index % Self.tones.count], style: StrokeStyle(lineWidth: width, lineCap: .butt))
          .rotationEffect(.degrees(-90))
      }
    }
  }

  private func legend(_ slice: PanelSlice, actual: Double?, target: Double?, tone: Color) -> some View {
    let drifted = actual.map { allocation.drifted(actual: $0, target: target) } ?? false
    return HStack(spacing: Spacing.xs) {
      RoundedRectangle(cornerRadius: 3).fill(tone).frame(width: 8, height: 8)
      Text(verbatim: slice.name).foregroundStyle(Palette.ink).lineLimit(1)
      Spacer(minLength: Spacing.xxs)
      Text(verbatim: PanelFigures.number(actual, style: PanelStyle(format: .percent), defaultDigits: 0))
        .fontWeight(.semibold)
        .foregroundStyle(drifted ? Palette.accentInk : Palette.ink)
      if drifted, let target {
        Text(verbatim: PanelFigures.plain(target * 100, digits: 0)).foregroundStyle(Palette.inkFaint)
      }
    }
    .font(.system(size: 12.5))
    .monospacedDigit()
  }
}
