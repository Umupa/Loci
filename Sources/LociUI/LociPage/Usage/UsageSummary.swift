import LociModel
import SwiftUI

/// The card at the top of the usage page: fresh tokens, cache reads, sessions, how large a session starts and
/// how much came from the cache (US-S2).
struct UsageSummary: View {
  let report: UsageReport

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
    HStack(alignment: .top, spacing: 0) {
      cell(.loci("usage.fresh"), ruled: false) {
        Big(count: report.tokens.fresh)
        HStack(spacing: 10) {
          Sub(text: "↧ " + TokenFigure.text(report.tokens.cacheWrite)).help(Text(.loci("usage.cacheWrite")))
          Sub(text: "↑ " + TokenFigure.text(report.tokens.output)).help(Text(.loci("usage.part.output")))
        }
      }
      cell(.loci("usage.cacheRead")) {
        Big(count: report.tokens.cacheRead)
        Text(.loci("usage.calls \(report.calls)")).font(.system(size: 11.5).monospacedDigit())
          .foregroundStyle(Palette.inkMuted)
      }
      cell(.loci("usage.sessions")) {
        Text(verbatim: "\(report.sessions.count)").font(Self.figure)
        HStack(spacing: 0) {
          Sub(text: TokenFigure.text(report.sessions.isEmpty ? 0 : report.tokens.fresh / report.sessions.count) + " / ")
          Text(.loci("usage.each")).font(.system(size: 11.5)).foregroundStyle(Palette.inkMuted)
        }
      }
      cell(.loci("usage.start")) { start }.frame(minWidth: 230)
      cell(.loci("usage.hit")) {
        Text(verbatim: TokenFigure.percent(report.hit)).font(Self.figure)
        ShareTrack(share: report.hit)
      }
    }
    .padding(.vertical, 18)
    .background(Palette.surface, in: shape)
    .cardShadow(shape)
  }

  static let figure = Font.system(size: 28, weight: .semibold).monospacedDigit()

  private var start: some View {
    let total = report.start.reduce(0) { $0 + $1.tokens }
    let heavy = report.typical > 0 && Double(total) / Double(report.typical) > 0.5
    return VStack(alignment: .leading, spacing: Spacing.xs) {
      Big(count: total, amber: heavy)
        .help(heavy ? UsageFlag.heavyStart(Double(total) / Double(report.typical)).reason : Text(verbatim: ""))
      MakeupBar(parts: report.start, height: 6)
    }
  }

  private func cell<Content: View>(
    _ label: LocalizedStringResource, ruled: Bool = true, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(label).font(.system(size: 11.5)).foregroundStyle(Palette.inkMuted)
      content()
    }
    .padding(.horizontal, 20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .leading) { Rectangle().fill(ruled ? Palette.line : .clear).frame(width: 1) }
  }
}

/// A large count, its unit smaller beside it.
private struct Big: View {
  let count: Int
  var amber = false

  var body: some View {
    let text = TokenFigure.text(count)
    let unit = text.last.map { $0.isLetter ? String($0) : "" } ?? ""
    HStack(alignment: .firstTextBaseline, spacing: 2) {
      Text(verbatim: String(text.dropLast(unit.count))).font(UsageSummary.figure)
      Text(verbatim: unit).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.inkMuted)
    }
    .foregroundStyle(amber ? Palette.accentInk : Palette.ink)
  }
}

private struct Sub: View {
  let text: String

  var body: some View {
    Text(verbatim: text).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Palette.inkMuted)
  }
}

/// A share as a short filled track.
private struct ShareTrack: View {
  let share: Double

  var body: some View {
    GeometryReader { proxy in
      Capsule().fill(Palette.fillStrong)
        .overlay(alignment: .leading) { Capsule().fill(Palette.ink).frame(width: proxy.size.width * share) }
    }
    .frame(height: 6)
  }
}
