import LociModel
import SwiftUI

/// Fresh tokens by day, or by hour today, stacked by kind, beside each kind's total; choosing a kind lights it
/// amber and narrows the page to it (US-S3).
struct UsageChart: View {
  let report: UsageReport
  let span: UsageSpan
  @Binding var kind: UsageKind?
  var calendar = Calendar.current
  @Environment(\.reducesMotion) private var reduceMotion

  private static let plot: CGFloat = 176

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
    HStack(alignment: .top, spacing: 26) {
      chart
      legend.frame(width: 250)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 18)
    .background(Palette.surface, in: shape)
    .cardShadow(shape)
  }

  private var chart: some View {
    let scale = Scale(top: report.buckets.map(\.total).max() ?? 0)
    return VStack(spacing: 6) {
      ZStack(alignment: .bottomLeading) {
        ForEach(0...3, id: \.self) { step in
          HStack(spacing: Spacing.xs) {
            Text(verbatim: step == 0 ? "0" : TokenFigure.text(scale.step * step))
              .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Palette.inkFaint)
              .frame(width: 34, alignment: .trailing)
            Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline)
          }
          .offset(y: -Self.plot * CGFloat(step) / 3 + 6)
        }
        HStack(alignment: .bottom, spacing: report.buckets.count > 20 ? 4 : 10) {
          ForEach(report.buckets, id: \.start) { bucket in
            column(bucket, scale: scale)
          }
        }
        .padding(.leading, 42)
      }
      .frame(height: Self.plot + 6)
      axis.padding(.leading, 42)
    }
    .frame(maxWidth: .infinity)
  }

  private func column(_ bucket: UsageReport.Bucket, scale: Scale) -> some View {
    VStack(spacing: 1) {
      ForEach(UsageKind.allCases.reversed(), id: \.self) { kind in
        if let fresh = bucket.fresh[kind], fresh > 0 {
          Rectangle()
            .fill(self.kind == kind ? Palette.accent : kind.shade)
            .frame(height: Self.plot * CGFloat(fresh) / CGFloat(scale.top))
            .opacity(self.kind == nil || self.kind == kind ? 1 : 0.18)
        }
      }
    }
    .frame(maxWidth: 22)
    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    .contentShape(Rectangle())
    .help(Text(verbatim: "\(moment(bucket.start)) · \(TokenFigure.text(bucket.total))"))
    .animation(reduceMotion ? nil : Motion.standard, value: bucket)
  }

  private var axis: some View {
    let count = report.buckets.count
    let marks = span == .today ? [0, 6, 12, 18, 23] : count > 7 ? [0, 7, 14, 21, count - 1] : Array(0..<count)
    return GeometryReader { proxy in
      ForEach(marks.filter { $0 < count }, id: \.self) { index in
        label(of: report.buckets[index].start, last: index == count - 1)
          .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Palette.inkFaint)
          .fixedSize()
          .position(x: proxy.size.width * (CGFloat(index) + 0.5) / CGFloat(count), y: 7)
      }
    }
    .frame(height: 14)
  }

  /// Under a column: its hour on today's chart, its day otherwise, and 今天 under the last day.
  private func label(of start: Date, last: Bool) -> Text {
    last && span != .today ? Text(.loci("usage.today")) : Text(verbatim: moment(start))
  }

  private func moment(_ start: Date) -> String {
    if span == .today { return String(format: "%02d:00", calendar.component(.hour, from: start)) }
    return "\(calendar.component(.month, from: start))/\(calendar.component(.day, from: start))"
  }

  private var legend: some View {
    let most = max(report.kinds.first?.fresh ?? 0, 1)
    return VStack(alignment: .leading, spacing: 3) {
      ForEach(report.kinds, id: \.kind) { total in
        let chosen = kind == total.kind
        Button {
          withAnimation(reduceMotion ? nil : Motion.standard) { kind = chosen ? nil : total.kind }
        } label: {
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.xs) {
              RoundedRectangle(cornerRadius: 2.5).fill(chosen ? Palette.accent : total.kind.shade).frame(
                width: 8, height: 8)
              Text(total.kind.name).font(.system(size: 13)).foregroundStyle(Palette.ink)
              Text(verbatim: "\(total.sessions)").font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(Palette.inkFaint)
              Spacer(minLength: 0)
              UsageNumber(text: TokenFigure.text(total.fresh), weight: .semibold, size: 13)
            }
            GeometryReader { proxy in
              Capsule().fill(Palette.fillStrong)
                .overlay(alignment: .leading) {
                  Capsule().fill(chosen ? Palette.accent : total.kind.shade)
                    .frame(width: proxy.size.width * CGFloat(total.fresh) / CGFloat(most))
                }
            }
            .frame(height: 3)
            .padding(.leading, 16)
          }
          .padding(.vertical, 7)
          .padding(.horizontal, 9)
          .background(chosen ? Palette.fill : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
  }

  /// The chart's height in round steps: the top line is three steps of 1, 2, 2.5 or 5 times a power of ten.
  private struct Scale {
    let step: Int
    var top: Int { step * 3 }

    init(top highest: Int) {
      let third = max(Double(highest) / 3, 1)
      let power = pow(10, floor(log10(third)))
      let factor = [1, 2, 2.5, 5, 10].first { $0 * power >= third } ?? 10
      step = max(Int(factor * power), 1)
    }
  }
}
