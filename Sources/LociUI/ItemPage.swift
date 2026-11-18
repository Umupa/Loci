import AppKit
import LociModel
import SwiftUI

/// An item, read the way its kind is read: an article as text, a paper as its PDF, a video or podcast with
/// its player.
struct ItemScreen: View {
  let item: EntityID
  @State private var feed: Feed<ItemPage>?

  var body: some View {
    Group {
      if let page = feed?.value {
        switch page.item.kind {
        case .video, .audio: MediaScreen(item: page.item).id(page.item.id)
        case .paper: PaperScreen(page: page)
        case .article, .repository: ItemView(page: page)
        }
      } else {
        Palette.canvas
      }
    }
    .subscribing(OneItem(item: item), into: $feed)
  }
}

/// An item's text, with its byline under the title, its pictures, and the lessons that cite it beside it.
struct ItemView: View {
  @Environment(\.host) private var host
  let page: ItemPage
  @State private var images: [String: NSImage] = [:]
  @State private var job: Feed<Job?>?

  var body: some View {
    Group {
      if let text = page.text {
        ContentReader(
          content: .item(page.item.id), title: page.item.title, markdown: text, byline: Byline.of(page.item),
          images: images, serif: true, pane: .itemPanel
        ) {
          CitingLessons(page: page)
        }
      } else {
        FetchingItem(item: page.item, job: job?.value ?? nil)
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

/// The lessons that cite an item, one row per lesson however many places it cites.
struct CitingLessons: View {
  let page: ItemPage

  var body: some View {
    if !citing.isEmpty {
      PanelLinks(title: Text(.loci("item.citedBy"))) {
        ForEach(citing, id: \.citation.lesson) { citing in
          NavigationLink(value: Page.lesson(citing.citation.lesson)) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
              Text(verbatim: citing.lessonTitle ?? citing.citation.lesson.lesson.description)
                .foregroundStyle(Palette.ink)
              Text(verbatim: citing.mentorName)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
            }
          }
        }
      }
    }
  }

  private var citing: [CitingLesson] {
    var seen = Set<LessonRef>()
    return page.citedBy.filter { seen.insert($0.citation.lesson).inserted }
  }
}

/// An item whose text has not arrived: what is happening to it, or what would fix it.
struct FetchingItem: View {
  @Environment(\.host) private var host
  @Environment(\.openPlace) private var openPlace
  @Environment(\.browser) private var browser
  @Environment(\.showFailure) private var showFailure
  let item: Item
  let job: Job?

  var body: some View {
    VStack(spacing: Spacing.s) {
      Text(verbatim: item.title)
        .font(Typography.mediaTitle)
        .foregroundStyle(Palette.ink)
        .multilineTextAlignment(.center)
      JobDetail(line: JobLine(job)) { fix in
        JobFixes(host: host, openPlace: openPlace, browser: browser, failed: showFailure).apply(fix, to: item)
      }
    }
    .padding(Spacing.xxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
  }
}

/// The line under an article's title: its authors, then site and date in a fixed-width face, then a link to the
/// original.
enum Byline {
  static func of(_ item: Item) -> NSAttributedString? {
    let line = NSMutableAttributedString()
    let mono = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
    let faint: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: Tones.inkFaint]
    func separate() {
      if line.length > 0 { line.append(NSAttributedString(string: "  ·  ", attributes: faint)) }
    }
    if !item.authors.isEmpty {
      line.append(
        NSAttributedString(
          string: item.authors.joined(separator: ", "),
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
    return line.length > 0 ? line : nil
  }
}
