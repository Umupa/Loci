import AppKit
import LociModel
import SwiftUI

/// One highlight in the panel: the words and pictures it marks, the thought, and each question with its answer.
/// A click finds it in the text; the card chosen last keeps a field for its thought at its foot.
struct NoteCard: View {
  @Environment(\.host) private var host
  @Environment(\.showFailure) private var showFailure
  @Environment(\.changesAllowed) private var changesAllowed
  let content: ContentRef
  let placed: PlacedNote
  /// The item's pictures by their address, for the pictures the highlight covers.
  var images: [String: NSImage] = [:]
  /// Whether it is the card chosen last, in the panel or in the text.
  let selected: Bool
  /// Just made from a picture, with nothing to type a thought into but this card: its field takes typing at once.
  var writing = false
  /// Changes each time the highlight is chosen in the text, which flashes the card.
  let flash: Int?
  /// Hands the highlight to Loci's composer; `nil` where the words are gone.
  let ask: (() -> Void)?
  let select: () -> Void
  @State private var editing = false
  @State private var draft = ""
  @State private var flashing = false
  @State private var hovering = false
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      marked
      if let thought = placed.note.thought, !editing {
        Text(verbatim: thought)
          .font(Typography.body)
          .foregroundStyle(Palette.inkMuted)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .onTapGesture { edit(thought) }
          .underCard()
      }
      if editing || (selected && placed.note.thought == nil && changesAllowed) {
        field.underCard().transition(.opacity.combined(with: .move(edge: .top)))
      }
      ForEach(Array(placed.note.exchanges.enumerated()), id: \.offset) { _, exchange in
        ExchangeView(exchange: exchange)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Radius.card).fill(Palette.surface))
    .background(
      RoundedRectangle(cornerRadius: Radius.card).fill(Palette.flash).opacity(flashing ? 1 : 0).padding(-1)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Radius.card).strokeBorder(
        selected ? Palette.accent.opacity(0.6) : hovering ? Palette.lineStrong : Palette.line,
        lineWidth: selected ? 1 : Size.hairline)
    )
    .shadow(color: .black.opacity(hovering || selected ? 0.06 : 0), radius: 8, y: 4)
    .contentShape(RoundedRectangle(cornerRadius: Radius.card))
    .onTapGesture(perform: select)
    .onHover { hovering = $0 }
    .contextMenu { menu }
    .animation(Motion.standard, value: selected)
    .task(id: writing) { if writing, changesAllowed { focused = true } }
    .onChange(of: selected) { _, selected in if !selected { editing = false } }
    .onChange(of: flash) { _, flash in
      guard flash != nil else { return }
      flashing = true
      Task {
        try? await Task.sleep(for: Motion.flashHold)
        withAnimation(Motion.flashFade) { flashing = false }
      }
    }
  }

  private var marked: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if let words = placed.words {
        Quote(
          text: words, font: Typography.highlightQuote, at: placed.note.locator.time.map { MediaTime.text($0.start) }
        )
        .foregroundStyle(Palette.ink)
      }
      if !placed.pictures.isEmpty { NotePictures(addresses: placed.pictures, images: images) }
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
    if let words = placed.words {
      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(words, forType: .string)
      } label: {
        Text(.loci("note.copy"))
      }
    }
    if let ask {
      Button(action: ask) {
        Text(.loci("passage.ask"))
      }
    }
    Button(role: .destructive) {
      run(DeleteNote(content: content, note: placed.id))
    } label: {
      Text(.loci("note.delete"))
    }
    .changesData()
  }

  private var field: some View {
    TextField(text: $draft, axis: .vertical) {
      Text(.loci("passage.thoughtPrompt"))
    }
    .textFieldStyle(.plain)
    .font(Typography.body)
    .foregroundStyle(Palette.ink)
    .lineLimit(1...6)
    .focused($focused)
    .onSubmit(save)
    .onExitCommand {
      editing = false
      draft = ""
    }
  }

  private func edit(_ thought: String) {
    guard changesAllowed else { return }
    select()
    draft = thought
    editing = true
    focused = true
  }

  private func save() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let thought = text.isEmpty ? nil : text
    editing = false
    draft = ""
    guard thought != placed.note.thought else { return }
    run(SetNoteThought(content: content, note: placed.id, thought: thought))
  }

  private func run<C: Command>(_ command: C) {
    Task {
      do throws(HostError) {
        _ = try await host.run(command)
      } catch {
        showFailure(error)
      }
    }
  }
}

extension View {
  /// A part of a highlight's card under its words, set off by a hairline.
  fileprivate func underCard() -> some View {
    padding(.top, 9)
      .padding(.top, 10)
      .overlay(alignment: .top) {
        Rectangle().fill(Palette.line).frame(height: Size.hairline).padding(.top, 10)
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
          Text(serif: text, font)
        )
        .lineSpacing(3)
      } else {
        Text(serif: text, font).lineSpacing(3)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// A question asked about a highlight and Loci's answer, under a hairline.
private struct ExchangeView: View {
  let exchange: Note.Exchange

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(verbatim: exchange.question).fontWeight(.semibold).foregroundStyle(Palette.ink)
      HStack(alignment: .top, spacing: 7) {
        LociAvatar(size: Size.avatarTiny).padding(.top, 2)
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
