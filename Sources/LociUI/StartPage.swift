import LociModel
import SwiftUI

/// One field: a sentence makes a mentor; a text file or a link dropped anywhere on the page becomes an item.
struct StartPage: View {
  @Environment(\.host) private var host
  @Environment(\.changesAllowed) private var changesAllowed
  let focusRequest: Int
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    PromptField(text: $text, submit: submit)
      .focused($focused)
      .offlineLineInstead(ruled: false)
      .padding(Spacing.xxl)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Palette.canvas)
      .acceptingDrops(opened: opened, failed: failed)
      .toolbar(removing: .title)
      .onAppear(perform: focus)
      .onChange(of: focusRequest, focus)
  }

  /// Puts the keyboard in the field, when there is a field: offline there is only a line, and the focus would
  /// land on whatever else takes it.
  private func focus() {
    if changesAllowed { focused = true }
  }

  private func submit() {
    switch PromptInput(text) {
    case .empty: return
    case .link(let url):
      Task {
        if await host.addLink(url, opened: opened, failed: failed) { text = "" }
      }
    case .sentence(let request):
      make(request)
    }
  }

  private func make(_ request: String) {
    Task {
      do throws(HostError) {
        let mentor = try await host.run(CreateMentor(request: request))
        text = ""
        opened(WindowState(place: .mentor(mentor.id)))
      } catch {
        failed(error)
      }
    }
  }
}

struct PromptField: View {
  @Binding var text: String
  let submit: () -> Void

  var body: some View {
    let input = PromptInput(text)
    HStack(spacing: Spacing.s) {
      TextField(text: $text, prompt: Text(.loci("start.prompt"))) { Text(.loci("start.prompt")) }
        .textFieldStyle(.plain)
        .font(Typography.prompt)
        .foregroundStyle(Palette.ink)
        .onSubmit(submit)
      SendButton(input: input, submit: submit)
    }
    .padding(.leading, Spacing.l)
    .padding(.trailing, Spacing.xs)
    .frame(height: Size.promptHeight)
    .frame(maxWidth: Size.promptMaximumWidth)
    .glassEffect(.regular, in: .capsule)
  }
}

private struct SendButton: View {
  let input: PromptInput
  let submit: () -> Void

  private var ready: Bool {
    input != .empty
  }

  private var isLink: Bool {
    if case .link = input { return true }
    return false
  }

  var body: some View {
    Button(action: submit) {
      Image(systemName: isLink ? Symbols.link : Symbols.send)
        .font(Typography.bodyEmphasis)
        .frame(width: Size.sendButton / 2, height: Size.sendButton / 2)
    }
    .buttonStyle(.glassProminent)
    .buttonBorderShape(.circle)
    .tint(Palette.accent)
    .disabled(!ready)
    .help(isLink ? Text(.loci("start.addLink")) : Text(.loci("start.send")))
    .accessibilityLabel(Text(.loci("start.send")))
  }
}
