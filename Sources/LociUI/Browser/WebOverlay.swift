import LociModel
import SwiftUI

/// A web page Loci linked to, opened over the conversation rather than in the browser: a card about seven
/// tenths of the conversation's size with the conversation blurred behind it. Along its top, going back, the
/// site, saving the page to the library, opening it in the browser, and closing it. Esc or a click outside
/// closes it and leaves the conversation where it was.
struct WebOverlay: View {
  @Environment(\.host) private var host
  @Environment(\.takeIn) private var takeIn
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.showFailure) private var showFailure
  @Environment(\.openPage) private var openPage
  @Environment(\.openPlace) private var openPlace
  @Environment(\.standIns) private var standIns
  let session: BrowserSession
  let tab: BrowserTab
  let close: () -> Void
  @State private var items: Feed<[Item]>?

  var body: some View {
    VStack(spacing: 0) {
      bar.background(Palette.menuFace)
      page.background(Palette.surface)
    }
    .background(Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
        .strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
    )
    .compositingGroup()
    .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
    .subscribing(AllItems(), into: $items)
  }

  private var bar: some View {
    HStack(spacing: Spacing.xxs) {
      IconButton(symbol: Symbols.back, title: .loci("browser.back"), tint: Palette.ink) { tab.back() }
        .disabled(!tab.canGoBack)
        .opacity(tab.canGoBack ? 1 : 0.35)
      if let site {
        SiteBadge(site: site, size: 18, ring: .clear).padding(.leading, Spacing.xxs)
        Text(verbatim: site)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Palette.ink)
          .lineLimit(1)
          .truncationMode(.middle)
          .padding(.leading, 6)
      }
      Spacer(minLength: Spacing.s)
      saveButton.changesData()
      IconButton(
        symbol: Symbols.external, title: .loci("overlay.openInBrowser"), tint: Palette.ink, action: openInBrowser)
      IconButton(symbol: Symbols.cancel, title: .loci("overlay.close"), tint: Palette.ink, action: close)
        .keyboardShortcut(.cancelAction)
    }
    .padding(.horizontal, 10)
    .frame(height: Self.barHeight)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Palette.line).frame(height: Size.hairline)
    }
    .overlay(alignment: .bottom) { LoadingLine(progress: tab.progress) }
  }

  @ViewBuilder private var saveButton: some View {
    if case .inLibrary(let item) = offer {
      PrimaryButton(action: { openPage(.item(item)) }, label: { Text(.loci("browser.showInLibrary")) })
    } else {
      PrimaryButton(
        action: save,
        label: {
          Image(systemName: Symbols.add).font(.system(size: 12, weight: .semibold))
          Text(.loci("overlay.save"))
        })
    }
  }

  @ViewBuilder private var page: some View {
    if let picture = standIns?.webPage {
      Color.clear
        .overlay(alignment: .top) { Image(nsImage: picture).resizable().scaledToFill() }
        .clipped()
        .contentShape(Rectangle())
    } else {
      WebPage(view: session.webView(for: tab))
    }
  }

  /// The page's site, without `www.`.
  private var site: String? {
    guard let host = tab.address?.host() else { return nil }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }

  private var offer: PageOffer? {
    guard let address = tab.address else { return nil }
    return PageOffer(at: address, facts: tab.facts, library: items?.value ?? [])
  }

  private func save() {
    let taker = PageTaker(
      host: host, session: session, takeIn: takeIn, failed: showFailure.callAsFunction,
      changesAllowed: changesAllowed)
    let page = tab
    if offer == .video, let address = page.address {
      Task { await taker.takeVideos([address]) }
    } else {
      Task { await taker.addPage(in: page) }
    }
  }

  /// The page goes into the browser as its tab in front, with its way back, and the browser shows.
  private func openInBrowser() {
    session.keep(tab)
    close()
    openPlace(.browser)
  }

  static let barHeight: CGFloat = 46
}

/// Opens a web link over the conversation it was clicked in.
struct PeekLink {
  let action: (URL) -> Void

  func callAsFunction(_ url: URL) {
    action(url)
  }
}

extension EnvironmentValues {
  /// Set by a conversation that opens web links over itself; elsewhere a link goes to the browser.
  @Entry var peekLink: PeekLink?
}

extension View {
  /// Opens the web links clicked in this view over it, in a `WebOverlay`.
  func peekingLinks() -> some View {
    modifier(PeekingLinks())
  }
}

private struct PeekingLinks: ViewModifier {
  @Environment(\.browser) private var browser
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.standIns) private var standIns
  @State private var tab: BrowserTab?

  func body(content: Content) -> some View {
    if let browser {
      content
        .blur(radius: tab == nil ? 0 : 14)
        .allowsHitTesting(tab == nil)
        .environment(\.peekLink, PeekLink { url in open(url, in: browser) })
        .overlay { if let tab { overlay(tab, in: browser) } }
        .animation(reduceMotion ? nil : Motion.standard, value: tab.map(ObjectIdentifier.init))
        .onAppear {
          if let url = standIns?.overlayPage, tab == nil { tab = browser.peek(url) }
        }
        .onDisappear { close(in: browser) }
    } else {
      content
    }
  }

  private func overlay(_ shown: BrowserTab, in browser: BrowserSession) -> some View {
    GeometryReader { space in
      ZStack {
        Button {
          close(in: browser)
        } label: {
          Palette.pageScrim
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(Text(.loci("overlay.close")))
        .transition(reduceMotion ? .identity : .opacity)
        WebOverlay(session: browser, tab: shown) { close(in: browser) }
          .frame(width: Self.side(of: space.size.width), height: Self.side(of: space.size.height))
          .transition(reduceMotion ? .identity : .scale(scale: 0.96).combined(with: .opacity))
      }
      .frame(width: space.size.width, height: space.size.height)
    }
    .onExitCommand { close(in: browser) }
  }

  private func open(_ url: URL, in browser: BrowserSession) {
    if let tab { browser.endPeek(tab) }
    tab = browser.peek(url)
  }

  private func close(in browser: BrowserSession) {
    guard let shown = tab else { return }
    browser.endPeek(shown)
    tab = nil
  }

  /// Seven tenths of the room, or nearly all of it where seven tenths would be too narrow to read.
  static func side(of room: CGFloat) -> CGFloat {
    let margin = Spacing.m
    return min(max(room * 0.7, min(room - 2 * margin, 520)), room - 2 * margin)
  }
}
