import AppKit
import LociModel
import SwiftUI

/// An item, read the way its kind is read: an article as text, a paper as its PDF, a video or podcast with
/// its player.
struct ItemScreen: View {
  let destination: Page
  @State private var feed: Feed<ItemPage>?

  var body: some View {
    if let item = destination.itemID {
      screen.subscribing(OneItem(item: item), into: $feed)
    } else {
      Palette.canvas
    }
  }

  @ViewBuilder private var screen: some View {
    if let page = feed?.value {
      switch page.item.kind {
      case .video, .audio:
        MediaScreen(item: page.item, initialTime: destination.locator?.time?.start).id(page.item.id)
      case .paper: PaperScreen(page: page)
      case .article, .repository: ItemView(page: page, openingQuote: destination.locator?.quote)
      }
    } else {
      Palette.canvas
    }
  }
}

/// An item's text, with its byline under the title and its pictures, and Loci beside it.
struct ItemView: View {
  @Environment(\.companionName) private var name
  @Environment(\.locale) private var locale
  @Environment(\.host) private var host
  let page: ItemPage
  let openingQuote: TextQuote?
  @State private var images: [String: NSImage] = [:]
  @State private var job: Feed<Job?>?
  @State private var openedWhileFetching = false

  var body: some View {
    Group {
      if let text = page.text {
        ContentReader(
          content: .item(page.item.id), title: page.item.title, markdown: text,
          byline: Byline.of(page.item, companion: name, locale: locale),
          images: images,
          serif: true, pane: .itemPanel,
          language: page.translatable
            ? ArticleLanguage(translation: page.translation, progress: page.translating) : nil,
          openingQuote: openingQuote,
          placeholder: openedWhileFetching ? FetchingItem(item: page.item, job: nil) : nil
        )
      } else {
        FetchingItem(item: page.item, job: job?.value ?? nil)
          .onAppear { openedWhileFetching = true }
      }
    }
    .subscribing(ItemJob(item: page.item.id), into: $job)
    .task(id: page.text) { await loadImages() }
  }

  /// Reads the pictures the article keeps beside it, once each.
  private func loadImages() async {
    guard let text = page.text else { return }
    for match in text.matches(of: /!\[[^\]]*\]\((images\/[^)\s]+)\)/) {
      let name = String(match.1)
      guard images[name] == nil,
        let data = try? await host.run(ReadItemImage(item: page.item.id, name: name)), let image = NSImage(data: data)
      else { continue }
      images[name] = image
    }
  }
}

/// An item whose text has not arrived: what is happening to it, or what would fix it.
struct FetchingItem: View {
  @Environment(\.host) private var host
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.openPlace) private var openPlace
  @Environment(\.browser) private var browser
  @Environment(\.showFailure) private var showFailure
  @AppStorage(ReadingWidth.key) private var readingWidth = ReadingWidth.comfortable
  let item: Item
  let job: Job?

  var body: some View {
    Group {
      if item.kind == .article {
        GeometryReader { frame in
          ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
              Text(serif: item.title, Serif.Face(size: ReadingStyle.articleTitleSize, weight: .semibold))
                .foregroundStyle(Palette.ink)
              if let source = item.site ?? item.source?.host()?.replacing(/^www\./, with: "") {
                Text(verbatim: source).font(Typography.mono).foregroundStyle(Palette.inkMuted)
              }
              if case .action(_, let problem) = JobLine(job) {
                details
                if problem != nil, let source = item.source {
                  Link(destination: source) { Text(.loci("job.openInBrowser")) }
                    .buttonStyle(PushStyle())
                }
              } else {
                skeleton
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, readingWidth.margin(in: frame.size.width))
            .padding(.vertical, Size.readingTop)
          }
        }
      } else {
        VStack(spacing: Spacing.s) {
          Text(serif: item.title, Typography.mediaTitle)
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.center)
          details
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Palette.canvas)
  }

  private var details: some View {
    JobDetail(line: JobLine(job)) { fix in
      JobFixes(
        host: host, openPlace: openPlace, browser: browser, failed: showFailure, changesAllowed: changesAllowed
      ).apply(fix, to: item)
    }
  }

  private var skeleton: some View {
    VStack(alignment: .leading, spacing: 13) {
      ForEach([1.0, 0.93, 0.59, 0.98, 0.87, 0.68], id: \.self) { width in
        GeometryReader { line in
          Capsule()
            .fill(Palette.fillStrong)
            .frame(width: line.size.width * width)
        }
        .frame(height: 8)
      }
    }
    .padding(.top, Spacing.l)
    .accessibilityHidden(true)
  }
}

/// The line under an article's title: its authors, then site and date in a fixed-width face, then a link to the
/// original; below it, why the reader took it in, in the serif's italic.
enum Byline {
  static func of(_ item: Item, companion: String, locale: Locale) -> NSAttributedString? {
    let line = NSMutableAttributedString()
    let mono = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
    let faint: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: Tones.inkFaint]
    func separate() {
      if line.length > 0 { line.append(NSAttributedString(string: "  ·  ", attributes: faint)) }
    }
    if !item.authors.isEmpty {
      var fallback = LocalizedStringResource.loci("companion.title")
      fallback.locale = locale
      let credit = companion.isEmpty ? String(localized: fallback) : companion
      line.append(
        NSAttributedString(
          string: item.writtenByCompanion ? credit : item.authors.joined(separator: ", "),
          attributes: [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: Tones.inkMuted]))
    }
    let place = item.site ?? item.source?.host()?.replacing(/^www\./, with: "")
    if let place {
      separate()
      line.append(NSAttributedString(string: place, attributes: faint))
    }
    if let published = item.published {
      separate()
      line.append(
        NSAttributedString(string: published.date.formatted(.iso8601.year().month().day()), attributes: faint))
    }
    if let source = item.source,
      let symbol = NSImage(systemSymbolName: Symbols.external, accessibilityDescription: nil)?
        .withSymbolConfiguration(
          .init(pointSize: 12, weight: .regular).applying(.init(hierarchicalColor: Tones.inkMuted)))
    {
      let attachment = NSTextAttachment()
      attachment.image = symbol
      attachment.bounds = CGRect(x: 0, y: -2, width: symbol.size.width, height: symbol.size.height)
      line.append(NSAttributedString(string: "  ", attributes: faint))
      let link = NSMutableAttributedString(attachment: attachment)
      link.addAttribute(.link, value: source, range: link.fullRange)
      line.append(link)
    }
    if let why = item.why {
      let serif = NSFont.serif(ofSize: 14.5)
      let italic = NSFont(descriptor: serif.fontDescriptor.withSymbolicTraits(.italic), size: 14.5) ?? serif
      line.append(
        NSAttributedString(
          string: (line.length > 0 ? "\n" : "") + why, attributes: [.font: italic, .foregroundColor: Tones.inkMuted]))
    }
    return line.length > 0 ? line : nil
  }
}
