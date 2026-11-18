import LociModel
import SwiftUI

/// One field: a sentence makes a mentor; a text file dropped anywhere on the page becomes an item.
struct StartPage: View {
  @Environment(\.host) private var host
  let focusRequest: Int
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    PromptField(text: $text, submit: submit)
      .focused($focused)
      .padding(Spacing.xxl)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Palette.canvas)
      .acceptingTextFiles(opened: opened, failed: failed)
      .acceptingLinks(opened: opened, failed: failed)
      .toolbar(removing: .title)
      .onAppear { focused = true }
      .onChange(of: focusRequest) { focused = true }
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

extension View {
  /// Turns text files dropped on the view into items, then opens the last one.
  func acceptingTextFiles(opened: @escaping (WindowState) -> Void, failed: @escaping (HostError) -> Void)
    -> some View
  {
    modifier(AcceptingTextFiles(opened: opened, failed: failed))
  }
}

private struct AcceptingTextFiles: ViewModifier {
  @Environment(\.host) private var host
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void

  func body(content: Content) -> some View {
    content.dropDestination(for: TextFile.self) { files, _ in
      Task { await add(files) }
      return !files.isEmpty
    }
  }

  private func add(_ files: [TextFile]) async {
    var last: Item?
    for file in files {
      do throws(HostError) {
        last = try await host.run(AddTextItem(fileName: file.fileName, text: file.text))
      } catch {
        failed(error)
      }
    }
    if let last { opened(WindowState(place: .library(nil), pages: [.item(last.id)])) }
  }
}
