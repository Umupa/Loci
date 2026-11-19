import LociModel
import SwiftUI

/// The thinking and tools between two replies. Each thought is a row; tools used one after another fold
/// into one row that counts what they did, and open to a row each.
struct StepsCard: View {
  let steps: [ConversationStep]
  /// Folded runs of tools start open, for looking at them.
  var opened = false
  @State private var openDetails: Set<EntityID> = []

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Self.segments(steps)) { segment in
        switch segment {
        case .one(let step): StepRow(step: step, open: detail(for: step.id))
        case .tools(let steps):
          ToolRun(steps: steps, open: opened || openDetails.contains(segment.id), detail: detail(for:))
        }
      }
    }
  }

  private func detail(for id: EntityID) -> Binding<Bool> {
    Binding(
      get: { openDetails.contains(id) },
      set: { open in
        if open { openDetails.insert(id) } else { openDetails.remove(id) }
      })
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

  nonisolated static func segments(_ steps: [ConversationStep]) -> [Segment] {
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

  /// The status before there is a reply or a tool to show.
  static func working(since: Timestamp) -> some View {
    StepLine(activeSince: since) {
      Text(.loci("conversation.working"))
    }
  }

  /// How long a step took: tenths under two seconds, whole seconds after.
  static func duration(_ took: Duration, fractional: Bool = true) -> String {
    let seconds = Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18
    if fractional && seconds < 2 { return String(format: "%.1fs", seconds) }
    let whole = Int(seconds.rounded())
    if whole < 60 { return "\(whole)s" }
    return "\(whole / 60)m \(whole % 60)s"
  }
}

private struct Divider: View {
  var body: some View {
    Rectangle().fill(Palette.line).frame(height: Size.hairline)
  }
}

/// The line every step row is drawn on: an icon, what it was, how long it took, and a chevron when it opens.
private struct StepLine<Label: View>: View {
  var symbol: String?
  var activeSince: Timestamp?
  var took: Duration?
  var failure: LocalizedStringResource?
  var opens = false
  var open = false
  @ViewBuilder let label: Label

  var body: some View {
    HStack(spacing: 9) {
      Group {
        if let symbol {
          Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.inkMuted)
        } else {
          ActivityDots()
        }
      }
      .frame(width: ActivityDots.size.width, height: ActivityDots.size.height)
      .accessibilityHidden(true)
      label.font(.system(size: 12)).foregroundStyle(activeSince == nil ? Palette.inkMuted : Palette.ink)
      if let activeSince {
        if symbol != nil { ActivityDots() }
        ActivityElapsed(since: activeSince)
      }
      if let failure {
        Text(failure).font(.system(size: 11)).foregroundStyle(Palette.accentInk).fixedSize()
      }
      Spacer(minLength: Spacing.xxs)
      if let took, activeSince == nil {
        Text(verbatim: StepsCard.duration(took)).font(.system(size: 11).monospaced())
          .foregroundStyle(Palette.inkMuted)
          .fixedSize()
      }
      if opens {
        Image(systemName: Symbols.fold)
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Palette.inkMuted)
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
  let detail: (EntityID) -> Binding<Bool>
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let tally = ToolTally(tools)
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(reduceMotion ? nil : Motion.fold) { open.toggle() }
      } label: {
        StepLine(
          symbol: Symbols.tools, activeSince: active?.activeSince, took: took,
          failure: tally.failed > 0 ? .loci("tools.failed \(tally.failed)") : nil, opens: true, open: open
        ) { label(for: tally) }
      }
      .buttonStyle(.plain)
      if open {
        VStack(spacing: 0) {
          ForEach(steps) { step in
            Divider()
            StepRow(step: step, open: detail(step.id))
          }
        }
        .padding(.leading, 22)
      }
    }
  }

  private var tools: [ToolActivity] {
    steps.compactMap { if case .tool(let tool) = $0.kind { tool } else { nil } }
  }

  private var active: ConversationStep? { open ? nil : steps.last }

  private var took: Duration? {
    guard let first = steps.first, let last = steps.last, let tail = last.took else { return nil }
    return .milliseconds(last.at.millisecondsSince1970 - first.at.millisecondsSince1970) + tail
  }

  @ViewBuilder private func label(for tally: ToolTally) -> some View {
    if let active, active.activeSince != nil, case .tool(let tool) = active.kind {
      StepRow.title(ToolTitle(tool), running: true).lineLimit(1).truncationMode(.middle)
    } else {
      let phrases = tally.phrases.map { Text($0) }
      phrases.dropFirst().reduce(phrases.first ?? Text(verbatim: "")) { whole, next in
        Text(joining: whole, Text(.loci("tools.separator")), next)
      }
    }
  }
}

private struct StepRow: View {
  let step: ConversationStep
  @Binding var open: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        guard !detail.isEmpty else { return }
        withAnimation(reduceMotion ? nil : Motion.fold) { open.toggle() }
      } label: {
        StepLine(
          symbol: step.symbol, activeSince: step.activeSince, took: step.took, failure: failure,
          opens: !detail.isEmpty, open: open
        ) { label }
      }
      .buttonStyle(.plain)
      if open && !detail.isEmpty {
        ScrollView {
          Text(verbatim: detail)
            .font(isThinking ? .system(size: 12) : Typography.mono)
            .foregroundStyle(Palette.inkMuted)
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: Size.toolOutputHeight)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group))
        .padding(.leading, 39)
        .padding(.trailing, 12)
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

  private var failure: LocalizedStringResource? {
    guard case .tool(let tool) = step.kind, tool.state == .failed else { return nil }
    return .loci("tool.failed")
  }

  @ViewBuilder private var label: some View {
    switch step.kind {
    case .thinking where step.activeSince != nil:
      Text(.loci("conversation.working"))
    case .thinking:
      Text(.loci("conversation.thinking"))
    case .tool(let tool):
      Self.title(ToolTitle(tool), running: step.activeSince != nil)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  static func title(_ title: ToolTitle, running: Bool) -> Text {
    let object = title.object.map {
      Text(verbatim: $0).font(title.isCode ? .system(size: 11.5).monospaced() : .system(size: 12, weight: .medium))
    }
    let subject: Text?
    if case .used(let name) = title.action {
      let named = Text(verbatim: name).font(.system(size: 11.5).monospaced())
      subject = object.map { Text(joining: named, Text(verbatim: " "), $0.foregroundStyle(Palette.inkMuted)) } ?? named
    } else {
      subject = object
    }
    guard let verb = running ? title.runningVerb : title.verb else {
      return subject?.foregroundStyle(Palette.ink) ?? Text(verbatim: "")
    }
    let said = Text(verb)
    return subject.map { Text(joining: said, Text(verbatim: " "), $0.foregroundStyle(Palette.ink)) } ?? said
  }
}

extension ConversationStep {
  var symbol: String {
    switch kind {
    case .thinking:
      return Symbols.thinking
    case .tool(let tool):
      switch ToolTitle(tool).action {
      case .ran: return Symbols.tool(.execute)
      case .searched: return Symbols.web
      case .read, .edited, .created, .deleted, .used: return Symbols.tool(tool.kind)
      }
    }
  }
}
