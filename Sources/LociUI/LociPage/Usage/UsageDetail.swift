import LociModel
import SwiftUI

/// An activity opened in place: how large its sessions start and grow, what the context is made of, and the
/// last few sessions (US-S6).
struct UsageDetail: View {
  let activity: ActivityUsage
  @Environment(\.fixedNow) private var fixedNow

  static let recent = 6

  var body: some View {
    let flags = Dictionary(activity.flags.map { ($0.figure, $0) }, uniquingKeysWith: { first, _ in first })
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 34) {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
          GridRow {
            figure(.loci("usage.start"), TokenFigure.text(activity.start), flags[.perSession])
            figure(.loci("usage.typical"), TokenFigure.text(activity.typical))
            figure(.loci("usage.peak"), TokenFigure.text(activity.peak), flags[.cacheRead])
          }
          GridRow {
            figure(.loci("usage.growth"), "+" + TokenFigure.text(activity.growth))
            figure(.loci("usage.hit"), TokenFigure.percent(activity.hit), flags[.fresh])
            figure(.loci("usage.calls.each"), Self.calls(activity.calls))
          }
        }
        .frame(width: 300, alignment: .leading)
        VStack(alignment: .leading, spacing: 9) {
          Text(.loci("usage.makeup")).font(.system(size: 11.5)).foregroundStyle(Palette.inkMuted)
          MakeupBar(parts: activity.makeup)
        }
      }
      sessions
    }
    .padding(.leading, 59)
    .padding(.trailing, 20)
    .padding(.top, 6)
    .padding(.bottom, 22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.fill)
  }

  private func figure(_ label: LocalizedStringResource, _ value: String, _ flag: UsageFlag? = nil) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.system(size: 11.5)).foregroundStyle(Palette.inkMuted)
      UsageNumber(text: value, flag: flag, weight: .semibold, size: 18)
    }
  }

  private var sessions: some View {
    let recent = Array(activity.sessions.suffix(Self.recent).reversed())
    let widest = max(recent.map(\.context.peak).max() ?? 0, 1)
    return Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 7) {
      GridRow {
        Color.clear.frame(width: 1, height: 1)
        Text(.loci("usage.calls.each"))
        Color.clear.frame(height: 1).gridColumnAlignment(.leading)
        Text(.loci("usage.start"))
        Text(.loci("usage.peak"))
        Text(.loci("usage.fresh"))
        Color.clear.frame(width: 1, height: 1)
      }
      .font(.system(size: 11))
      .foregroundStyle(Palette.inkFaint)
      ForEach(recent) { session in
        GridRow {
          Text(verbatim: when(session.startedAt.date)).foregroundStyle(Palette.inkMuted).gridColumnAlignment(.leading)
          Text(verbatim: "\(session.calls)")
          ContextTrack(span: session.context, widest: widest)
          Text(verbatim: TokenFigure.text(session.context.start))
          Text(verbatim: TokenFigure.text(session.context.peak))
          Text(verbatim: TokenFigure.text(session.tokens.fresh)).fontWeight(.semibold)
          if let outcome = session.outcome {
            OutcomeDots(outcomes: [outcome])
          } else {
            Color.clear.frame(width: 7, height: 7)
          }
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(Palette.ink)
      }
    }
  }

  private func when(_ date: Date) -> String {
    let calendar = Calendar.current
    let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    if calendar.isDate(date, inSameDayAs: fixedNow ?? Date()) { return time }
    return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date)) \(time)"
  }

  private static func calls(_ calls: Double) -> String {
    calls < 10 ? String(format: "%.1f×", calls).replacingOccurrences(of: ".0×", with: "×") : "\(Int(calls.rounded()))×"
  }
}

/// A session's context on a track as wide as the largest shown: grey up to where it started, ink to its peak.
private struct ContextTrack: View {
  let span: ContextSpan
  let widest: Int

  var body: some View {
    GeometryReader { proxy in
      let unit = proxy.size.width / CGFloat(widest)
      Capsule().fill(Palette.fillStrong)
        .overlay(alignment: .leading) {
          HStack(spacing: 0) {
            Rectangle().fill(Palette.ink.opacity(0.35)).frame(width: unit * CGFloat(span.start))
            Rectangle().fill(Palette.ink).frame(width: unit * CGFloat(max(span.peak - span.start, 0)))
          }
          .clipShape(Capsule())
        }
    }
    .frame(height: 4)
    .frame(minWidth: 200)
  }
}
