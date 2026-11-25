import LociModel
import SwiftUI

/// A token count as the page writes it: 940, 71.4K, 3.85M.
enum TokenFigure {
  static func text(_ count: Int) -> String {
    let value = Double(count)
    switch count {
    case 10_000_000...: return trimmed(value / 1_000_000, digits: 1) + "M"
    case 1_000_000...: return trimmed(value / 1_000_000, digits: 2) + "M"
    case 100_000...: return trimmed(value / 1000, digits: 0) + "K"
    case 1000...: return trimmed(value / 1000, digits: 1) + "K"
    default: return String(count)
    }
  }

  static func percent(_ share: Double) -> String {
    "\(Int((share * 100).rounded()))%"
  }

  private static func trimmed(_ value: Double, digits: Int) -> String {
    var text = String(format: "%.\(digits)f", value)
    while text.contains("."), text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
  }
}

extension UsageKind {
  var name: LocalizedStringResource {
    switch self {
    case .main: .loci("usage.kindMain")
    case .course: .loci("usage.kindCourse")
    case .item: .loci("usage.kindItem")
    case .panel: .loci("usage.kindPanel")
    case .timer: .loci("usage.kindTimer")
    case .review: .loci("usage.kindReview")
    }
  }

  var symbol: String {
    switch self {
    case .main: Symbols.ask
    case .course: Symbols.course
    case .item: Symbols.notes
    case .panel: Symbols.panels
    case .timer: Symbols.schedule
    case .review: Symbols.review
    }
  }

  /// The kind's ink in the chart: darker for the kinds the companion is asked for, lighter for its own work.
  var shade: Color {
    switch self {
    case .course: Palette.ink.opacity(0.84)
    case .main: Palette.ink.opacity(0.6)
    case .panel: Palette.ink.opacity(0.42)
    case .timer: Palette.ink.opacity(0.3)
    case .review: Palette.ink.opacity(0.22)
    case .item: Palette.ink.opacity(0.14)
    }
  }
}

extension UsageActivity {
  /// What a row is called when Loci keeps no title for it.
  var name: LocalizedStringResource {
    switch self {
    case .main, .project: .loci("usage.kindMain")
    case .review: .loci("usage.review")
    case .followUp: .loci("usage.followUp")
    case .repair: .loci("usage.repair")
    case .item, .course, .panel, .schedule: UsageKind(self).name
    }
  }
}

extension ContextSource {
  var name: Text {
    switch self {
    case .runtime: Text(.loci("usage.partRuntime"))
    case .instructions: Text(verbatim: "AGENTS.md")
    case .prefix: Text(.loci("usage.partPrefix"))
    case .tool(let name): Text(verbatim: name).monospaced()
    case .talk: Text(.loci("usage.partTalk"))
    case .output: Text(.loci("usage.partOutput"))
    }
  }

  /// The part's color in a makeup bar; the tools take the earthy colors in the order they come.
  func color(tool index: Int) -> AnyShapeStyle {
    switch self {
    case .runtime: AnyShapeStyle(Palette.ink.opacity(0.85))
    case .instructions: AnyShapeStyle(Palette.ink.opacity(0.42))
    case .prefix: AnyShapeStyle(Palette.accent)
    case .tool: AnyShapeStyle(UsageInks.tools[index % UsageInks.tools.count])
    case .talk: AnyShapeStyle(Palette.ink.opacity(0.14))
    case .output: AnyShapeStyle(UsageInks.output)
    }
  }
}

/// The colors the makeup bar gives what the tools brought back and what the model wrote.
enum UsageInks {
  static let tools = [
    Color(dark: 0x98B28B, light: 0x6F8A63), Color(dark: 0x8AA4BC, light: 0x56708A),
    Color(dark: 0xD5B985, light: 0xB99A5F), Color(dark: 0xB494AD, light: 0x8A6683),
    Color(dark: 0x7DB5B0, light: 0x4C8783), Color(dark: 0xB3A693, light: 0x9C8F7E),
  ]
  static let output = Color(dark: 0xD7917A, light: 0xB06A4E)
}

extension UsageFlag {
  var reason: Text {
    switch self {
    case .heavyStart(let share):
      let start = TokenFigure.percent(share)
      return Text(.loci("usage.flagStart \(start)"))
    case .largeContext(let peak):
      let tokens = TokenFigure.text(peak)
      return Text(.loci("usage.flagPeak \(tokens)"))
    case .lowCache(let hit):
      let cached = TokenFigure.percent(hit)
      return Text(.loci("usage.flagCache \(cached)"))
    case .idleStreak(let count): return Text(.loci("usage.flagStreak \(count)"))
    case .idleShare(let idle, let shown): return Text(.loci("usage.flagIdle \(idle) \(shown)"))
    }
  }
}

