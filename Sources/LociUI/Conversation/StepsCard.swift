import LociModel
import SwiftUI

/// The thinking and tools between two replies, one row each: what it was, what on, and how long it took.
struct StepsCard: View {
  let steps: [ConversationStep]

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
        if index > 0 { Rectangle().fill(Palette.line).frame(height: Size.hairline) }
        StepRow(step: step)
      }
    }
    .modifier(StepsBackground())
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

private struct StepRow: View {
  let step: ConversationStep
  @State private var open = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        guard !detail.isEmpty else { return }
        withAnimation(Motion.fold) { open.toggle() }
      } label: {
        HStack(spacing: 9) {
          icon.frame(width: 13)
          label
          Spacer(minLength: Spacing.xxs)
          if let took = step.took {
            Text(verbatim: StepsCard.duration(took)).font(.system(size: 10.5).monospaced())
              .foregroundStyle(Palette.inkFaint)
          }
          if !detail.isEmpty {
            Image(systemName: "chevron.right")
              .font(.system(size: 8, weight: .semibold))
              .foregroundStyle(Palette.inkFaint)
              .rotationEffect(.degrees(open ? 90 : 0))
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if open && !detail.isEmpty {
        Rectangle().fill(Palette.line).frame(height: Size.hairline)
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
    case .tool(let tool): tool.output
    }
  }

  @ViewBuilder private var icon: some View {
    switch step.kind {
    case .thinking:
      SparkleMark(spinning: step.isGoing)
    case .tool(let tool):
      Image(systemName: tool.state == .failed ? Symbols.problem : Symbols.tool(tool.kind))
        .font(.system(size: 11))
        .foregroundStyle(tool.state == .failed ? Palette.accentInk : Palette.inkFaint)
    }
  }

  @ViewBuilder private var label: some View {
    switch step.kind {
    case .thinking where step.isGoing:
      Shimmer(text: Text(.loci("conversation.thinkingNow"))).font(.system(size: 12))
    case .thinking:
      Text(.loci("conversation.thinking")).font(.system(size: 12)).foregroundStyle(Palette.inkMuted)
    case .tool(let tool):
      Text(verbatim: tool.subject ?? tool.name)
        .font(.system(size: 11.5).monospaced())
        .foregroundStyle(Palette.ink)
        .lineLimit(1)
        .truncationMode(.middle)
    }
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
