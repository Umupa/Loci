import SwiftUI

/// Back, forward and the start page; the address with its site in ink and the rest faint, and reload; then
/// what trails it. On the start page the address gives way to the start page's own field.
struct AddressBar<Trailing: View>: View {
  let session: BrowserSession
  let tab: BrowserTab
  @ViewBuilder let trailing: () -> Trailing
  @State private var editing: String?
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      IconButton(symbol: Symbols.back, title: .loci("browser.back"), tint: Palette.ink) { tab.back() }
        .disabled(!tab.canGoBack)
        .opacity(tab.canGoBack ? 1 : 0.35)
      IconButton(symbol: Symbols.forward, title: .loci("browser.forward"), tint: Palette.ink) { tab.forward() }
        .disabled(!tab.canGoForward || tab.atStart)
        .opacity(tab.canGoForward && !tab.atStart ? 1 : 0.35)
      IconButton(symbol: Symbols.home, title: .loci("browser.home"), tint: Palette.ink) { tab.home() }
        .disabled(tab.atStart)
        .opacity(tab.atStart ? 0.35 : 1)
      if tab.atStart {
        Spacer(minLength: 0)
      } else {
        field
      }
      trailing()
    }
    .frame(height: Size.addressHeight)
    .padding(.top, Spacing.s)
    .padding(.horizontal, 14)
    .padding(.bottom, 10)
    .onChange(of: session.addressFocus) { startEditing() }
  }

  private var field: some View {
    HStack(spacing: Spacing.xs) {
      if tab.address?.scheme == "https" {
        Image(systemName: Symbols.lock).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.inkFaint)
      }
      ZStack(alignment: .leading) {
        TextField(text: Binding(get: { editing ?? "" }, set: { editing = $0 })) { Text(.loci("browser.address")) }
          .textFieldStyle(.plain)
          .focused($focused)
          .opacity(focused ? 1 : 0)
          .onSubmit {
            if let editing { session.go(to: editing) }
            focused = false
          }
        if !focused {
          shownAddress.lineLimit(1).truncationMode(.tail).allowsHitTesting(false)
        }
      }
      .font(.system(size: 13))
      .contentShape(Rectangle())
      .onTapGesture(perform: startEditing)
      IconButton(symbol: Symbols.reload, title: .loci("browser.reload"), size: 24, symbolSize: 12) { tab.reload() }
    }
    .padding(.leading, 14)
    .padding(.trailing, 6)
    .frame(height: Size.addressHeight)
    .background(Capsule().fill(Palette.surface).shadow(color: .black.opacity(0.04), radius: 1, y: 1))
    .overlay(Capsule().strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
    .overlay(alignment: .bottom) { LoadingLine(progress: tab.progress) }
    .clipShape(Capsule())
    .padding(.horizontal, 6)
  }

  private func startEditing() {
    guard !tab.atStart else { return }
    editing = tab.address?.absoluteString
    focused = true
  }

  /// `youtube.com/@cncf/videos`: the site in ink, the rest faint.
  private var shownAddress: Text {
    guard let url = tab.address else { return Text(verbatim: "") }
    let host = (url.host() ?? "").replacing(/^www\./, with: "")
    var rest = url.path()
    if let query = url.query() { rest += "?" + query }
    if rest == "/" { rest = "" }
    return Text(
      joining: Text(verbatim: host).foregroundStyle(Palette.ink), Text(verbatim: rest).foregroundStyle(Palette.inkFaint)
    )
  }
}

/// An amber line along the lower edge of what shows a page's address while the page loads.
struct LoadingLine: View {
  let progress: Double?

  var body: some View {
    GeometryReader { space in
      Rectangle()
        .fill(Palette.accent)
        .frame(width: space.size.width * max(progress ?? 0, 0.08), height: 2)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .opacity(progress == nil ? 0 : 1)
        .animation(Motion.quick, value: progress)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

struct IconButton: View {
  let symbol: String
  let title: LocalizedStringResource
  var size: CGFloat = Size.iconButton
  var symbolSize: CGFloat = 14
  var tint: Color = Palette.inkMuted
  /// The language the glyph is drawn in, for a symbol SF Symbols would otherwise draw as a word.
  var glyphLocale: Locale?
  let action: () -> Void
  @Environment(\.locale) private var locale
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .environment(\.locale, glyphLocale ?? locale)
        .font(.system(size: symbolSize))
        .foregroundStyle(hovering ? Palette.ink : tint)
        .frame(width: size, height: size)
        .background(Circle().fill(hovering ? Palette.fillStrong : .clear))
        .contentShape(Circle())
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .help(Text(title))
    .accessibilityLabel(Text(title))
  }
}
