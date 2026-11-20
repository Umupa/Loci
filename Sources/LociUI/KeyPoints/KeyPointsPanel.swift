import LociModel
import SwiftUI

/// The key points page of the panel beside a video, a podcast or an article: a button to pick them until
/// they are, a shimmering list while they are being picked, then the list with what they were picked with.
struct KeyPointsPanel: View {
  @Environment(\.host) private var host
  @Environment(\.locale) private var locale
  let item: EntityID
  /// The video or audio item whose pictures the rows show; `nil` for an article.
  let media: Item?
  let page: KeyPointsPage?
  /// The key point playing, or the passage in view, with how far through it is.
  let current: (index: Int, progress: Double?)?
  let frames: KeyPointFrames?
  let open: (KeyPoint) -> Void
  @State private var choice: KeyPointChoice?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let page, page.keyPoints != nil || page.picking != nil {
        KeyPointChoiceBar(choice: chosen, picking: page.picking == .running) { pick(choice ?? page.choice) }
          .changesData()
        summary(page)
        list(page)
      } else if let page {
        empty(page)
      }
    }
    .padding(.horizontal, Spacing.m)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var chosen: Binding<KeyPointChoice> {
    Binding {
      choice ?? page?.keyPoints?.choice ?? page?.choice ?? .standard
    } set: {
      choice = $0
    }
  }

  private func pick(_ choice: KeyPointChoice) {
    Task { _ = try? await host.run(PickKeyPoints(item: item, choice: choice)) }
  }

  private func summary(_ page: KeyPointsPage) -> some View {
    HStack(spacing: 6) {
      Image(systemName: Symbols.keyPoints).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
      if page.picking == .running {
        Text(.loci("keypoints.picking"))
      } else if let points = page.keyPoints?.points {
        Text(verbatim: KeyPointWords.summary(points, in: locale))
      }
    }
    .font(.system(size: 12).monospaced())
    .foregroundStyle(Palette.inkMuted)
  }

  @ViewBuilder private func list(_ page: KeyPointsPage) -> some View {
    if page.picking == .running {
      VStack(spacing: 2) {
        ForEach(0..<(page.keyPoints?.choice ?? chosen.wrappedValue).count.range.lowerBound, id: \.self) { _ in
          KeyPointPlaceholder(article: media == nil)
        }
      }
      .transition(.opacity)
    } else {
      if case .failed(let reason) = page.picking {
        Text(verbatim: reason)
          .font(.system(size: 12))
          .foregroundStyle(Palette.inkMuted)
          .lineLimit(3)
          .padding(.horizontal, Spacing.xs)
      }
      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(Array((page.keyPoints?.points ?? []).enumerated()), id: \.offset) { index, point in
            KeyPointRow(
              media: media, point: point, number: index + 1,
              progress: current?.index == index ? (current?.progress ?? 0) : nil, frames: frames
            ) { open(point) }
            .rising(after: Double(index) * 0.06)
          }
        }
        .padding(.bottom, Spacing.l)
      }
      .scrollIndicators(.never)
    }
  }

  private func empty(_ page: KeyPointsPage) -> some View {
    VStack(spacing: 18) {
      Image(systemName: Symbols.keyPoints)
        .font(.system(size: 28, weight: .regular))
        .foregroundStyle(Palette.accent)
        .frame(width: 64, height: 64)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.tint))
        .overlay(
          RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(
            Palette.accent.opacity(0.35), lineWidth: Size.hairline))
      PrimaryButton(action: { pick(page.choice) }) { Text(.loci("keypoints.pick")) }
        .changesData()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

extension View {
  /// Rises into place as it fades in, `delay` seconds after it appears.
  fileprivate func rising(after delay: Double) -> some View {
    modifier(Rising(delay: delay))
  }
}

private struct Rising: ViewModifier {
  let delay: Double
  @State private var shown = false

  func body(content: Content) -> some View {
    content
      .opacity(shown ? 1 : 0)
      .offset(y: shown ? 0 : Motion.riseDistance)
      .onAppear { withAnimation(Motion.rise.delay(delay)) { shown = true } }
  }
}

/// A key point's row while it is still being picked: its shapes, shimmering.
private struct KeyPointPlaceholder: View {
  let article: Bool

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.s) {
      if article {
        Shimmer().frame(width: 18, height: 14)
      } else {
        Shimmer().frame(width: 104, height: 58.5)
      }
      VStack(alignment: .leading, spacing: 7) {
        Shimmer().frame(height: 13).frame(maxWidth: 170, alignment: .leading)
        Shimmer().frame(height: 11).frame(maxWidth: 220, alignment: .leading)
        Shimmer().frame(width: 90, height: 10)
      }
      .padding(.top, 2)
      Spacer(minLength: 0)
    }
    .padding(Spacing.xs)
    .accessibilityHidden(true)
  }
}
