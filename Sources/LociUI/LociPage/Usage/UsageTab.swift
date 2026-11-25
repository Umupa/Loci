import LociModel
import SwiftUI

/// What the companion's sessions cost, read from the files the CLIs keep: a summary, a chart by day and a
/// table of activities (US-S1–US-S8).
struct UsageTab: View {
  @Environment(\.host) private var host
  @Environment(\.showFailure) private var showFailure
  @Environment(\.fixedNow) private var fixedNow
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var usage: [SessionUsage]?
  @State private var span: UsageSpan
  @State private var kind: UsageKind?
  @State private var opened: UsageActivity?

  /// Starts on `span`, narrowed to `kind`, with `opened`'s row open, for a snapshot.
  init(span: UsageSpan = .week, kind: UsageKind? = nil, opened: UsageActivity? = nil) {
    _span = State(initialValue: span)
    _kind = State(initialValue: kind)
    _opened = State(initialValue: opened)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Spacer()
        CapsulePicker(
          selection: $span.animation(reduceMotion ? nil : Motion.standard),
          options: [(.today, .loci("usage.today")), (.week, .loci("usage.week")), (.month, .loci("usage.month"))],
          compact: true)
      }
      if let usage {
        let report = UsageReport(usage, span: span, kind: kind, now: now, calendar: .current)
        UsageSummary(report: report)
        UsageChart(report: report, span: span, kind: $kind)
        if !report.activities.isEmpty {
          UsageTable(activities: report.activities, opened: $opened)
        }
      }
    }
    .frame(maxWidth: 960, alignment: .leading)
    .task { await load() }
  }

  private var now: Date { fixedNow ?? Date() }

  private func load() async {
    let since = Calendar.current.date(byAdding: .day, value: -UsageSpan.month.days, to: now) ?? now
    do throws(HostError) {
      usage = try await host.run(ReadUsage(since: Timestamp(since)))
    } catch {
      showFailure(error)
    }
  }
}
