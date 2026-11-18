import AppKit
import LociModel
import SwiftUI
import WebKit

/// The built-in browser: an address bar with what the page can become in the library beside it, and the page.
/// With no page open it is a search field and a few sites to start from.
struct BrowserScreen: View {
  @Environment(\.host) private var host
  let session: BrowserSession
  @Environment(\.standIns) private var standIns
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  @State private var items: Feed<[Item]>?
  @State private var picking = false

  var body: some View {
    Group {
      if session.address == nil {
        BrowserStart { session.go(to: $0) }
      } else {
        VStack(spacing: 0) {
          AddressBar(session: session) {
            if let offer { OfferButton(offer: offer, take: take).changesData() }
          }
          page
            .clipShape(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
                .strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
            )
            .padding([.horizontal, .bottom], Spacing.s)
        }
        .overlay(alignment: .topTrailing) {
          if picking, case .videos(let videos) = offer {
            VideoPicker(videos: videos, library: items?.value ?? []) { chosen in
              picking = false
              Task { await add(chosen) }
            }
            .changesData()
            .padding(.top, 50)
            .padding(.trailing, 14)
            .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
          }
        }
      }
    }
    .background(Palette.canvas)
    .subscribing(AllItems(), into: $items)
    .onChange(of: session.address) { picking = false }
    .onAppear { if standIns?.videoPickerOpen == true { picking = true } }
  }

  @ViewBuilder private var page: some View {
    if let picture = standIns?.webPage {
      Image(nsImage: picture).resizable().scaledToFill()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    } else {
      WebPage(view: session.webView)
    }
  }

  private var offer: PageOffer? {
    guard let address = session.address else { return nil }
    return PageOffer(at: address, facts: session.facts, library: items?.value ?? [])
  }

  private func take(_ offer: PageOffer) {
    switch offer {
    case .inLibrary(let item):
      opened(WindowState(place: .library(nil), pages: [.item(item)]))
    case .video, .add:
      guard let address = session.address else { return }
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

/// Back, forward, the address with its site in ink and the rest faint, reload, and what trails it.
struct AddressBar<Trailing: View>: View {
  let session: BrowserSession
  @ViewBuilder let trailing: () -> Trailing
  @State private var editing: String?
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      IconButton(
        symbol: Symbols.back, title: .loci("browser.back"), symbolSize: 14, tint: Palette.ink, shape: AnyShape(Circle())
      ) { session.back() }
      .disabled(!session.canGoBack)
      .opacity(session.canGoBack ? 1 : 0.35)
      IconButton(
        symbol: Symbols.forward, title: .loci("browser.forward"), symbolSize: 14, tint: Palette.ink,
        shape: AnyShape(Circle())
      ) { session.forward() }
      .disabled(!session.canGoForward)
      .opacity(session.canGoForward ? 1 : 0.35)
      field
      trailing()
    }
    .padding(.top, Spacing.s)
    .padding(.horizontal, 14)
    .padding(.bottom, 10)
  }

  private var field: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: Symbols.lock).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.inkFaint)
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
      .onTapGesture {
        editing = session.address?.absoluteString
        focused = true
      }
      IconButton(
        symbol: Symbols.reload, title: .loci("browser.reload"), size: 24, symbolSize: 12, shape: AnyShape(Circle())
      ) { session.reload() }
    }
    .padding(.leading, 14)
    .padding(.trailing, 6)
    .frame(height: Size.addressHeight)
    .background(Capsule().fill(Palette.surface).shadow(color: .black.opacity(0.04), radius: 1, y: 1))
    .overlay(Capsule().strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
    .padding(.horizontal, 6)
  }

  /// `youtube.com/@cncf/videos`: the site in ink, the rest faint.
  private var shownAddress: Text {
    guard let url = session.address else { return Text(verbatim: "") }
    let host = (url.host() ?? "").replacing(/^www\./, with: "")
    var rest = url.path()
    if let query = url.query() { rest += "?" + query }
    if rest == "/" { rest = "" }
    return Text(
      joining: Text(verbatim: host).foregroundStyle(Palette.ink), Text(verbatim: rest).foregroundStyle(Palette.inkFaint)
    )
  }
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
