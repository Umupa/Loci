import AppKit
import LociModel
import SwiftUI
import WebKit

/// The built-in browser: the tabs when there are several, an address bar with the library button beside it
/// (`KeepButton`, with `KeepList` under it), and the page. A tab with no page shows a search field and a few
/// sites to start from.
struct BrowserScreen: View {
  @Environment(\.host) private var host
  let session: BrowserSession
  @Environment(\.standIns) private var standIns
  @Environment(\.takeIn) private var takeIn
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.openPage) private var openPage
  @Environment(\.reducesMotion) private var reduceMotion
  let failed: (HostError) -> Void
  @State private var items: Feed<[Item]>?
  @State private var choosing = false

  private var tab: BrowserTab { session.current }

  var body: some View {
    VStack(spacing: 0) {
      if session.tabs.count > 1 { TabStrip(session: session) }
      AddressBar(session: session, tab: tab) {
        if let finds { KeepButton(finds: finds, choosing: choosing) { click(finds) }.changesData() }
        IconButton(symbol: Symbols.add, title: .loci("browser.newTab"), tint: Palette.ink) { session.newTab() }
      }
      if tab.atStart {
        BrowserStart(session: session)
      } else {
        page
          .id(ObjectIdentifier(tab))
          .clipShape(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
              .strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
          )
          .padding([.horizontal, .bottom], Spacing.s)
      }
    }
    .overlay(alignment: .topTrailing) {
      if choosing, let finds {
        KeepList(finds: finds, site: tab.address?.host(), keep: keep) { find in
          let shown = tab
          Task { await shown.point(at: find?.kind == .page ? nil : find?.url) }
        }
        .changesData()
        .padding(.top, session.tabs.count > 1 ? 50 + Size.tabHeight : 50)
        .padding(.trailing, 40)
        .transition(reduceMotion ? .identity : .scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity))
      }
    }
    .background(Palette.canvas)
    .subscribing(AllItems(), into: $items)
    .onChange(of: tab.address) { choosing = false }
    .onChange(of: ObjectIdentifier(tab)) { choosing = false }
    .onAppear { if standIns?.keepListOpen == true { choosing = true } }
    .onExitCommand { if choosing { withAnimation(reduceMotion ? nil : Motion.quick) { choosing = false } } }
    .task { await session.checkSignIns() }
    .focusedSceneValue(\.browserCommands, commands)
  }

  private var commands: BrowserCommands {
    BrowserCommands(
      newTab: session.newTab, closeTab: session.tabs.count > 1 ? { session.close(session.current) } : nil,
      openLocation: session.focusAddress, reload: tab.atStart ? nil : { session.current.reload() })
  }

  @ViewBuilder private var page: some View {
    if let picture = standIns?.webPage {
      Color.clear
        .overlay(alignment: .top) { Image(nsImage: picture).resizable().scaledToFill() }
        .clipped()
    } else {
      WebPage(view: session.webView(for: tab))
    }
  }

  private var finds: PageFinds? {
    guard !tab.atStart, let address = tab.address else { return nil }
    let title = tab.title.isEmpty ? (address.host() ?? address.absoluteString) : tab.title
    return PageFinds(at: address, title: title, facts: tab.facts, library: items?.value ?? [])
  }

  private func click(_ finds: PageFinds) {
    switch finds.click {
    case .keepPage: keep(finds.left)
    case .choose: withAnimation(reduceMotion ? nil : Motion.quick) { choosing.toggle() }
    case .open(let item): openPage(.item(item))
    }
  }

  private func keep(_ chosen: [PageFinds.Find]) {
    withAnimation(reduceMotion ? nil : Motion.quick) { choosing = false }
    let taker = PageTaker(
      host: host, session: session, takeIn: takeIn, failed: failed, changesAllowed: changesAllowed)
    let page = tab
    Task {
      await page.point(at: nil)
      await taker.keep(chosen, from: page)
    }
  }
}

/// The page itself.
struct WebPage: NSViewRepresentable {
  let view: WKWebView

  func makeNSView(context: Context) -> WKWebView { view }
  func updateNSView(_ nsView: WKWebView, context: Context) {}
}
