import SwiftUI

/// A tab before any page: one field that takes an address or a search, and sites to start from.
struct BrowserStart: View {
  let session: BrowserSession
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    VStack(spacing: 34) {
      HStack(spacing: Spacing.s) {
        Image(systemName: Symbols.search).font(.system(size: 15)).foregroundStyle(Palette.inkFaint)
        TextField(text: $text, prompt: Text(.loci("browser.prompt")).foregroundStyle(Palette.inkFaint)) {
          Text(.loci("browser.prompt"))
        }
        .textFieldStyle(.plain)
        .font(.system(size: 16))
        .focused($focused)
        .onSubmit {
          session.go(to: text)
          text = ""
        }
      }
      .padding(.horizontal, 20)
      .frame(width: Size.browserField.width, height: Size.browserField.height)
      .background(
        Capsule().fill(Palette.surface)
          .shadow(color: Color(nsColor: NSColor(rgb: 0x281905)).opacity(0.1), radius: 22, y: 14)
          .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
      )
      .overlay(Capsule().strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
      HStack(spacing: 30) {
        ForEach(StartSite.all, id: \.address) { site in
          Button {
            session.go(to: site.address)
          } label: {
            VStack(spacing: Spacing.xs) {
              let tile = RoundedRectangle(cornerRadius: 15, style: .continuous)
              Image(systemName: site.symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(site.ink)
                .frame(width: Size.siteTile, height: Size.siteTile)
                .background(Palette.surface, in: tile)
                .overlay(
                  tile.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
                )
                .accessibilityHidden(true)
              Text(site.name).font(.system(size: 12)).foregroundStyle(Palette.inkMuted)
            }
          }
          .buttonStyle(PressStyle())
        }
      }
    }
    .padding(.bottom, 80)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: session.addressFocus, initial: true) { focused = true }
  }
}

/// A site the browser's start page offers.
private struct StartSite {
  let name: LocalizedStringResource
  let address: String
  let symbol: String
  var ink = Palette.inkMuted

  static let all = [
    StartSite(
      name: .loci("site.youtube"), address: "https://www.youtube.com", symbol: "play.rectangle.fill",
      ink: Color(dark: 0xFF7973, light: 0xCA211F)),
    StartSite(
      name: .loci("site.bilibili"), address: "https://www.bilibili.com", symbol: "tv",
      ink: Color(dark: 0x7DCAEB, light: 0x16749F)),
    StartSite(
      name: .loci("site.xiaoyuzhou"), address: "https://www.xiaoyuzhoufm.com", symbol: "circle.circle"),
    StartSite(
      name: .loci("site.arxiv"), address: "https://arxiv.org", symbol: "text.book.closed",
      ink: Color(dark: 0xE49283, light: 0xA83C2F)),
  ]
}
