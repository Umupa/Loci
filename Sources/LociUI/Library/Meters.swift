import LociModel
import SwiftUI

/// How much of an item has been watched, as a line along the foot of its cover.
struct ProgressLine: View {
  let share: Double?

  var body: some View {
    if let share, share > 0 {
      GeometryReader { frame in
        ZStack(alignment: .leading) {
          Rectangle().fill(.black.opacity(0.28))
          Rectangle().fill(Palette.accent).frame(width: frame.size.width * share)
        }
      }
      .frame(height: 3)
    }
  }
}

/// A ring filling with the share done, or a wave while speech is being recognized.
struct ActivityMark: View {
  let activity: JobLine.Activity
  let progress: Fraction?

  var body: some View {
    if activity == .recognizing {
      Image(systemName: Symbols.recognizing)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Palette.accent)
        .frame(width: 13, height: 13)
    } else if let progress {
      ZStack {
        Circle().stroke(Palette.accent.opacity(0.3), lineWidth: 1.8)
        Circle().trim(from: 0, to: progress.value)
          .stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      .padding(1.5)
      .frame(width: 13, height: 13)
    } else {
      ProgressView().controlSize(.mini).frame(width: 13, height: 13)
    }
  }
}

/// A thin bar with the share done in amber.
struct Meter: View {
  let share: Double
  var width: CGFloat = Size.meter

  var body: some View {
    Capsule()
      .fill(Palette.fillStrong)
      .overlay(alignment: .leading) {
        Capsule().fill(Palette.accent).frame(width: width * min(max(share, 0), 1))
      }
      .frame(width: width, height: Size.meterHeight)
  }
}
