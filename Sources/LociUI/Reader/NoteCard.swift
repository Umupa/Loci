import LociModel
import SwiftUI

/// One highlight in the panel: the words it marks, the thought, and each question with its answer.
struct NoteCard: View {
  @Environment(\.host) private var host
  let content: ContentRef
  let placed: PlacedNote
  let mentors: [Mentor]
  /// Changes each time the highlight is chosen in the text, which outlines and flashes the card.
  let chosen: Int?
  /// Hands the highlight to the mentor's composer; `nil` where there is no mentor or the words are gone.
  let ask: (() -> Void)?
  let select: () -> Void
  @State private var editing = false
  @State private var draft = ""
  @State private var flashing = false
  @State private var hovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      excerpt
      if let thought = placed.note.thought, !editing {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(systemName: Symbols.thought).font(Typography.caption).foregroundStyle(Palette.inkFaint)
          Text(verbatim: thought)
        }
        .font(Typography.body)
        .foregroundStyle(Palette.inkMuted)
      }
      if editing { field }
      ForEach(Array(placed.note.exchanges.enumerated()), id: \.offset) { _, exchange in
        ExchangeView(exchange: exchange, mentor: mentors.first { $0.id == exchange.mentor })
      }
    }
    .textSelection(.enabled)
    .padding(.horizontal, 14)
    .padding(.vertical, 13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Radius.card).fill(Palette.surface))
    .background(
      RoundedRectangle(cornerRadius: Radius.card).fill(Palette.flash).opacity(flashing ? 1 : 0).padding(-1)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Radius.card).strokeBorder(
        chosen != nil ? Palette.accent.opacity(0.6) : hovering ? Palette.lineStrong : Palette.line,
        lineWidth: chosen != nil ? 1 : Size.hairline)
    )
    .shadow(color: .black.opacity(hovering || chosen != nil ? 0.06 : 0), radius: 8, y: 4)
    .contentShape(RoundedRectangle(cornerRadius: Radius.card))
    .onTapGesture(perform: select)
    .onHover { hovering = $0 }
    .contextMenu { menu }
    .onChange(of: chosen) { _, chosen in
      guard chosen != nil else { return }
      flashing = true
      Task {
        try? await Task.sleep(for: Motion.flashHold)
        withAnimation(Motion.flashFade) { flashing = false }
      }
    }
  }

  private var excerpt: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Quote(
        text: placed.note.excerpt ?? placed.note.locator.quote?.text ?? "", font: Typography.highlightQuote,
        at: placed.note.locator.time.map { MediaTime.text($0.start) }
      )
      .foregroundStyle(Palette.ink)
      if placed.range == nil {
        Label {
          Text(.loci("note.lost"))
        } icon: {
          Image(systemName: Symbols.problem)
        }
        .font(Typography.caption)
        .foregroundStyle(Palette.accentInk)
      }
    }
  }

  @ViewBuilder private var menu: some View {
    Button {
      draft = placed.note.thought ?? ""
      editing = true
    } label: {
      Text(placed.note.thought == nil ? .loci("note.writeThought") : .loci("note.editThought"))
    }
    if let ask {
      Button(action: ask) {
        Text(.loci("passage.ask"))
      }
    }
    Button(role: .destructive) {
      Task { _ = try? await host.run(DeleteNote(content: content, note: placed.id)) }
    } label: {
      Text(.loci("note.delete"))
    }
  }

  private var field: some View {
    TextField(text: $draft, axis: .vertical) {
      Text(.loci("passage.thoughtPrompt"))
    }
    .textFieldStyle(.plain)
    .font(Typography.body)
    .lineLimit(1...6)
    .onSubmit(save)
    .onExitCommand { editing = false }
  }

  private func save() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    editing = false
    Task {
      _ = try? await host.run(SetNoteThought(content: content, note: placed.id, thought: text.isEmpty ? nil : text))
    }
  }
}

/// Words quoted from the text: serif, behind an amber bar.
struct Quote: View {
  let text: String
  var font = Typography.quote
  /// Where in a video or audio item the words are said, before them.
  var at: String?

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      RoundedRectangle(cornerRadius: 1).fill(Palette.accent.opacity(0.8)).frame(width: 2)
      if let at {
        Text(
          joining: Text(verbatim: at + " ").font(Typography.mono).foregroundStyle(Palette.accentInk),
          Text(verbatim: text).font(font)
        )
        .lineSpacing(3)
      } else {
        Text(verbatim: text).font(font).lineSpacing(3)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// A question asked about a highlight and the mentor's answer, under a hairline.
private struct ExchangeView: View {
  let exchange: Note.Exchange
  let mentor: Mentor?

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(verbatim: exchange.question).fontWeight(.semibold).foregroundStyle(Palette.ink)
      HStack(alignment: .top, spacing: 7) {
        if let mentor { Avatar(mentor: mentor, size: Size.avatarTiny).padding(.top, 2) }
        RichText(markdown: exchange.answer, font: Typography.body).foregroundStyle(Palette.inkMuted)
      }
    }
    .font(Typography.body)
    .padding(.top, 9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: Size.hairline) }
  }
}

extension Locator {
  /// The stretch of a video or audio item it points at.
  var time: TimeSpan? {
    if case .item(_, .time(let span)) = self { return span }
    return nil
  }
}
