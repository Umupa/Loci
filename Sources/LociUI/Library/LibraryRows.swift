import LociModel
import SwiftUI

/// A cover on the shelf: large, with the title and its length and source over the foot of the picture, and a
/// thin amber line along the bottom for how much has been watched. Work going on or stopped shows under the
/// title as it does in the list.
struct ShelfCover: View {
  let item: Item
  let share: Double?
  var job: Job?
  var act: (JobLine.Fix) -> Void = { _ in }

  var body: some View {
    Cover(item: item, corner: Radius.card, squareInset: 0.11, squareCorner: Size.shelfHeight * 0.78 * 0.05)
      .overlay(alignment: .bottom) { caption }
      .overlay(alignment: .bottom) { ProgressLine(share: share) }
      .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
      .coverShadow()
      .frame(height: Size.shelfHeight)
      .contentShape(Rectangle())
  }

  private var caption: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: item.title)
        .font(Typography.shelfTitle)
        .foregroundStyle(Palette.onCover)
        .lineLimit(2)
        .lineSpacing(1)
      Text(verbatim: item.byline)
        .font(Typography.mono)
        .foregroundStyle(Palette.onCoverMuted)
        .lineLimit(1)
      if JobLine(job) != .none {
        JobStatus(line: JobLine(job), act: act, onCover: true).padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Spacing.m)
    .padding(.top, 64)
    .padding(.bottom, 15)
    .background(
      LinearGradient(
        stops: [
          .init(color: Palette.coverShade.opacity(0), location: 0),
          .init(color: Palette.coverShade.opacity(0.5), location: 0.4),
          .init(color: Palette.coverShade.opacity(0.86), location: 1),
        ], startPoint: .top, endPoint: .bottom))
  }
}

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

/// One item in the library's list: a small cover, the title and where it comes from, and on the right how the
/// work on it stands.
struct LibraryRow: View {
  let item: Item
  let job: Job?
  let share: Double?
  let act: (JobLine.Fix) -> Void

  var body: some View {
    let line = JobLine(job)
    HStack(spacing: 14) {
      Cover(item: item, corner: Radius.thumbnail, dimmed: line.isDownloading)
        .overlay(alignment: .bottom) { ProgressLine(share: share) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
            .strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
        )
        .frame(width: Size.listThumbnail, height: Size.listThumbnail * 9 / 16)
      VStack(alignment: .leading, spacing: 5) {
        Text(verbatim: item.title)
          .font(Typography.rowTitle)
          .foregroundStyle(Palette.ink)
          .lineLimit(1)
        Text(verbatim: item.byline)
          .font(Typography.mono)
          .foregroundStyle(Palette.inkFaint)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      JobStatus(line: line, act: act)
        .frame(width: Size.listStatus, alignment: .trailing)
    }
    .padding(Spacing.xs)
    .contentShape(Rectangle())
  }
}

extension JobLine {
  var isDownloading: Bool {
    if case .working(.downloading, _) = self { return true }
    return false
  }
}

/// On the right of a row: the work going on with its share, or the button that gets it going again.
struct JobStatus: View {
  let line: JobLine
  let act: (JobLine.Fix) -> Void
  /// Over the foot of a cover, where the words are light on the dark shade.
  var onCover = false

  var body: some View {
    HStack(spacing: 10) {
      switch line {
      case .none:
        EmptyView()
      case .working(let activity, let progress):
        HStack(spacing: 6) {
          ActivityMark(activity: activity, progress: progress)
          Text(
            joining: Text(activity.name), Text(verbatim: progress.map { " \(Int(($0.value * 100).rounded()))%" } ?? "")
          )
          .font(Typography.mono)
          .foregroundStyle(onCover ? Palette.onCoverMuted : Palette.inkMuted)
        }
        .fixedSize()
        if let progress { Meter(share: progress.value) }
      case .action(let fix, let problem):
        if let why = fix.why(problem) {
          why.font(.system(size: 12)).foregroundStyle(onCover ? Palette.onCoverMuted : Palette.inkMuted).lineLimit(1)
            .fixedSize()
            .help(problem.map { Text(verbatim: $0.reason) } ?? why)
        }
        Button(action: { act(fix) }) { fix.label }.buttonStyle(PushStyle()).fixedSize()
          .changesData(fix.changesData)
      }
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

extension View {
  /// The soft shadow a cover casts on the page.
  func coverShadow() -> some View {
    shadow(color: Color(nsColor: NSColor(rgb: 0x281905)).opacity(0.08), radius: 9, y: 6)
      .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
  }
}
