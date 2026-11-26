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
  @State private var items: Feed<[Item]>?
  @State private var jobs: Feed<[Job]>?
  @State private var choosing = false
  @State private var keeping = PageKeeping()

  private var tab: BrowserTab { session.current }

  var body: some View {
    VStack(spacing: 0) {
      if session.tabs.count > 1 { TabStrip(session: session) }
      AddressBar(session: session, tab: tab) {
        if let finds {
          KeepButton(finds: finds, choosing: choosing, keeping: keepingState) { click(finds) }.changesData()
        }
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
      } else {
        KeepNoteSlot(keeping: keeping, state: keepingState, session: session, keepAgain: keep)
          .padding(.top, session.tabs.count > 1 ? 50 + Size.tabHeight : 50)
          .padding(.trailing, 40)
      }
    }
    .background(Palette.canvas)
    .subscribing(AllItems(), into: $items)
    .subscribing(AllJobs(), into: $jobs)
    .onChange(of: items?.value) { _, library in keeping.noting(library ?? []) }
    .onChange(of: tab.address) {
      choosing = false
      keeping.forget()
    }
    .onChange(of: ObjectIdentifier(tab)) {
      choosing = false
      keeping.forget()
    }
    .onAppear {
      if standIns?.keepListOpen == true { choosing = true }
      if let standing = standIns?.keeping { keeping.stand(in: standing) }
    }
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

  private var keepingState: Keeping.State? {
    keeping.state(library: items?.value, jobs: jobs?.value ?? [])
  }

  private func click(_ finds: PageFinds) {
    switch keepingState {
    case .saving: return
    case .stopped, .refused:
      keeping.showNote()
      return
    case .saved, nil: break
    }
    switch finds.click {
    case .keepPage: keep(finds.left)
    case .choose: withAnimation(reduceMotion ? nil : Motion.quick) { choosing.toggle() }
    case .open(let item): openPage(.item(item))
    }
  }

  private func keep(_ chosen: [PageFinds.Find]) {
    withAnimation(reduceMotion ? nil : Motion.quick) { choosing = false }
    keeping.keep(
      chosen, from: tab, by: PageTaker(host: host, session: session, takeIn: takeIn, changesAllowed: changesAllowed))
  }
}

/// The page itself.
struct WebPage: NSViewRepresentable {
  let view: WKWebView

  func makeNSView(context: Context) -> WKWebView { view }
  func updateNSView(_ nsView: WKWebView, context: Context) {}
}
