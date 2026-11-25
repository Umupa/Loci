import LociModel
import SwiftUI

/// One row an activity, most fresh tokens first; a row opens in place to show what its context is made of
/// (US-S4–US-S7).
struct UsageTable: View {
  let activities: [ActivityUsage]
  @Binding var opened: UsageActivity?
  @Environment(\.reducesMotion) private var reduceMotion

  static let columns = [
    GridItem(.flexible(minimum: 140), spacing: 12, alignment: .leading),
    GridItem(.fixed(78), spacing: 12, alignment: .leading), GridItem(.fixed(40), spacing: 12, alignment: .trailing),
    GridItem(.fixed(64), spacing: 12, alignment: .trailing), GridItem(.fixed(96), spacing: 12, alignment: .leading),
    GridItem(.fixed(70), spacing: 12, alignment: .trailing), GridItem(.fixed(66), spacing: 12, alignment: .trailing),
    GridItem(.fixed(122), spacing: 0, alignment: .leading),
  ]

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
    VStack(spacing: 0) {
      header
      ForEach(activities) { activity in
        row(activity)
        if opened == activity.activity {
          UsageDetail(activity: activity)
            .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
        }
      }
    }
    .padding(.vertical, 6)
    .background(Palette.surface, in: shape)
    .clipShape(shape)
    .cardShadow(shape)
  }

  private static let headings: [LocalizedStringResource] = [
    .loci("usage.activity"), .loci("usage.model"), .loci("usage.count"), .loci("usage.each"), .loci("usage.trend"),
    .loci("usage.fresh"), .loci("usage.cacheRead"), .loci("usage.outcome"),
  ]

  private var header: some View {
    LazyVGrid(columns: Self.columns, spacing: 0) {
      ForEach(Array(Self.headings.enumerated()), id: \.offset) { _, heading in
        Text(heading).lineLimit(1).fixedSize()
      }
    }
    .font(.system(size: 11.5))
    .foregroundStyle(Palette.inkMuted)
    .padding(.horizontal, 20)
    .frame(height: 38)
  }

  private func row(_ activity: ActivityUsage) -> some View {
    let flags = Dictionary(activity.flags.map { ($0.figure, $0) }, uniquingKeysWith: { first, _ in first })
    let open = opened == activity.activity
    return Button {
      withAnimation(reduceMotion ? nil : Motion.standard) { opened = open ? nil : activity.activity }
    } label: {
      LazyVGrid(columns: Self.columns, spacing: 0) {
        HStack(spacing: 11) {
          UsageTile(symbol: activity.kind.symbol)
          ActivityName(activity: activity)
        }
        Text(verbatim: activity.model.map(ModelName.short) ?? "—")
          .font(.system(size: 11).monospaced()).foregroundStyle(Palette.inkMuted)
          .padding(.horizontal, 7).padding(.vertical, 2)
          .background(Palette.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
          .lineLimit(1)
        UsageNumber(text: "\(activity.sessions.count)", muted: true)
        UsageNumber(text: TokenFigure.text(activity.perSession), flag: flags[.perSession])
        Sparkline(values: activity.sessions.map(\.tokens.fresh)).frame(width: 96, height: 22)
        UsageNumber(text: TokenFigure.text(activity.fresh), flag: flags[.fresh], weight: .semibold, size: 13)
        UsageNumber(text: TokenFigure.text(activity.tokens.cacheRead), flag: flags[.cacheRead], muted: true)
        if let outcomes = activity.outcomes {
          OutcomeDots(outcomes: outcomes, flag: flags[.outcomes])
        } else {
          Color.clear.frame(height: 1)
        }
      }
      .padding(.horizontal, 20)
      .frame(height: 52)
      .background(open ? Palette.fill : .clear)
      .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: Size.hairline).padding(.horizontal, 20) }
      .contentShape(Rectangle())
    }
    .buttonStyle(HoverRowStyle())
  }
}

/// An activity's name: its title, or the kind's name when it has none.
struct ActivityName: View {
  let activity: ActivityUsage

  var body: some View {
    Group {
      if let title = activity.title {
        Text(verbatim: title)
      } else {
        Text(activity.activity.name)
      }
    }
    .font(.system(size: 13.5))
    .foregroundStyle(Palette.ink)
    .lineLimit(1)
  }
}

/// A kind's symbol on a small raised tile.
struct UsageTile: View {
  let symbol: String

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    Image(systemName: symbol)
      .font(.system(size: 12.5, weight: .medium))
      .foregroundStyle(Palette.ink)
      .frame(width: 28, height: 28)
      .background(Palette.surface, in: shape)
      .overlay(shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
  }
}

/// A model's name without its vendor: `claude-opus-5-5` reads `opus-5-5`.
enum ModelName {
  static func short(_ model: String) -> String {
    model.hasPrefix("claude-") ? String(model.dropFirst(7)) : model
  }
}

/// A row that washes faintly under the pointer.
private struct HoverRowStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    HoverWash { configuration.label }
  }
}

private struct HoverWash<Content: View>: View {
  @ViewBuilder let content: Content
  @State private var pointed = false

  var body: some View {
    content
      .background(pointed ? Palette.fill : .clear)
      .onHover { pointed = $0 }
  }
}
