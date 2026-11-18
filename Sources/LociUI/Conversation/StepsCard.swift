import LociModel
import SwiftUI

/// The thinking and tools between two replies. Each thought is a row; tools used one after another fold
/// into one row that counts what they did, and open to a row each.
struct StepsCard: View {
  let steps: [ConversationStep]
  /// Folded runs of tools start open, for looking at them.
  var opened = false

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(Self.segments(steps).enumerated()), id: \.element.id) { index, segment in
        if index > 0 { Divider() }
        switch segment {
        case .one(let step): StepRow(step: step)
        case .tools(let steps): ToolRun(steps: steps, open: opened)
        }
      }
    }
    .modifier(StepsBackground())
  }

  /// A thought on its own, a tool on its own, or tools used one after another.
  enum Segment: Identifiable {
    case one(ConversationStep)
    case tools([ConversationStep])

    var id: EntityID {
      switch self {
      case .one(let step): step.id
      case .tools(let steps): steps[0].id
      }
    }
  }

  static func segments(_ steps: [ConversationStep]) -> [Segment] {
    var segments: [Segment] = []
    var tools: [ConversationStep] = []
    func close() {
      if tools.count == 1 { segments.append(.one(tools[0])) }
      if tools.count > 1 { segments.append(.tools(tools)) }
      tools = []
    }
    for step in steps {
      if case .tool = step.kind {
        tools.append(step)
      } else {
        close()
        segments.append(.one(step))
      }
    }
    close()
    return segments
  }

  /// A card with one thought that has not started to say anything yet.
  static var waiting: some View {
    HStack(spacing: 9) {
      SparkleMark(spinning: true).frame(width: 13)
      Shimmer(text: Text(.loci("conversation.thinkingNow"))).font(.system(size: 12))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .modifier(StepsBackground())
  }

  /// How long a step took: tenths under two seconds, whole seconds after.
  static func duration(_ took: Duration) -> String {
    let seconds = Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18
    if seconds < 2 { return String(format: "%.1fs", seconds) }
    if seconds < 60 { return "\(Int(seconds.rounded()))s" }
    return "\(Int(seconds) / 60)m \(Int(seconds) % 60)s"
  }
}

private struct Divider: View {
  var body: some View {
    Rectangle().fill(Palette.line).frame(height: Size.hairline)
  }
}

private struct StepsBackground: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(RoundedRectangle(cornerRadius: Radius.group, style: .continuous).fill(Palette.surface))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
          .strokeBorder(Palette.line, lineWidth: Size.hairline)
      }
      .clipShape(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
  }
}

/// The line every step row is drawn on: an icon, what it was, how long it took, and a chevron when it opens.
private struct StepLine<Label: View>: View {
  let icon: AnyView
  let took: Duration?
  let opens: Bool
  let open: Bool
  @ViewBuilder let label: Label

  var body: some View {
    HStack(spacing: 9) {
      icon.frame(width: 13)
      label
      Spacer(minLength: Spacing.xxs)
      if let took {
        Text(verbatim: StepsCard.duration(took)).font(.system(size: 10.5).monospaced())
          .foregroundStyle(Palette.inkFaint)
      }
      if opens {
        Image(systemName: Symbols.fold)
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(Palette.inkFaint)
          .rotationEffect(.degrees(open ? 90 : 0))
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .contentShape(Rectangle())
  }
}

/// Tools used one after another: what they did, counted; open, a row each.
private struct ToolRun: View {
  let steps: [ConversationStep]
  @State var open: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(Motion.fold) { open.toggle() }
      } label: {
        StepLine(icon: AnyView(icon), took: took, opens: true, open: open) { label }
      }
      .buttonStyle(.plain)
      if open {
        VStack(spacing: 0) {
          ForEach(steps) { step in
            Divider()
            StepRow(step: step)
          }
        }
        .padding(.leading, 22)
      }
    }
  }

  private var tools: [ToolActivity] {
    steps.compactMap { if case .tool(let tool) = $0.kind { tool } else { nil } }
  }

  private var going: Bool { steps.last?.isGoing == true && tools.last?.state == .running }

  private var took: Duration? {
    guard !going, let first = steps.first, let last = steps.last, let tail = last.took else { return nil }
    return .milliseconds(last.at.millisecondsSince1970 - first.at.millisecondsSince1970) + tail
  }

  @ViewBuilder private var icon: some View {
    let failed = tools.contains { $0.state == .failed }
    Image(systemName: failed ? Symbols.problem : Symbols.tools)
      .font(.system(size: 11))
      .foregroundStyle(failed ? Palette.accentInk : Palette.inkFaint)
  }

  @ViewBuilder private var label: some View {
    let phrases = ToolTally(tools).phrases.map { Text($0) }
    let text = phrases.dropFirst().reduce(phrases.first ?? Text(verbatim: "")) { whole, next in
      Text(joining: whole, Text(.loci("tools.separator")), next)
    }
    if going {
      Shimmer(text: text).font(.system(size: 12))
    } else {
      text.font(.system(size: 12)).foregroundStyle(Palette.inkMuted)
    }
  }
}

