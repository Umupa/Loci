import AppKit
import LociModel
import SwiftUI

extension LociModel.Host {
  /// Adds the link to the library and opens the new item. Whether it was added.
  @MainActor func addLink(
    _ url: URL, opened: (WindowState) -> Void, failed: (HostError) -> Void
  ) async -> Bool {
    do throws(HostError) {
      let item = try await run(AddLink(url: url))
      opened(WindowState(place: .library(nil), pages: [.item(item.id)]))
      return true
    } catch {
      failed(error)
      return false
    }
  }
}

/// The empty library: the start page's field, which makes a mentor from a sentence or adds a link.
struct LibraryStart: View {
  @Environment(\.host) private var host
  @FocusedValue(\.navigator) private var navigator
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  @State private var text = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      TextField(text: $text, prompt: Text(.loci("library.prompt")).foregroundStyle(Palette.inkFaint)) {
        Text(.loci("library.prompt"))
      }
      .textFieldStyle(.plain)
      .font(.system(size: 17))
      .foregroundStyle(Palette.ink)
      .frame(height: 28)
      .onSubmit(submit)
      HStack(spacing: Spacing.xxs) {
        IconButton(symbol: Symbols.attach, title: .loci("library.attach")) { navigator?.addFile?() }
        Spacer()
        RoundSendButton(ready: PromptInput(text) != .empty, action: submit)
      }
    }
    .padding(.top, 18)
    .padding([.trailing, .bottom], Spacing.s)
    .padding(.leading, 22)
    .frame(width: Size.startFieldWidth)
    .background(
      RoundedRectangle(cornerRadius: Spacing.l, style: .continuous).fill(Palette.surface)
        .shadow(color: Color(nsColor: NSColor(rgb: 0x281905)).opacity(0.1), radius: 22, y: 14)
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Spacing.l, style: .continuous)
        .strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
    )
    .offlineLineInstead(ruled: false)
    .padding(.bottom, 60)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func submit() {
    switch PromptInput(text) {
    case .empty:
      return
    case .link(let url):
      Task { if await host.addLink(url, opened: opened, failed: failed) { text = "" } }
    case .sentence(let request):
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
}

/// A square button with a symbol that darkens under the pointer.
struct IconButton: View {
  let symbol: String
  let title: LocalizedStringResource
  var size: CGFloat = Size.iconButton
  var symbolSize: CGFloat = 14
  var tint: Color = Palette.inkMuted
  var shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: symbolSize))
        .foregroundStyle(hovering ? Palette.ink : tint)
        .frame(width: size, height: size)
        .background(shape.fill(hovering ? Palette.fillStrong : .clear))
        .contentShape(shape)
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .help(Text(title))
    .accessibilityLabel(Text(title))
  }
}

/// The round amber send button; gray until there is something to send.
struct RoundSendButton: View {
  let ready: Bool
  var size: CGFloat = 30
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: Symbols.send)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(ready ? Palette.onAccent : Palette.inkFaint)
        .frame(width: size, height: size)
        .background(
          Circle().fill(
            ready
              ? AnyShapeStyle(
                RadialGradient(
                  colors: [Palette.accent.mix(with: .white, by: 0.4), Palette.accent],
                  center: UnitPoint(x: 0.35, y: 0.25),
                  startRadius: 0, endRadius: size * 0.7))
              : AnyShapeStyle(Palette.fillStrong))
        )
    }
    .buttonStyle(PressStyle())
    .disabled(!ready)
    .accessibilityLabel(Text(.loci("start.send")))
  }
}