/// A figure in tabular digits, amber with its reason on hover when a flag marks it.
struct UsageNumber: View {
  let text: String
  var flag: UsageFlag?
  var weight: Font.Weight = .regular
  var size: CGFloat = 12.5
  var muted = false

  var body: some View {
    Text(verbatim: text)
      .font(.system(size: size, weight: weight).monospacedDigit())
      .foregroundStyle(flag != nil ? Palette.accentInk : muted ? Palette.inkMuted : Palette.ink)
      .help(flag?.reason ?? Text(verbatim: ""))
  }
}

/// The fresh tokens of each session, oldest to newest, with the last one dotted.
struct Sparkline: View {
  let values: [Int]

  var body: some View {
    Canvas { context, size in
      let top = Double(values.max() ?? 0) * 1.1
      guard top > 0 else { return }
      let points = values.enumerated().map { index, value in
        CGPoint(
          x: values.count == 1 ? size.width / 2 : size.width * Double(index) / Double(values.count - 1),
          y: values.count == 1 ? size.height / 2 : size.height * (1 - Double(value) / top))
      }
      var line = Path()
      line.addLines(points)
      var area = line
      area.addLine(to: CGPoint(x: points.last?.x ?? 0, y: size.height))
      area.addLine(to: CGPoint(x: points.first?.x ?? 0, y: size.height))
      context.fill(area, with: .color(Palette.fill))
      context.stroke(
        line, with: .color(Palette.ink.opacity(0.55)), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
      if let last = points.last {
        context.fill(
          Path(ellipseIn: CGRect(x: last.x - 2.2, y: last.y - 2.2, width: 4.4, height: 4.4)), with: .color(Palette.ink))
      }
    }
  }
}

/// One dot for each of the last runs: solid when it wrote something, hollow when it wrote nothing, amber when
/// it failed (US-S5).
struct OutcomeDots: View {
  let outcomes: [UsageOutcome]
  var flag: UsageFlag?

  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(outcomes.enumerated()), id: \.offset) { _, outcome in
        switch outcome {
        case .made: Circle().fill(Palette.ink)
        case .failed: Circle().fill(Palette.accent)
        case .nothingNew: Circle().strokeBorder(flag != nil ? Palette.accent : Palette.inkFaint, lineWidth: 1.3)
        }
      }
      .frame(width: 7, height: 7)
    }
    .help(flag?.reason ?? Text(verbatim: ""))
  }
}

/// What a context is made of, one segment a part, with the parts named below; hovering a name lights its
/// segment.
struct MakeupBar: View {
  let parts: [ContextPart]
  var height: CGFloat = 10
  var named = true
  @State private var lit: ContextSource?
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    let total = max(parts.reduce(0) { $0 + $1.tokens }, 1)
    let shown = parts.filter { Double($0.tokens) / Double(total) >= 0.01 }
    let tools = shown.map(\.source).filter { if case .tool = $0 { true } else { false } }
    VStack(alignment: .leading, spacing: Spacing.s) {
      GeometryReader { proxy in
        let room = proxy.size.width - CGFloat(max(shown.count - 1, 0)) * 2
        HStack(spacing: 2) {
          ForEach(shown, id: \.source) { part in
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
              .fill(part.source.color(tool: tools.firstIndex(of: part.source) ?? 0))
              .frame(width: max(2, room * CGFloat(part.tokens) / CGFloat(total)))
              .opacity(lit == nil || lit == part.source ? 1 : 0.25)
              .help(Text(verbatim: TokenFigure.text(part.tokens)))
          }
        }
      }
      .frame(height: height)
      if named {
        FlowRow(spacing: Spacing.m) {
          ForEach(shown, id: \.source) { part in
            HStack(spacing: 6) {
              RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(part.source.color(tool: tools.firstIndex(of: part.source) ?? 0))
                .frame(width: 8, height: 8)
              part.source.name.foregroundStyle(Palette.inkMuted)
              Text(verbatim: TokenFigure.percent(Double(part.tokens) / Double(total)))
                .monospacedDigit().foregroundStyle(Palette.ink)
            }
            .font(.system(size: 12))
            .onHover { inside in withAnimation(reduceMotion ? nil : Motion.quick) { lit = inside ? part.source : nil } }
          }
        }
      }
    }
  }
}