private struct StepRow: View {
  let step: ConversationStep
  @State private var open = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        guard !detail.isEmpty else { return }
        withAnimation(Motion.fold) { open.toggle() }
      } label: {
        StepLine(icon: AnyView(icon), took: step.took, opens: !detail.isEmpty, open: open) { label }
      }
      .buttonStyle(.plain)
      if open && !detail.isEmpty {
        Divider()
        ScrollView {
          Text(verbatim: detail)
            .font(isThinking ? .system(size: 12) : Typography.mono)
            .foregroundStyle(Palette.inkMuted)
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: Size.toolOutputHeight)
        .padding(.leading, 34)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
      }
    }
  }

  private var isThinking: Bool {
    if case .thinking = step.kind { true } else { false }
  }

  private var detail: String {
    switch step.kind {
    case .thinking(let text): text
    case .tool(let tool): Self.detail(of: tool)
    }
  }

  /// A command's output under the whole command, which the title shortens.
  private static func detail(of tool: ToolActivity) -> String {
    let title = ToolTitle(tool)
    guard title.action == .ran, let subject = tool.subject, subject != title.object else { return tool.output }
    return tool.output.isEmpty ? "$ \(subject)" : "$ \(subject)\n\n\(tool.output)"
  }

  @ViewBuilder private var icon: some View {
    switch step.kind {
    case .thinking:
      SparkleMark(spinning: step.isGoing)
    case .tool(let tool):
      Image(systemName: tool.state == .failed ? Symbols.problem : Self.symbol(ToolTitle(tool), tool.kind))
        .font(.system(size: 11))
        .foregroundStyle(tool.state == .failed ? Palette.accentInk : Palette.inkFaint)
    }
  }

  private static func symbol(_ title: ToolTitle, _ kind: ToolActivity.Kind) -> String {
    switch title.action {
    case .ran: Symbols.tool(.execute)
    case .searched: Symbols.web
    case .read, .edited, .created, .used: Symbols.tool(kind)
    }
  }

  @ViewBuilder private var label: some View {
    switch step.kind {
    case .thinking where step.isGoing:
      Shimmer(text: Text(.loci("conversation.thinkingNow"))).font(.system(size: 12))
    case .thinking:
      Text(.loci("conversation.thinking")).font(.system(size: 12)).foregroundStyle(Palette.inkMuted)
    case .tool(let tool):
      let title = Self.title(ToolTitle(tool))
      Group {
        if step.isGoing && tool.state == .running {
          Shimmer(text: title)
        } else {
          title.foregroundStyle(Palette.ink)
        }
      }
      .lineLimit(1)
      .truncationMode(.middle)
    }
  }

  private static func title(_ title: ToolTitle) -> Text {
    let object = Text(verbatim: title.object ?? "")
      .font(title.isCode ? .system(size: 11.5).monospaced() : .system(size: 12, weight: .medium))
    if case .used(let name) = title.action {
      let tool = Text(verbatim: name).font(.system(size: 11.5).monospaced())
      return title.object == nil
        ? tool : Text(joining: tool, Text(verbatim: " "), object.foregroundStyle(Palette.inkMuted))
    }
    guard let verb = title.verb else { return object }
    let said = Text(verb).font(.system(size: 12)).foregroundStyle(Palette.inkMuted)
    return title.object == nil ? said : Text(joining: said, Text(verbatim: " "), object)
  }
}

/// The four-pointed star that marks thinking, turning while the mentor thinks.
struct SparkleMark: View {
  let spinning: Bool

  var body: some View {
    TimelineView(.animation(paused: !spinning)) { timeline in
      Image(systemName: "sparkle")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Palette.accent)
        .rotationEffect(.degrees(spinning ? timeline.date.timeIntervalSinceReferenceDate * 120 : 0))
    }
  }
}
