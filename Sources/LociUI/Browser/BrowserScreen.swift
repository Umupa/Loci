import AppKit
import LociModel
import SwiftUI
import WebKit

/// The built-in browser: the tabs when there are several, an address bar with what the page can become in the
/// library beside it, and the page. A tab with no page shows a search field and a few sites to start from.
struct BrowserScreen: View {
  @Environment(\.host) private var host
  let session: BrowserSession
  @Environment(\.standIns) private var standIns
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  @State private var items: Feed<[Item]>?
  @State private var picking = false

  private var tab: BrowserTab { session.current }

  var body: some View {
    VStack(spacing: 0) {
      if session.tabs.count > 1 { TabStrip(session: session) }
      AddressBar(session: session, tab: tab) {
        if let offer { OfferButton(offer: offer, take: take).changesData() }
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
      if picking, case .videos(let videos) = offer {
        VideoPicker(videos: videos, library: items?.value ?? []) { chosen in
          picking = false
          Task { await add(chosen) }
        }
        .changesData()
        .padding(.top, session.tabs.count > 1 ? 50 + Size.tabHeight : 50)
        .padding(.trailing, 14)
        .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
      }
    }
    .background(Palette.canvas)
    .subscribing(AllItems(), into: $items)
    .onChange(of: tab.address) { picking = false }
    .onChange(of: ObjectIdentifier(tab)) { picking = false }
    .onAppear { if standIns?.videoPickerOpen == true { picking = true } }
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

  private var offer: PageOffer? {
    guard !tab.atStart, let address = tab.address else { return nil }
    return PageOffer(at: address, facts: tab.facts, library: items?.value ?? [])
  }

  private func take(_ offer: PageOffer) {
    switch offer {
    case .inLibrary(let item):
      opened(WindowState(place: .library(nil), pages: [.item(item)]))
    case .video, .add:
      guard let address = tab.address else { return }
      Task { await add([address], open: true) }
    case .videos:
      withAnimation(Motion.quick) { picking.toggle() }
    }
  }

  /// Hands the browser's sign-in to the host, then adds each link. One link opens; several stay in the list.
  private func add(_ links: [URL], open: Bool = false) async {
    if let first = links.first {
      let cookies = await session.cookies(for: first)
      if !cookies.isEmpty { _ = try? await host.run(HandOverBrowserCookies(cookies)) }
    }
    var last: Item?
    for link in links {
      do throws(HostError) {
        last = try await host.run(AddLink(url: link))
      } catch {
        failed(error)
      }
    }
    if open, let last { opened(WindowState(place: .library(nil), pages: [.item(last.id)])) }
  }
}

/// The page itself.
private struct WebPage: NSViewRepresentable {
  let view: WKWebView

  func makeNSView(context: Context) -> WKWebView { view }
  func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// The amber button for what the page can become.
struct OfferButton: View {
  let offer: PageOffer
  let take: (PageOffer) -> Void

  var body: some View {
    PrimaryButton(
      action: { take(offer) },
      label: {
        switch offer {
        case .inLibrary:
          Text(.loci("browser.showInLibrary"))
        case .video:
          Image(systemName: Symbols.download).font(.system(size: 12, weight: .semibold))
          Text(.loci("browser.downloadVideo"))
        case .videos(let videos):
          Image(systemName: Symbols.download).font(.system(size: 12, weight: .semibold))
          Text(
            joining: Text(.loci("browser.downloadVideo")), Text(verbatim: " · "),
            Text(verbatim: "\(videos.count)").font(.system(size: 12.5, weight: .semibold).monospaced()))
        case .add:
          Image(systemName: Symbols.add).font(.system(size: 12, weight: .semibold))
          Text(.loci("browser.add"))
        }
      })
  }
}

/// A capsule in amber, for the one thing a screen is for.
struct PrimaryButton<Label: View>: View {
  let action: () -> Void
  @ViewBuilder let label: () -> Label

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) { label() }
        .font(Typography.buttonStrong)
        .foregroundStyle(Palette.onAccent)
        .lineLimit(1)
        .padding(.leading, Spacing.s)
        .padding(.trailing, 14)
        .frame(height: Size.primaryHeight)
        .background(
          Capsule()
            .fill(
              LinearGradient(
                colors: [Palette.accent.mix(with: .white, by: 0.18), Palette.accent], startPoint: .top,
                endPoint: .bottom)
            )
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
        )
        .overlay(Capsule().strokeBorder(.black.opacity(0.12), lineWidth: Size.hairline))
        .fixedSize()
    }
    .buttonStyle(PressStyle())
  }
}
